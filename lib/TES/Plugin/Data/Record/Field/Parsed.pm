package TES::Plugin::Data::Record::Field::Parsed;
use parent 'TES::Plugin::Data::Record::Field';

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

sub deserialize {
	my ($self, $field, %opts) = @_;
	my $verbose = $opts{'verbose'} // $field->{'verbose'} // 0;
	my $data_tab = $opts{'data_tab'};
	return unless ($field->data);

	my $sig = $field->signature;
	my $ref = $data_tab->{$sig};
	if (!$ref) {
		printf STDERR ("%s: Unknown signature: '%s'\n", __PACKAGE__, $sig)
			if ($verbose);
		return;
	} elsif (ref $ref eq 'HASH') {
		$ref = $ref->{'read'};
	}

	my $data = $field->data;
	if (ref $ref eq 'ARRAY') {
		my ($keys, $tmpl, %opts) = @$ref;
		my @keys = ref $keys ? @$keys : $keys;
		my @data = unpack($tmpl, $data);
		@$self{@keys} = $opts{'array'} ? \@data : @data;
	} elsif (ref $ref eq 'CODE') {
		$ref->($self, $data, $self->idx_map->{$sig}++);
	}
}

sub serialize {
	my ($self, $field, %opts) = @_;
	my $verbose = $opts{'verbose'} // $field->{'verbose'} // 0;
	my $data_tab = $opts{'data_tab'};
	return unless ($self->dirty);

	# XXX: this should probably be driven by keys from $self
	my $sig = $field->signature;
	my $ref = $data_tab->{$sig};
	if (!$ref) {
		printf STDERR ("%s: Unknown signature: '%s'\n", __PACKAGE__, $sig)
			if ($verbose);
		return;
	} elsif (ref $ref eq 'HASH') {
		$ref = $ref->{'write'};
	}

	if (ref $ref eq 'ARRAY') {
		my ($keys, $tmpl, %opts) = @$ref;
		my @keys = ref $keys ? @$keys : $keys;
		$field->{'data'} = pack($tmpl, $opts{'array'} ? @{@$self{@keys}} : @$self{@keys});
	} elsif (ref $ref eq 'CODE') {
		$ref->($field->data, $self, $self->idx_map->{$sig}++);
	}

	$field->{'size'} = length($field->data);
	$field->dirty(0);
}

sub new {
	my ($class, %opts) = @_;
	my $parent = delete $opts{'parent'};
	map delete $opts{$_}, qw(data_skip data_parse record_parse field_parse verbose);

	my $self = bless { %opts }, ref $class || $class;

	if (defined $parent) {
		$self->parent($parent);
	}

	$self->idx_map({});

	return $self;
}

use Class::XSAccessor (
	accessors => {
		idx_map => '__idx_map',
	}
);

1;

__END__
