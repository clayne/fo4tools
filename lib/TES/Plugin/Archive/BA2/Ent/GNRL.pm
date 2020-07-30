package TES::Plugin::Archive::BA2::Ent::GNRL;
use parent 'TES::Plugin::Archive::BA2::Ent';

use FindBin;
use lib "$FindBin::Bin/../lib";

use Scalar::Util qw(blessed);
use File::Basename qw(basename dirname);
use Data::Dumper;
use Carp qw(confess);

use strict;
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;
sub fatal { local $SIG{__DIE__}; die @_, "\n" }

local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Useqq = 1;

our $VERSION = '$Id$';

sub header_size {
	# L Z4 L L Q L L L
	return 4 + 4 + 4 + 4 + 8 + 4 + 4 + 4;
}

sub read {
	my ($self, $fd, %opts) = @_;

	# If called with CLASS->read, create a new object.
	$self = $self->new(%opts) if (!blessed($self));

	my ($off, $bsz, $buf) = (0, $self->header_size);
	my $len = read($fd, $buf, $bsz) or die "read: $!";

	@$self{ qw(
		name_hash
		extension
		dir_hash
		flags
		offset
		size_packed
		size
		check
	) } = unpack("L Z4 L L Q L L L", $buf);

	if ($self->check != 0xbaadf00d) {
		printf STDERR ("ent fails check, check == 0x%x, pos == %d\n", $self->check, tell($fd));
	}

	return $self;
}

sub write {
	my ($self, $fd, %opts) = @_;

	print $fd pack("L a4 L L Q L L L", map $self->{$_}, qw(
		name_hash
		extension
		dir_hash
		flags
		offset
		size_packed
		size
		check
	)) or die "print: $!";
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
		flags
		offset
		size_packed
		size
		check
	) }
);

1;

__END__
