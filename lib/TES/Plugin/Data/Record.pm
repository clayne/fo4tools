package TES::Plugin::Data::Record;
use parent 'TES::Plugin::Base';

use FindBin;
use lib "$FindBin::Bin/../lib";

use TES::Plugin::Data::Record::Field qw();
use TES::Plugin::Data::Record::Field::Parsed qw();

use IO::Compress::Deflate qw($DeflateError);
use IO::Uncompress::Inflate qw($InflateError);
use Scalar::Util qw(blessed weaken);
use File::Basename qw(basename dirname);
use File::stat qw(stat);
use Fcntl qw(SEEK_SET SEEK_CUR);
use Carp qw(confess);
use Data::Dumper;

use strict;
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;
sub fatal { local $SIG{__DIE__}; die @_, "\n" }

local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Useqq = 1;

our $VERSION = '$Id$';

use constant {
	F_COMPRESSED => (0x1 << 18),
};

my $class_tab = {
	GRUP => 'TES::Plugin::Data::Record::GRUP',
	TES4 => 'TES::Plugin::Data::Record::TES4',
	SCOL => 'TES::Plugin::Data::Record::SCOL',
};

sub is_compressed {
	my ($self, %opts) = @_;
	return (defined $self->flags) ? $self->flags & F_COMPRESSED : 0;
}

