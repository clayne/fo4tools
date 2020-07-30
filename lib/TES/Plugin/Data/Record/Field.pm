package TES::Plugin::Data::Record::Field;
use parent 'TES::Plugin::Base';

use FindBin;
use lib "$FindBin::Bin/../lib";

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

sub total_size {
	my $self = shift;
	return $self->header_size + $self->size;
}

sub header_size {
	# a4 S
	return 4 + 2;
}

sub read {
	my ($self, $fd, %opts) = @_;
	my $data_skip = $opts{'data_skip'};
	my $data_parse = $opts{'field_parse'} // $opts{'data_parse'};
	my $size_force = delete $opts{'size_force'};
	my $data_tab = delete $opts{'data_tab'};
	my $parsed = delete $opts{'parsed'};
	my $parent = delete $opts{'parent'};
	my ($off, $bsz, $buf);

	# If called with CLASS->read, create a new object.
	$self = $self->new(%opts, parent => $parent) if (!blessed($self));

	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	# header

	($off, $bsz, $buf) = (0, $self->header_size);
	my $len = read($fd, $buf, $bsz) or die "read: $!";
	if ($len != $bsz) {
		die sprintf("len != bsz (len == %d, bsz == %d)", $len, $bsz);
	}

	@$self{ qw(
		signature
		size
	) } = unpack("a4 S", substr($buf, $off, $bsz)); $off += $bsz;

	# XXXX fields
	if ($self->signature eq 'XXXX') {
		# 047185f0  01 01 58 58 58 58 04 00  04 46 02 00 4f 46 53 54  |..XXXX...F..OFST|
		# 04718600  00 00 0f 08 02 06 3e 07  02 06 cb 04 02 06 29 03  |......>.......).|
		# 04718610  02 06 87 01 02 06 e5 ff  01 06 43 fe 01 06 a1 fc  |..........C.....|
		#
		# XXXX<size-of-size><size><sig><size (always zero)><data>

		if ($self->size != 4) {
			fatal sprintf("%s: Unable to handle XXXX field with size == %d", __PACKAGE__, $self->size);
		}

		my ($off, $bsz, $buf) = (0, $self->size);
		my $len = read($fd, $buf, $bsz) or die "read: $!";
		if ($len != $bsz) {
			die sprintf("len != bsz (len == %d, bsz == %d)", $len, $bsz);
		}

		my $size = unpack('L', substr($buf, $off, $bsz)); $off += $bsz;
		return $self->read($fd,
			%opts,
			size_force => $size,
			data_tab => $data_tab,
			parsed => $parsed,
			parent => $parent,
		);
	} elsif (defined $size_force) {
		$self->{'size'} = $size_force;
	}

	print STDERR Dumper __PACKAGE__, $self if ($verbose > 2);

	# data
	($off, $bsz, $buf) = (0, $self->size);
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

	if ((my $parse = $data_parse) && defined $self->data && defined $parsed) {
		if (ref $data_parse) {
			my %match = (ref $data_parse eq 'ARRAY')
				? map +($_ => 1), @$data_parse
				: %$data_parse;
			$parse = $match{$self->signature};
		}
		$parsed->deserialize($self, data_tab => $data_tab, %opts) if ($parse);
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
	my $data_parse = $opts{'field_parse'} // $opts{'data_parse'};
	my $size_force = delete $opts{'size_force'};
	my $data_tab = delete $opts{'data_tab'};
	my $parsed = delete $opts{'parsed'};

	if (defined $self->data && defined $parsed && $parsed->dirty) {
		$parsed->serialize($self, data_tab => $data_tab, %opts);
	}

	# header

	# XXXX fields
	my $size = $size_force // $self->size;
	if ($size > 65535) {
		print $fd pack('a4 S L', 'XXXX', 4, $size) or die "print: $!";
		return $self->write($fd,
			%opts,
			size_force => 0,
			data_tab => $data_tab,
			parsed => $parsed,
		);
	}

	print $fd pack("a4 S", $self->signature, $size) or die "print: $!";

	# data

	if ($data_skip) {
		# XXX: Support STDIN
		seek($fd, $self->size, SEEK_CUR) or die "seek: $!";
	} elsif ($data_parse && ref $data_parse) {
		fatal "Attempt to write out partially parsed field";
	} elsif (defined $self->data) {
		print $fd $self->data or die "print: $!";
	} elsif ($self->size) {
		fatal "Field has no data";
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
		data
	) }
);

1;

__END__
