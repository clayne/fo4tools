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

my $parent_tab = {
	parent0 => [
	  "Fallout4.esm",
	  "DLCworkshop01.esm"
	],
	parent1 => [
	  "Fallout4.esm",
	  "DLCCoast.esm",
	  "DLCNukaWorld.esm",
	  "DLCworkshop01.esm",
	  "parent0.esp"
	],
	parent2 => [
	  "Fallout4.esm",
	  "DLCworkshop02.esm",
	  "DLCworkshop03.esm",
	  "DLCworkshop01.esm",
	  "parent0.esp",
	  "DLCNukaWorld.esm",
	  "DLCCoast.esm",
	  "parent1.esm"
	],
	parent3 => [
	  "Fallout4.esm",
	  "DLCworkshop01.esm",
	  "parent0.esp",
	  "DLCNukaWorld.esm",
	  "DLCCoast.esm",
	  "parent1.esm",
	  "DLCworkshop03.esm",
	  "DLCworkshop02.esm",
	  "parent2.esp"
	],
	parent4 => [
	  "Fallout4.esm",
	  "DLCworkshop01.esm",
	  "parent0.esp",
	  "DLCNukaWorld.esm",
	  "DLCCoast.esm",
	  "parent1.esm",
	  "DLCworkshop03.esm",
	  "DLCworkshop02.esm",
	  "parent2.esp"
	],
	xxxx => [
	  "Fallout4.esm"
	],
	empty => [
	  "Fallout4.esm"
	],
	compressed => [
	  "Fallout4.esm"
	],
	cell_compressed_xxxx => [
	  "Fallout4.esm"
	],
	plugin => [
	  "Fallout4.esm",
	  "DLCworkshop01.esm",
	  "parent0.esp",
	  "DLCNukaWorld.esm",
	  "DLCCoast.esm",
	  "parent1.esm",
	  "DLCworkshop03.esm",
	  "DLCworkshop02.esm",
	  "parent2.esp",
	  "master with spaces.esm",
	  "plugin with spaces.esp",
	],
	'plugin with spaces' => [
	  "Fallout4.esm",
	  "DLCworkshop01.esm",
	  "parent0.esp",
	  "DLCNukaWorld.esm",
	  "DLCCoast.esm",
	  "parent1.esm",
	  "DLCworkshop03.esm",
	  "DLCworkshop02.esm",
	  "parent2.esp",
	  "master with spaces.esm",
	],
	'master with spaces' => [
	  "Fallout4.esm"
	],
};

foreach my $plugin (@plugins) {
	my $filename = File::Spec->join($plugin_dir, $plugin);
	my ($plugin_base, $plugin_ext) = ($plugin =~ /^(.+)\.(es[pml])$/) or die;

# parents
{
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 1,
		data_parse => 0,
		record_parse => 0,
		field_parse => 0,
	);
	my $parents = [ $ret->parents ];
	my $expected = $parent_tab->{$plugin_base};

	eq_or_diff($parents, $expected, $plugin) or print STDERR explain $parents, "\n";
}

}

done_testing();
