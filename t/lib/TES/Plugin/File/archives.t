#!/usr/bin/perl

use Scalar::Util qw(weaken);
use File::Basename qw(basename dirname);
use File::Spec qw(join);
use File::Temp qw(tempfile tempdir);
use Test::Differences;
use Test::More;
use Test::Deep;
use Data::Dumper;
use Digest::MD5 qw();
use Carp qw(cluck confess);
use Sereal::Encoder qw(SRL_ZLIB);
use Sereal::Decoder qw();

use strict;
use autodie qw(:all);
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;

local $Data::Dumper::Deepcopy = 1;
local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Purity = 1;
local $Data::Dumper::Useqq = 1;

use TES::Plugin::File qw();

# test all plugins in data directory
my $plugin_dir = 't/data';
my $test_file = basename($0);

opendir(my $dh, $plugin_dir) || die "opendir: $!";
my @plugins = grep /\.es[pml]$/, readdir($dh);
closedir $dh or die "closedir: $!";

my $archive_tab = {
	parent0 => [
	  "parent0 - Main.ba2",
	  "parent0 - Textures.ba2"
	],
	parent1 => [],
	parent2 => [],
	parent3 => [],
	parent4 => [],
	xxxx => [],
	empty => [],
	compressed => [],
	cell_compressed_xxxx => [],
	plugin => [
	  "plugin - Main.ba2",
	],
	'plugin with spaces' => [
	  "plugin with spaces - Main.ba2",
	],
	'master with spaces' => [
	  "master with spaces - Main.ba2",
	],
};

foreach my $plugin (@plugins) {
	my $filename = File::Spec->join($plugin_dir, $plugin);
	my ($plugin_base, $plugin_ext) = ($plugin =~ /^(.+)\.(es[pml])$/) or die;

# archives
{
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 1,
		data_parse => 0,
		record_parse => 0,
		field_parse => 0,
	);
	my $archives = [ $ret->archives ];
	my $expected = $archive_tab->{$plugin_base};

	eq_or_diff($archives, $expected, $plugin) or print STDERR explain $archives, "\n";
}

}

done_testing();
