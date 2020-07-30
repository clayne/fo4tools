package TES::Plugin::Archive::BA2;

use FindBin;
use lib "$FindBin::Bin/../lib";

use TES::Plugin::Common qw(file_sub file_join);
use TES::Plugin::Archive::BA2::Ent::GNRL qw();
use TES::Plugin::Archive::BA2::Ent::DX10 qw();
use Scalar::Util qw(blessed);
use File::Basename qw(basename dirname);
use File::stat qw(stat);
use Fcntl qw(SEEK_SET);
use Data::Dumper;
use Carp qw(confess);

use strict;
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;
sub fatal { local $SIG{__DIE__}; die @_, "\n" }

local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Useqq = 1;

our $VERSION = '$Id$';

my $ent_class_tab = {
	GNRL => 'TES::Plugin::Archive::BA2::Ent::GNRL',
	DX10 => 'TES::Plugin::Archive::BA2::Ent::DX10',
};

sub ent_proc {
	my ($self, $cb, %opts) = @_;
	my $sort = delete $opts{'sort'};

	my @out = ();
	for (my $i = 0; $i < $self->{'file_count'}; $i++) {
		my $ent = $self->{'ents'}[$i] || fatal "file_ent[$i] not found!";
		push @out, $ent;
	}

	if (defined $sort) {
		if ($sort eq 'size') {
			@out = sort { $a->size <=> $b->size } @out;
		} else {
			@out = sort { $a->name cmp $b->name } @out;
		}
	}

	foreach (@out) { $cb->($_, %opts) || last }
}

sub ent_push {
	my $self = shift;
	push @{$self->{'ents'}}, @_;
}

sub ent_class {
	my $self = shift;
	my $type = $self->{'type'} || die;
	return $ent_class_tab->{$type} || die;
}

