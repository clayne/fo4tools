package TES::Plugin::Data::Record::GRUP;
use parent 'TES::Plugin::Data::Record';

use FindBin;
use lib "$FindBin::Bin/../lib";

use Scalar::Util qw(blessed);
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

sub proc {
	my ($self, $cb, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	if ((my $records = $self->records)) {
		foreach my $record (@$records) {
			$record->proc($cb, %opts);
		}
	}

	return 1;
}

sub deserialize {
	my ($self, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	return unless ($self->data);

	print STDERR Dumper __PACKAGE__,[$self->signature,length($self->data // ''),substr($self->data // '', 0, 256)]
		if ($verbose > 1);

	my $data = $self->is_compressed ? $self->decompress : $self->data;
	open(my $data_fd, '<', \$data) or die "open: $!";
	while (!eof($data_fd)) {
		my $ref = TES::Plugin::Data::Record->read($data_fd, %opts, parent => $self);
		push @{$self->{'records'}}, $ref;
	}
	close($data_fd) or die "close: $!";

	return 1;
}

sub serialize {
	my ($self, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	return unless ($self->dirty);

	die("Assertion failed: records and fields") if ($self->records && $self->fields);

	open(my $data_fd, '>', \$self->data) or die "open: $!";
	if ((my $records = $self->records)) {
		foreach my $record (@$records) {
			$record->write($data_fd, %opts);
		}
	}
	close($data_fd) or die "close: $!";

	my $data = $self->is_compressed ? $self->compress : $self->data;
	$self->{'size'} = length($data) + $self->header_size;
	$self->{'data'} = $data;

	$self->dirty(0);
}

# GRUP size contains the size of the header as well
sub size {
	my ($self) = @_;
	return $self->{'size'} - $self->header_size;
}

sub header_size {
	# a4 L a4 L C C C C L
	return 4 + 4 + 4 + 4 + 1 + 1 + 1 + 1 + 4;
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
		label
		type
		vc_day
		vc_mon
		vc_user_last
		vc_user_cur
		unknown
	) } = unpack("a4 L a4 L C C C C L", substr($buf, $off, $bsz)); $off += $bsz;

	print STDERR Dumper __PACKAGE__,$self if ($verbose > 2);

}

sub header_write {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	print $fd pack("a4 L a4 L C C C C L", map $self->{$_}, qw(
		signature
		size
		label
		type
		vc_day
		vc_mon
		vc_user_last
		vc_user_cur
		unknown
	)) or die "print: $!";
}

sub new {
	return (shift)->SUPER::new(@_, group => 1);
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
		label
		type
	) }
);

1;

__END__
