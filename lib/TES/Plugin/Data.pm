package TES::Plugin::Data;
use parent 'TES::Plugin::Base';

use FindBin;
use lib "$FindBin::Bin/../lib";

use TES::Plugin::Data::Record qw();

use Scalar::Util qw(blessed weaken);
use File::Basename qw(basename dirname);
use File::stat qw(stat);
use Fcntl qw(SEEK_SET SEEK_CUR);
use Carp qw(confess);
use Data::Dumper;

use strict;
use warnings FATAL => qw(all);

local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Useqq = 1;

local $SIG{__DIE__} = \&confess;
sub fatal { local $SIG{__DIE__}; die @_, "\n" }

our $VERSION = '$Id$';

sub proc {
	my ($self, $cb, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	my $include = $opts{'include'};
	my $exclude = $opts{'exclude'};
	return unless ($self->size && $self->records);

	foreach my $record (@{$self->records}) {
		$record->proc($cb, %opts) || last;
	}
}

sub header_size {
	my ($self, %opts) = @_;
	return $self->header->total_size;
}

sub deserialize {
	my ($self, %opts) = @_;

	$self->{'records'} = [];

	open(my $data_fd, '<', \$self->data) or die "open: $!";
	while (!eof($data_fd)) {
		my $ref = TES::Plugin::Data::Record->read($data_fd, %opts, parent => $self);
		push @{$self->{'records'}}, $ref;
	}
	close($data_fd) or die "close: $!";
}

sub serialize {
	my ($self, %opts) = @_;
	return unless ($self->dirty);

	open(my $data_fd, '>', \$self->data) or die "open: $!";
	if ((my $records = $self->records)) {
		foreach my $record (@$records) {
			$record->write($data_fd, %opts);
		}
	}
	close($data_fd) or die "close: $!";

	$self->{'size'} = length($self->data);

	$self->header->serialize(%opts);

	$self->dirty(0);
}

sub rewrite {
	my ($self, %opts) = @_;
	my $header_rewrite = delete $opts{'header_rewrite'};
	my $data_rewrite = delete $opts{'data_rewrite'};
	my $ret = 0;

	$ret |= $self->header->rewrite(%opts, %$header_rewrite);

	$self->proc(sub {
		my ($self, %opts) = @_;
		if ($self->can('rewrite')) {
			$ret |= $self->rewrite(%opts) || 0;
		}
		return 1;
	}, %opts, %$data_rewrite);

	return $ret;
}

sub read {
	my ($self, $fd, %opts) = @_;
	my $header_data_skip = delete $opts{'header_data_skip'};
	my $data_parse = $opts{'data_parse'};
	my $data_skip = $opts{'data_skip'};
	my $parent = delete $opts{'parent'};

	# If called with CLASS->read, create a new object.
	$self = $self->new(%opts, parent => $parent) if (!blessed($self));

	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	# header

	$self->{'header'} = TES::Plugin::Data::Record->read($fd, %opts,
		data_skip => 0,
		record_parse => 1,
		field_parse => 1,
		parent => $self,
	);

	print STDERR Dumper { header_data => substr($self->header->data // '', 0, 512) }
		if ($verbose > 1);

	fatal("Not a TES4 plugin") unless ($self->header->signature eq 'TES4');

	# data

	$self->{'size'} = stat($fd)->size - $self->header_size;

	my ($off, $bsz, $buf) = (0, $self->size, '');
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

	if ($data_parse && defined $self->data) {
		$self->deserialize(%opts);
	}

	return $self;
}

sub write {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	my $header_data_skip = delete $opts{'header_data_skip'};
	my $data_skip = $opts{'data_skip'};

	if ($self->dirty && defined $self->records) {
		$self->serialize(%opts);
	}

	# header

	print STDERR Dumper { header_data => substr($self->header->data // '', 0, 512) }
		if ($verbose > 1);

	$self->header->write($fd, %opts,
		data_skip => 0,
		record_parse => 1,
		field_parse => 1,
	);

	# data

	if ($data_skip) {
		# XXX: Support STDIN
		seek($fd, $self->size, SEEK_CUR) or die "seek: $!";
	} elsif (defined $self->data) {
		print $fd $self->data or die "print: $!";
	} elsif ($self->size) {
		fatal "Plugin has no data";
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
		header
		size
		data
		records
	) }
);

1;

__END__
