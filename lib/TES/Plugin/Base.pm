package TES::Plugin::Base;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Scalar::Util qw(weaken);
use Carp qw(confess);
use Data::Dumper;

use strict;
use warnings FATAL => qw(all);

local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Useqq = 1;

local $SIG{__DIE__} = \&confess;
sub fatal { local $SIG{__DIE__}; die @_, "\n" }

our $VERSION = '$Id$';

sub dirty {
	my ($self, $state, %opts) = @_;
	if (defined $state) {
		$self->parent->dirty($state, %opts) if ($self->parent);
		$self->{'__modified'} = $state;
	}
	return $self->{'__modified'};
}

sub parent {
	my ($self, $parent, %opts) = @_;
	if (defined $parent) {
		weaken($self->{'__parent'} = $parent);
	}
	return $self->{'__parent'};
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
	) }
);

1;

__END__
