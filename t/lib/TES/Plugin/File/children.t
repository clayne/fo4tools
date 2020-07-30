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

my $child_tab = {
	parent0 => [
	  "parent1.esm",
	  "parent3.esp",
	  "parent4.esm",
	  "plugin with spaces.esp",
	  "plugin.esp",
	  "parent2.esp"
	],
	parent1 => [
	  "parent2.esp",
	  "parent3.esp",
	  "parent4.esm",
	  "plugin with spaces.esp",
	  "plugin.esp"
	],
	parent2 => [
	  "parent3.esp",
	  "parent4.esm",
	  "plugin with spaces.esp",
	  "plugin.esp"
	],
	parent3 => [],
	parent4 => [],
	xxxx => [],
	empty => [],
	compressed => [],
	cell_compressed_xxxx => [],
	plugin => [],
	'plugin with spaces' => [
	  "plugin.esp",
	],
	'master with spaces' => [
	  "plugin with spaces.esp",
	  "plugin.esp",
	],
};

foreach my $plugin (@plugins) {
	my $filename = File::Spec->join($plugin_dir, $plugin);
	my ($plugin_base, $plugin_ext) = ($plugin =~ /^(.+)\.(es[pml])$/) or die;

# children
{
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 1,
		data_parse => 0,
		record_parse => 0,
		field_parse => 0,
	);
	my $children = [ $ret->children ];
	my $expected = $child_tab->{$plugin_base};

	eq_or_diff($children, $expected, $plugin) or print STDERR explain $children, "\n";
}

}

done_testing();
