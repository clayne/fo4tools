package TES::Plugin::File;
use parent 'TES::Plugin::Data';

use FindBin;
use lib "$FindBin::Bin/../lib";

use TES::Plugin::Archive::BA2 qw();
use Scalar::Util qw(blessed);
use File::Basename qw(basename dirname);
use File::stat qw(stat);
use File::Spec qw();
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

our $childen_uncached = 0;
our $parents_uncached = 0;

my $plugin_dir_size;
my $plugin_dir_inode;
my $plugin_dir_mtime;

my $parent_map;
my $child_map;

sub plugin_map_dump {
	return Dumper {
		parent_map => $parent_map,
		child_map => $child_map,
	};
}

sub plugin_map_clear {
	$plugin_dir_size = undef;
	$plugin_dir_mtime = undef;
	$plugin_dir_inode = undef;
}

sub plugin_dir_dirty_check {
	my ($dir, $force) = @_;

	my $size = stat($dir)->size;
	my $mtime = stat($dir)->mtime;
	my $inode = stat($dir)->ino;

	return unless ($force
		|| !defined $plugin_dir_size  ||  $size != $plugin_dir_size
		|| !defined $plugin_dir_inode || $inode != $plugin_dir_inode
		|| !defined $plugin_dir_mtime || $mtime != $plugin_dir_mtime
	);

	$plugin_dir_size = $size;
	$plugin_dir_mtime = $mtime;
	$plugin_dir_inode = $inode;

	return 1;
}

sub plugin_map_generate {
	my ($dir, $force) = @_;
	return unless (plugin_dir_dirty_check($dir, $force));

	$parent_map = {};
	$child_map = {};

	opendir(my $dh, $dir || '.') or die "opendir: $!";
	foreach (grep /\.es[pml]$/, readdir($dh)) {
		my $path = File::Spec->join($dir, $_);
		my $plugin = __PACKAGE__->read($path, data_skip => 1);
		my @parents = $plugin->masters or next;
		foreach my $parent (@parents) {
			push @{$child_map->{$parent}}, $_;
			push @{$parent_map->{$_}}, $parent;
		}
	}
	closedir($dh) or die "closedir: $!";
}

sub parents {
	my ($self, %opts) = @_;
	my $force = $opts{'force'} // $parents_uncached;

	plugin_map_generate($self->plugin_dir, $force);

	my $filename = $self->plugin_file;
	my $parents = $parent_map->{$filename} || [];
	my %parents = map +($_, 1), @$parents;

	my (@stack, @res, %seen)  = $filename;
	while ((my $parent = shift @stack)) {
		next unless (!$seen{$parent}++);
		unshift @res, $parent;

		my $parents = $parent_map->{$parent} || next;
		for (my $i = scalar @$parents; $i--; ) {
			# Account for parents of parents that are not
			# a parent of the plugin itself.
			my $parent = $parents->[$i];
			if ($seen{$parent}) { next }
			elsif ($parents{$parent}) { push @stack, $parent }
			else { unshift @stack, $parent }
		}
	}

	if (!$opts{'include_self'} && $res[-1] eq $filename) {
		pop @res;
	}

	return @res;
}

sub children {
	my ($self, %opts) = @_;
	my $force = $opts{'force'} // $childen_uncached;

	plugin_map_generate($self->plugin_dir, $force);

	my $filename = $self->plugin_file;
	my $children = $child_map->{$filename} || [];

	my (@stack, @res, %seen)  = $filename;
	while ((my $child = shift @stack)) {
		next unless (!$seen{$child}++);
		push @res, $child;

		my $children = $child_map->{$child} || next;
		push @stack, grep !$seen{$_}, @$children;
	}

	if (!$opts{'include_self'} && $res[0] eq $filename) {
		shift @res;
	}

	return @res;
}

sub archives {
	my ($self, %opts) = @_;

	opendir(my $dh, $self->plugin_dir || '.') or die "opendir: $!";
	my @archives = grep {
		(index($_, $self->plugin_base . ' - ', 0) == 0) && /\.ba2$/
	} readdir($dh);
	closedir($dh) or die "closedir: $!";

	return @archives;
}

sub masters {
	my ($self, %opts) = @_;
	die unless (defined $self->header);

	return $self->header->masters ? @{$self->header->masters} : ();
}

sub flags {
	my ($self, %opts) = @_;
	die unless (defined $self->header);

	return $self->header->flags;
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
	} elsif (ref $path eq 'GLOB') {
		$fd = $path;
		$close = 0;
		seek($fd, 0, SEEK_SET) or die "seek: $!";
		$self->{'file_size'} = stat($fd)->size or ($! && die "stat: $!");
	} else {
		open($fd, '<', $path) or die "open: $path: $!";
		binmode($fd);

		my $dirname = dirname($path);
		my $basename = basename($path);
		my ($plugin_base, $plugin_ext) = ($basename =~ /^(.+)\.(es[pml])$/);

		$self->{'plugin_path'} = $path;
		$self->{'plugin_file'} = $basename;
		$self->{'plugin_dir'} = $dirname;
		$self->{'plugin_base'} = $plugin_base;
		$self->{'plugin_ext'} = $plugin_ext;

		$self->{'file_size'} = stat($fd)->size or ($! && die "stat: $!");
	}

	$self->SUPER::read($fd, %opts);

	if ($close) {
		close($fd) or die "close: $!";
	}

	return $self;
}

sub write {
	my ($self, $path, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	my $data_skip = $opts{'data_skip'};
	my $close = $opts{'close'} // 1;

	my ($fd, $stdin);
	if (ref $path eq 'GLOB') {
		$fd = $path;
		$close = 0;
		seek($fd, 0, SEEK_SET) or die "seek: $!";
	} elsif ($path eq '/dev/stdin' || $path eq '-') {
		$fd = *STDIN;
		$stdin = 1;
		$close = 0;
	} else {
		# XXX: data_skip should actually be 'inplace'
		open($fd, $data_skip ? '+<' : '>', $path) or die "open: $path: $!";
		binmode($fd);
	}

	$self->SUPER::write($fd, %opts);

	if ($close) {
		close($fd) or die "close: $!";
	}

	plugin_map_clear;

	return 1;
}

sub new {
	my ($class, %opts) = @_;
	map delete $opts{$_}, qw(data_skip data_parse record_parse field_parse verbose);

	my $self = bless { %opts }, ref $class || $class;

	return $self;
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
		file_size
		plugin_path
		plugin_file
		plugin_base
		plugin_dir
		plugin_ext
	) }
);

use Exporter 'import';
our @EXPORT_OK = qw(plugin_map_generate plugin_map_clear);

1;

__END__
