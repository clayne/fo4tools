package TES::Plugin::Archive::BA2::Ent::DX10;
use parent 'TES::Plugin::Archive::BA2::Ent';

use FindBin;
use lib "$FindBin::Bin/../lib";

use TES::Plugin::Archive::BA2::Ent::DX10::Chunk;
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

sub chunk_proc {
	my ($self, $cb, %opts) = @_;

	for (my $i = 0; $i < $self->{'chunk_count'}; $i++) {
		my $chunk = $self->{'chunks'}[$i] || fatal "chunk_ent[$i] not found!";
		$cb->($chunk, %opts) || last;
	}
}

sub chunk_push {
	my $self = shift;
	push @{$self->{'chunks'}}, @_;
}

sub chunk_class {
	return 'TES::Plugin::Archive::BA2::Ent::DX10::Chunk';
}

sub header_size {
	# L Z4 L C C S S S C C S
	return 4 + 4 + 4 + 1 + 1 + 2 + 2 + 2 + 1 + 1 + 2;
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
		chunk_count
		chunk_header_size
		height
		width
		mip_count
		dxgi_format
		cubemaps
	) } = unpack("L Z4 L C C S S S C C S", $buf);

	my ($size, $size_packed) = (0, 0);
	for (my $i = 0; $i < $self->chunk_count; $i++) {
		my $chunk = $self->chunk_class->read($fd);

		$size += $chunk->size;
		$size_packed += $chunk->size_packed;

		$self->chunk_push($chunk);
	}

	$self->{'size'} = $size;
	$self->{'size_packed'} = $size_packed;

	return $self;
}

sub write {
	my ($self, $fd, %opts) = @_;

	print $fd pack("L a4 L C C S S S C C S", map $self->{$_}, qw(
		name_hash
		extension
		dir_hash
		flags
		chunk_count
		chunk_header_size
		height
		width
		mip_count
		dxgi_format
		cubemaps
	)) or die "print: $!";

	for (my $i = 0; $i < $self->{'chunk_count'}; $i++) {
		my $chunk = $self->{'chunks'}[$i] || fatal "chunk_ent[$i] not found!";
		$chunk->write($fd);
	}
}

sub new {
	my $self = (shift)->SUPER::new(@_) || return;
	$self->{'chunks'} ||= [];

	return $self;
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
		size
		size_packed
		flags
		chunk_count
		chunk_header_size
		height
		width
		mip_count
		dxgi_format
		cubemaps
	) }
);

1;

__END__