sub rewrite {
	my ($self, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	my $match_string = $opts{'match_string'};
	my $match_file = $opts{'match_file'};
	my $match_dir = $opts{'match_dir'};
	my $sub_string = $opts{'sub_string'};
	my $sub_file = $opts{'sub_file'};
	my $sub_dir = $opts{'sub_dir'};
	my $sub_string_ext = $opts{'sub_string_ext'};
	my $sub_file_ext = $opts{'sub_file_ext'};
	my $sub_dir_ext = $opts{'sub_dir_ext'};
	my $sub_ext = $opts{'sub_ext'};
	my $sub = $opts{'sub'};
	my $rewrite = 0;

	for (my $i = 0; $i < $self->{'file_count'}; $i++) {
		my $ent = $self->{'ents'}[$i] || fatal "file_ent[$i] not found!";
		my ($dirname, $basename, $extension) = $ent->name_split;
		my $filename = join('.', $basename, $extension ? $extension : ());

		if (defined $match_string && index($dirname, 'Strings', 0) == 0 && $filename =~ $match_string) {
			my $filename_new = file_sub($filename,
				match => $match_string,
				sub => $sub_string // $sub,
				sub_ext => $sub_string_ext // $sub_ext,
				verbose => $verbose,
			);
			if ($filename_new ne $filename) {
				$filename = $filename_new;
				$ent->name(file_join($dirname, $filename));
				$rewrite++;
			}
		} elsif (defined $match_file && !index($dirname, 'Strings', 0) == 0 && $filename =~ $match_file) {
			my $filename_new = file_sub($filename,
				match => $match_file,
				sub => $sub_file // $sub,
				sub_ext => $sub_file_ext // $sub_ext,
				verbose => $verbose,
			);
			if ($filename_new ne $filename) {
				$filename = $filename_new;
				$ent->name(file_join($dirname, $filename));
				$rewrite++;
			}
		}

		if (defined $match_dir && $dirname =~ $match_dir) {
			my $dirname_new = file_sub($dirname,
				match => $match_dir,
				sub => $sub_dir // $sub,
				sub_ext => $sub_dir_ext // $sub_ext,
				verbose => $verbose,
			);
			if ($dirname_new ne $dirname) {
				$dirname = $dirname_new;
				$ent->name(file_join($dirname, $filename));
				$rewrite++;
			}
		}
	}

	return $rewrite;
}

# https://github.com/AlexxEG/BSA_Browser/wiki/BA2-Specs#name-table
#
# Structure
# Name			Type		Info
# Header		Header		See Header below
# [type] File Records	File Record	See File Record below
# Raw Data		Blob		Raw file data
# Name Table		Name Table	See Name Table below
#
# Header
# Name			Type		Info
# magic			char[4]		BTDX
# version		uint32		Currently: 1
# type			char[4]		Values: GNRL, DX10, GNMF
# numFiles		uint32		Number of files
# nameTableOffset	uint64		Offset to name table
#
# GNRL File Record
# Name			Type		Info
# nameHash		uint32		crc32 hash. Unsure how this is used
# extension		char[4]		File extension, for example: nif or dds
# dirHash		uint32		crc32 hash. Unsure how this is used
# flags			uint32		Unknown
# offset		uint64		Offset to raw data
# size			uint32		File size. If 0 the file is uncompressed
# realSize		uint32		File size (uncompressed)
# align			uint32		Seems to be 0DF0ADBA
#
# DX10 File Record
# Name			Type		Info
# nameHash		uint32		crc32 hash. Unsure how this is used
# extension		char[4]		File extension, for example: nif or dds
# dirHash		uint32		crc32 hash. Unsure how this is used
# flags			uint8		Unknown
# chunkCount		uint8		Number of texture chunks
# chunkHeaderSize	uint16		Seems to always be 24
# height		uint16		Height
# width			uint16		Width
# mipCount		uint8		mipmap count
# dxgiFormat		uint8		DXGI format
# cubeMaps		uint16
# (
#   offset		uint64		Offset to raw data
#   size		uint32		File size. If 0 the file is uncompressed
#   realSize		uint32		File size (uncompressed)
#   mipStart		uint16
#   mipEnd		uint16
#   align		uint32		Seems to be 0DF0ADBA
# ) x chunkCount
#
# Raw Data
#
# Name Table
# Name			Type		Info
# length		uint16		Length of filename
# filename		char[length]	Filename
# [...]

sub header_size {
	# a4 L a4 L Q
	return 4 + 4 + 4 + 4 + 8;
}

sub header_read {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	my ($off, $bsz, $buf) = (0, $self->header_size);
	my $len = read($fd, $buf, $bsz) or die "read: $!";
	print STDERR Dumper length($buf) if ($verbose > 1);

	my $signature = unpack("a4", substr($buf, $off, 4));
	return unless ($signature eq 'BTDX');

	@$self{ qw(
		signature
		version
		type
		file_count
		name_table_offset
	) } = unpack("a4 L a4 L Q", substr($buf, $off, $bsz)); $off += $bsz;

	print STDERR Dumper $self if ($verbose > 1);

	return 1;
}

sub ents_read {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	for (my $i = 0; $i < $self->{'file_count'}; $i++) {
		my $ent = $self->ent_class->read($fd);
		$self->ent_push($ent);
	}

	return 1;
}

sub data_read {
	my ($self, $fd, %opts) = @_;
	my $data_skip = $opts{'data_skip'};
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	# XXX: Support STDIN
	$self->{'data_offset'} = tell($fd) or die "tell: $!";
	$self->{'data_size'} = $self->{'name_table_offset'} - $self->{'data_offset'};

	if ($data_skip) {
		# XXX: Support STDIN
		seek($fd, $self->{'name_table_offset'}, SEEK_SET) or die "seek: $!";
	} else {
		my ($off, $bsz, $buf) = (0, $self->{'name_table_offset'} - $self->{'data_offset'});
		if (!$bsz) {
			return 1;
		}

		my $len = read($fd, $buf, $bsz) or die "read: $!";
		$self->{'data'} = $buf;
	}

	return 1;
}

sub name_table_read {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	# XXX: Support STDIN
	$self->{'name_table_size'} = $self->{'file_size'} - $self->{'name_table_offset'};

	my ($off, $bsz, $buf) = (0, $self->{'name_table_size'});
	if (!$bsz) {
		return 1;
	}

	my $len = read($fd, $buf, $bsz) or die "read: $!";
	if ($len < $bsz) {
		fatal sprintf("file is shorter than expected (len == %d, bsz == %d)", $len, $bsz);
	} elsif ((my $offset = $self->{'name_table_offset'} + $len) != $self->{'file_size'}) {
		printf STDERR ("file has %d bytes of trailing data\n", $self->{'file_size'} - $offset);
	}

	for (my $i = 0; $i < $self->{'file_count'}; $i++) {
		my $ent = $self->{'ents'}[$i] || fatal "file_ent[$i] not found!";
		my $name = unpack("S/a", substr($buf, $off, 65536)); $off += 2 + length($name);
		$ent->{'name'} = ($name =~ tr%\\%/%r);

		my ($dirname, $basename) = $ent->name_split;
		my $dir_hash = $ent->crc($dirname);
		my $name_hash = $ent->crc($basename);

		if ($ent->{'dir_hash'} != $dir_hash) {
			binmode(STDERR, ":utf8");
			printf STDERR ("file[%d]: dir_hash mismatch: 0x%08x != 0x%08x, '%s'\n",
				$i, $ent->{'dir_hash'}, $dir_hash, $ent->{'name'});
		}

		if ($ent->{'name_hash'} != $name_hash) {
			binmode(STDERR, ":utf8");
			printf STDERR ("file[%d]: name_hash mismatch: 0x%08x != 0x%08x, '%s'\n",
				$i, $ent->{'name_hash'}, $name_hash, $ent->{'name'});
		}
	}

	return 1;
}

sub header_write {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	print $fd pack("a4 L a4 L Q", map $self->{$_}, qw(
		signature
		version
		type
		file_count
		name_table_offset
	)) or die "print: $!";

	return 1;
}

sub ents_write {
	my ($self, $fd, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;

	for (my $i = 0; $i < $self->{'file_count'}; $i++) {
		my $ent = $self->{'ents'}[$i] || fatal "file_ent[$i] not found!";
		$ent->write($fd);
	}

	return 1;
}

sub data_write {
	my ($self, $fd, %opts) = @_;
	my $data_skip = $opts{'data_skip'};

	# XXX: Support STDIN
	my $pos = tell($fd) or die "tell: $!";
	if ($pos != $self->{'data_offset'}) {
		die sprintf("Assertion failed: pos != data_offset (pos == %d, data_offset == %d)\n",
			$pos, $self->{'data_offset'});
	}

	if ($data_skip) {
		# XXX: Support STDIN
		seek($fd, $self->{'name_table_offset'}, SEEK_SET) or die "seek: $!";
	} elsif (defined $self->{'data'}) {
		print $fd $self->{'data'} or die "print: $!";

		# XXX: Support STDIN
		$pos = tell($fd) or die "tell: $!";
		if ($pos != $self->{'name_table_offset'}) {
			die sprintf("Assertion failed: pos != name_table_offset (pos == %d, name_table_offset == %d)\n",
				$pos, $self->{'name_table_offset'});
		}
	} elsif ($self->{'name_table_offset'}) {
		fatal "Archive has no data"
	}

	return 1;
}

sub name_table_write {
	my ($self, $fd, %opts) = @_;

	for (my $i = 0; $i < $self->{'file_count'}; $i++) {
		my $ent = $self->{'ents'}[$i] || fatal "file_ent[$i] not found!";
		print $fd pack("S/a", $ent->{'name'}) or die "print: $!";
	}

	# XXX: Support STDIN
	my $pos = tell($fd) or die "tell: $!";
	if ($pos != $self->{'file_size'}) {
		die sprintf("Assertion failed: pos != file_size (pos == %d, file_size == %d)\n",
			$pos, $self->{'file_size'});
	}

	return 1;
}

sub read {
	my ($self, $path, %opts) = @_;

	# If called with CLASS->read, create a new object.
	$self = $self->new(%opts) if (!blessed($self));

	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	my $close = $opts{'close'} // 1;

	my ($fd, $stdin);
	if ($path eq '/dev/stdin' || $path eq '-') {
		$fd = *STDIN;
		$stdin = 1;
		$close = 0;
	} else {
		if (ref $path eq 'GLOB') {
			$fd = $path;
			$close = 0;

			seek($fd, 0, SEEK_SET) or die "seek: $!";
		} else {
			open($fd, '<', $path) or die "open: $!: $path";
			binmode($fd);
		}

		$self->{'file_size'} = stat($fd)->size or die "stat: $!";
	}

	$self->header_read($fd, %opts) or fatal "$path: Not a ba2 archive";
	$self->ents_read($fd, %opts);
	$self->data_read($fd, %opts);
	$self->name_table_read($fd, %opts);

	if ($close) {
		close($fd) or die "close: $!";
	}

	return $self;
}

sub write {
	my ($self, $path, %opts) = @_;
	my $verbose = $opts{'verbose'} // 0;
	my $close = $opts{'close'} // 1;
	my $data_skip = $opts{'data_skip'};
	my ($fd, $stdin);

	if ($path eq '/dev/stdin' || $path eq '-') {
		$fd = *STDIN;
		$stdin = 1;
		$close = 0;
	} elsif (ref $path eq 'GLOB') {
		$fd = $path;
		$close = 0;

		seek($fd, 0, SEEK_SET) or die "seek: $!";
	} else {
		open($fd, $data_skip ? '+<' : '>', $path) or die "open: $!: $path";
		binmode($fd);
	}

	$self->header_write($fd, %opts);
	$self->ents_write($fd, %opts);
	$self->data_write($fd, %opts);
	$self->name_table_write($fd, %opts);

	if ($close) {
		close($fd) or die "close: $!";
	}

	return 1;
}

sub new {
	my ($class, %opts) = @_;
	map delete $opts{$_}, qw(data_skip verbose);

	my $self = bless { ents => [], %opts }, ref $class || $class;

	return $self;
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
		signature
		version
		type
		file_count
		file_size
		data_offset
		data_size
		name_table_offset
		name_table_size
	) }
);

1;

__END__
