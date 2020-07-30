package TES::Plugin::Archive::BA2::Ent::DX10::Chunk;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Scalar::Util qw(blessed);
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
	# Q L L S S L
	return 8 + 4 + 4 + 2 + 2 + 4;
}

sub read {
	my ($self, $fd, %opts) = @_;

	# If called with CLASS->read, create a new object.
	$self = $self->new(%opts) if (!blessed($self));

	my ($off, $bsz, $buf) = (0, $self->header_size);
	my $len = read($fd, $buf, $bsz) or die "read: $!";

	@$self{ qw(
		offset
		size_packed
		size
		mip_start
		mip_end
		check
	) } = unpack("Q L L S S L", $buf);

	if ($self->check != 0xbaadf00d) {
		printf STDERR ("chunk fails check, check == 0x%x, pos == %d\n", $self->check, tell($fd));
	}

	return $self;
}

sub write {
	my ($self, $fd, %opts) = @_;

	print $fd pack("Q L L S S L", map $self->{$_}, qw(
		offset
		size_packed
		size
		mip_start
		mip_end
		check
	)) or die "print: $!";
}

sub new {
	my ($class, %opts) = @_;
	map delete $opts{$_}, qw(data_skip verbose);

	my $self = bless { %opts }, ref $class || $class;

	return $self;
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
		offset
		size_packed
		size
		mip_start
		mip_end
		check
	) }
);

1;

__END__