sub proc {
	my ($self, $cb, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	my $include = $opts{'include'};
	my $exclude = $opts{'exclude'};
	return unless ($self->size);

	if (defined $include) {
		if (!ref $include) {
			$include = { $include => 1 };
		} elsif (ref $include eq 'ARRAY') {
			$include = +{ map +($_, 1), @$include };
		}
	}

	if (defined $exclude) {
		if (!ref $exclude) {
			$exclude = { $exclude => 1 };
		} elsif (ref $exclude eq 'ARRAY') {
			$exclude = +{ map +($_, 1), @$exclude };
		}
	}

	my $sig = $self->signature;
	return 1 if ($include &&  $exclude->{$sig});
	return 1 if ($include && !$include->{$sig});

	return $self->$cb(%opts);
}

sub decompress {
	my ($self) = @_;
	my $uncompressed;

	my ($size, $compressed) = unpack('La*', substr($self->data, 0, $self->size));
	my $z = IO::Uncompress::Inflate->new(\$compressed, transparent => 0);
	if (!defined $z) {
		print STDERR Dumper { size => $size, data => substr($compressed, 0, 256) };
		die "IO::Uncompress::Inflate->new failed: $InflateError";
	}

	my $ret = $z->read($uncompressed, $size, 0);
	if ($ret < 0) {
		die "zlib read failed";
	} elsif ($ret == 0 && $size) {
		die "zlib read EOF";
	} elsif ($ret != $size) {
		print STDERR Dumper { size => $size, data => substr($uncompressed, 0, 256) };
		die "zlib decompressed buf length != expected size ($ret vs $size)";
	}
	$z->close;

	return $uncompressed;
}

sub compress {
	my ($self) = @_;
	my $compressed;

	my ($size, $uncompressed) = (length($self->data), $self->data);
	my $z = IO::Compress::Deflate->new(\$compressed);
	if (!defined $z) {
		print STDERR Dumper { size => $size, data => substr($uncompressed, 0, 256) };
		die "IO::Compress::Deflate->new failed: $DeflateError";
	}

	my $ret = $z->write($uncompressed, $size, 0);
	if (!$ret) {
		die "zlib write failed";
	} elsif ($ret != $size) {
		print STDERR Dumper {
			size => $size,
			uncompressed_len => length($uncompressed),
			uncompressed_data => substr($uncompressed, 0, 256),
			compressed_len => length($compressed),
			compressed_data => substr($compressed, 0, 256),
		};
		die "zlib decompressed buf length != expected size ($ret vs $size)";
	}
	$z->close;

	return pack('La*', $size, $compressed);
}

sub deserialize {
	my ($self, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	print STDERR Dumper __PACKAGE__,[$self->signature,length($self->data // ''),substr($self->data // '', 0, 256)]
		if ($verbose > 1);

	delete $self->{'parsed'};
	$self->{'fields'} = [];

	my $data_tab;
	if ($self->can('data_tab')) {
		$self->{'parsed'} = TES::Plugin::Data::Record::Field::Parsed->new(
			parent => $self,
		);
		$data_tab = $self->data_tab,
	}

	my $data = $self->is_compressed ? $self->decompress : $self->data;
	open(my $data_fd, '<', \$data) or die "open: $!";
	while (!eof($data_fd)) {
		my $field = TES::Plugin::Data::Record::Field->read($data_fd,
			%opts,
			data_tab => $data_tab,
			parsed => $self->parsed,
			parent => $self,
		);
		push @{$self->{'fields'}}, $field;
	}
	close($data_fd) or die "close: $!";

	return 1;
}

sub serialize {
	my ($self, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	return unless ($self->dirty);

	die("Assertion failed: records and fields") if ($self->records && $self->fields);
	die("Assertion failed: records vs group") if ($self->records);

	my $data_tab;
	if ($self->parsed) {
		$data_tab = $self->data_tab,
		$self->parsed->idx_map({});
	}

	open(my $data_fd, '>', \$self->data) or die "open: $!";
	if ((my $fields = $self->fields)) {
		foreach my $field (@$fields) {
			$field->write($data_fd,
				%opts,
				data_tab => $data_tab,
				parsed => $self->parsed,
			);
		}
	}
	close($data_fd) or die "close: $!";

	$self->parsed->dirty(0) if ($self->parsed);

	my $data = $self->is_compressed ? $self->compress : $self->data;
	$self->{'size'} = length($data);
	$self->{'data'} = $data;
	$self->dirty(0);
}

sub classify {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	my $parent = delete $opts{'parent'};

	# Could be either a GRUP record or a normal record
	my ($off, $bsz, $buf) = (0, 4);
	my $len = read($fd, $buf, $bsz) or die "read: $!";
	if ($len != $bsz) {
		die sprintf("len != bsz (len == %d, bsz == %d)", $len, $bsz);
	}
	seek($fd, -$bsz, SEEK_CUR) or die "seek: $!";

	my $sig = unpack('a4', substr($buf, 0, $bsz));
	if (!defined $sig) {
		fatal sprintf("%s: Unable to parse signature", __PACKAGE__);
	}

	my $class = $class_tab->{$sig};
	if (!$class) {
		printf STDERR ("%s: Unknown signature: '%s'\n", __PACKAGE__, $sig)
			if ($verbose);
		return $self;
	}

	eval "require $class" or die;
	return $class->new(%opts, parent => $parent);
}

sub total_size {
	my $self = shift;
	return $self->header_size + $self->size;
}

sub header_size {
	# a4 L L L C C C C S S
	return 4 + 4 + 4 + 4 + 1 + 1 + 1 + 1 + 2 + 2;
}

sub header_read {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	my ($off, $bsz, $buf) = (0, $self->header_size);
	my $len = read($fd, $buf, $bsz) or die "read: $!";
	if ($len != $bsz) {
		die sprintf("len != bsz (len == %d, bsz == %d)", $len, $bsz);
	}

	@$self{ qw(
		signature
		size
		flags
		formid
		vc_day
		vc_mon
		vc_user_last
		vc_user_cur
		version
		unknown
	) } = unpack("a4 L L L C C C C S S", substr($buf, $off, $bsz)); $off += $bsz;

	print STDERR Dumper __PACKAGE__,$self if ($verbose > 2);

}

sub header_write {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	print $fd pack("a4 L L L C C C C S S", map $self->{$_}, qw(
		signature
		size
		flags
		formid
		vc_day
		vc_mon
		vc_user_last
		vc_user_cur
		version
		unknown
	)) or die "print: $!";
}

sub read {
	my ($self, $fd, %opts) = @_;
	my $data_skip = $opts{'data_skip'};
	my $data_parse = $opts{'record_parse'} // $opts{'data_parse'};
	my $parent = delete $opts{'parent'};

	# If called with CLASS->read, create a new object.
	$self = $self->new(%opts, parent => $parent) if (!blessed($self));

	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	if (ref $self eq __PACKAGE__) {
		$self = $self->classify($fd, %opts, parent => $parent);
	}

	# header
	$self->header_read($fd, %opts);

	# data
	my ($off, $bsz, $buf) = (0, $self->size);
	if ($data_skip) {
		# XXX: Support STDIN
		seek($fd, $bsz, SEEK_CUR) or die "seek: $!";
		return $self;
	} elsif (!$bsz) {
		return $self;
	} else {
		my $len = read($fd, $buf, $bsz) or die "read: $!";
		if ($len != $bsz) {
			die sprintf("len != bsz (len == %d, bsz == %d)", $len, $bsz);
		}
	}

	$self->{'data'} = substr($buf, 0, $self->size);

	print STDERR Dumper __PACKAGE__, substr($self->data, 0, $self->size < 256 ? $self->size : 256)
		if ($verbose > 2);

	if ((my $parse = $data_parse) && defined $self->data) {
		if (ref $data_parse) {
			my %match = (ref $data_parse eq 'ARRAY')
				? map +($_ => 1), @$data_parse
				: %$data_parse;
			$parse = $self->group && $match{$self->label} || $match{$self->signature};
		}
		$self->deserialize(%opts) if ($parse);
	}

	print STDERR Dumper __PACKAGE__, [
		+{ map +($_, $self->{$_}), grep +($_ ne 'data'), keys %$self },
		substr($self->data, 0, $self->size < 256 ? $self->size : 256),
	] if ($verbose > 1);

	return $self;
}

sub write {
	my ($self, $fd, %opts) = @_;
	my $data_skip = $opts{'data_skip'};
	my $data_parse = $opts{'record_parse'} // $opts{'data_parse'};

	if ($self->dirty && (defined $self->records || defined $self->fields)) {
		$self->serialize(%opts);
	}

	# header

	$self->header_write($fd, %opts);

	# data

	if ($data_skip) {
		# XXX: Support STDIN
		seek($fd, $self->size, SEEK_CUR) or die "seek: $!";
	} elsif ($data_parse && ref $data_parse) {
		fatal "Attempt to write out partially parsed record";
	} elsif (defined $self->data) {
		print $fd $self->data or die "print: $!";
	} elsif ($self->size) {
		fatal "Record has no data";
	}

	return 1;
}

sub new {
	my ($class, %opts) = @_;
	my $parent = delete $opts{'parent'};
	map delete $opts{$_}, qw(data_skip data_parse record_parse field_parse verbose);

	my $self = bless { %opts }, ref $class || $class;

	if (defined $parent) {
		$self->parent($parent);
	}

	return $self;
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
		signature
		size
		flags
		formid
		vc_day
		vc_mon
		vc_user_last
		vc_user_cur
		version
		data
		group
		records
		fields
		parsed
	) }
);

1;

__END__
