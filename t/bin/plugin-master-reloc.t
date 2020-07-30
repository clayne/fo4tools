#!/usr/bin/perl

use File::Spec qw(join);
use File::Temp qw(tempfile tempdir);
use File::Copy qw(cp);
use File::chdir;
use Test::Differences;
use Test::More;
use Test::Deep;
use Test::Output;
use Data::Dumper;
use Carp qw(cluck confess);

use strict;
use autodie qw(:all);
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;

local $Data::Dumper::Deepcopy = 1;
local $Data::Dumper::Sortkeys = 1;

use lib '.';
require 'bin/plugin-master-reloc';

my $plugin_dir = 't/data';

sub ls_dir {
	my $src = shift;

	opendir(my $dh, $src) || die "opendir: $!";
	my @plugins = grep /\.es[pml]$/, readdir($dh);
	closedir $dh or die "closedir: $!";

	return [ sort @plugins ];
}

sub temp_dir_prepare {
	my $src = shift;
	my $dst = tempdir(CLEANUP => 1);

	opendir(my $dh, $src) || die "opendir: $!";
	my @plugins = grep /\.es[pml]$/, readdir($dh);
	closedir $dh or die "closedir: $!";

	foreach my $plugin (@plugins) {
		my $filename_src = File::Spec->join($src, $plugin);
		my $filename_dst = File::Spec->join($dst, $plugin);
		cp($filename_src, $filename_dst) or die "cp: $plugin";
	}

	# XXX: special case copy xxxx.esp to vanilla files
	foreach (qw(
		Fallout4.esm
		DLCworkshop01.esm
		DLCworkshop02.esm
		DLCworkshop03.esm
		DLCCoast.esm
		DLCRobot.esm
		DLCNukaWorld.esm
	)) {
		cp(
			File::Spec->join($src, 'xxxx.esp'),
			File::Spec->join($dst, $_)
		);
	}

	return ($dst, @plugins);
}

# dump
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp	Fallout4.esm
------
compressed.esp	Fallout4.esm
------
empty.esp	Fallout4.esm
------
master with spaces.esm	Fallout4.esm
------
parent0.esp	Fallout4.esm
parent0.esp	DLCworkshop01.esm
------
parent1.esm	Fallout4.esm
parent1.esm	DLCCoast.esm
parent1.esm	DLCNukaWorld.esm
parent1.esm	parent0.esp
------
parent2.esp	Fallout4.esm
parent2.esp	DLCworkshop02.esm
parent2.esp	DLCworkshop03.esm
parent2.esp	parent1.esm
------
parent3.esp	Fallout4.esm
parent3.esp	parent0.esp
parent3.esp	parent1.esm
parent3.esp	parent2.esp
------
parent4.esm	Fallout4.esm
parent4.esm	parent0.esp
parent4.esm	parent1.esm
parent4.esm	parent2.esp
------
plugin with spaces.esp	Fallout4.esm
plugin with spaces.esp	parent0.esp
plugin with spaces.esp	parent1.esm
plugin with spaces.esp	parent2.esp
plugin with spaces.esp	master with spaces.esm
------
plugin.esp	Fallout4.esm
plugin.esp	parent0.esp
plugin.esp	parent1.esm
plugin.esp	parent2.esp
plugin.esp	plugin with spaces.esp
------
EOF
	ok($ret);
}

# dump --include-self
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--include-self
				),
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp	Fallout4.esm
cell_compressed_xxxx.esp	cell_compressed_xxxx.esp
------
compressed.esp	Fallout4.esm
compressed.esp	compressed.esp
------
empty.esp	Fallout4.esm
empty.esp	empty.esp
------
master with spaces.esm	Fallout4.esm
master with spaces.esm	master with spaces.esm
------
parent0.esp	Fallout4.esm
parent0.esp	DLCworkshop01.esm
parent0.esp	parent0.esp
------
parent1.esm	Fallout4.esm
parent1.esm	DLCCoast.esm
parent1.esm	DLCNukaWorld.esm
parent1.esm	parent0.esp
parent1.esm	parent1.esm
------
parent2.esp	Fallout4.esm
parent2.esp	DLCworkshop02.esm
parent2.esp	DLCworkshop03.esm
parent2.esp	parent1.esm
parent2.esp	parent2.esp
------
parent3.esp	Fallout4.esm
parent3.esp	parent0.esp
parent3.esp	parent1.esm
parent3.esp	parent2.esp
parent3.esp	parent3.esp
------
parent4.esm	Fallout4.esm
parent4.esm	parent0.esp
parent4.esm	parent1.esm
parent4.esm	parent2.esp
parent4.esm	parent4.esm
------
plugin with spaces.esp	Fallout4.esm
plugin with spaces.esp	parent0.esp
plugin with spaces.esp	parent1.esm
plugin with spaces.esp	parent2.esp
plugin with spaces.esp	master with spaces.esm
plugin with spaces.esp	plugin with spaces.esp
------
plugin.esp	Fallout4.esm
plugin.esp	parent0.esp
plugin.esp	parent1.esm
plugin.esp	parent2.esp
plugin.esp	plugin with spaces.esp
plugin.esp	plugin.esp
------
xxxx.esp	xxxx.esp
EOF
	ok($ret);
}

# dump -q
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				-q
				), $plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
Fallout4.esm
------
Fallout4.esm
------
Fallout4.esm
------
Fallout4.esm
------
Fallout4.esm
DLCworkshop01.esm
------
Fallout4.esm
DLCCoast.esm
DLCNukaWorld.esm
parent0.esp
------
Fallout4.esm
DLCworkshop02.esm
DLCworkshop03.esm
parent1.esm
------
Fallout4.esm
parent0.esp
parent1.esm
parent2.esp
------
Fallout4.esm
parent0.esp
parent1.esm
parent2.esp
------
Fallout4.esm
parent0.esp
parent1.esm
parent2.esp
master with spaces.esm
------
Fallout4.esm
parent0.esp
parent1.esm
parent2.esp
plugin with spaces.esp
------
EOF
	ok($ret);
}

# dump -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				-v
				), $plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm
------
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# dump -v --include-self
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--include-self
				-v
				), $plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
[01] cell_compressed_xxxx.esp
------
compressed.esp (size: 58):
[00] Fallout4.esm
[01] compressed.esp
------
empty.esp (size: 58):
[00] Fallout4.esm
[01] empty.esp
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
[01] master with spaces.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
[02] parent0.esp
------
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
[04] parent1.esm
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
[04] parent2.esp
------
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] parent3.esp
------
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] parent4.esm
------
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm
[05] plugin with spaces.esp
------
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
[05] plugin.esp
------
xxxx.esp (size: 94316):
[00] xxxx.esp
EOF
	ok($ret);
}


# dump -r -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				-r
				-v
				), $plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
Fallout4.esm (size: 94316):

cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
Fallout4.esm (size: 94316):

compressed.esp (size: 58):
[00] Fallout4.esm
------
Fallout4.esm (size: 94316):

empty.esp (size: 58):
[00] Fallout4.esm
------
Fallout4.esm (size: 94316):

master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
Fallout4.esm (size: 94316):

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Fallout4.esm (size: 94316):

DLCCoast.esm (size: 94316):

DLCNukaWorld.esm (size: 94316):

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
Fallout4.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

DLCworkshop03.esm (size: 94316):

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

DLCNukaWorld.esm (size: 94316):

DLCCoast.esm (size: 94316):

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp

parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Fallout4.esm (size: 94316):

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

DLCNukaWorld.esm (size: 94316):

DLCCoast.esm (size: 94316):

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp

DLCworkshop03.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm

parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Fallout4.esm (size: 94316):

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

DLCNukaWorld.esm (size: 94316):

DLCCoast.esm (size: 94316):

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp

DLCworkshop03.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm

parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Fallout4.esm (size: 94316):

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

DLCNukaWorld.esm (size: 94316):

DLCCoast.esm (size: 94316):

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp

DLCworkshop03.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm

master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm

plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm
------
Fallout4.esm (size: 94316):

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

DLCNukaWorld.esm (size: 94316):

DLCCoast.esm (size: 94316):

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp

DLCworkshop03.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm

master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm

plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm

plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# --esp-to-esm -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--esp-to-esm
				-v
				), $plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esm
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esp": [03] parent2.esm
Writing "parent3.esp": [01] parent0.esm
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "parent4.esm": [03] parent2.esm
Writing "parent4.esm": [01] parent0.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "plugin with spaces.esp": [03] parent2.esm
Writing "plugin with spaces.esp": [01] parent0.esm
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] master with spaces.esm
------
Writing "plugin.esp": [04] plugin with spaces.esm
Writing "plugin.esp": [03] parent2.esm
Writing "plugin.esp": [01] parent0.esm
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] plugin with spaces.esm
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# --esp-to-esm --sub -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--esp-to-esm
				--sub parent:rename
				-v
				),
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'rename0.esm',
	  'rename2.esm',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] rename0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] rename0.esm
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esp": [03] rename2.esm
Writing "parent3.esp": [01] rename0.esm
parent3.esp (size: 154):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
------
Writing "parent4.esm": [03] rename2.esm
Writing "parent4.esm": [01] rename0.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
------
Writing "plugin with spaces.esp": [03] rename2.esm
Writing "plugin with spaces.esp": [01] rename0.esm
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
[04] master with spaces.esm
------
Writing "plugin.esp": [04] plugin with spaces.esm
Writing "plugin.esp": [03] rename2.esm
Writing "plugin.esp": [01] rename0.esm
plugin.esp (size: 197):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
[04] plugin with spaces.esm
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# --esp-to-esm --sub -r -v (parent3.esp only)
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	my $plugin = 'parent3.esp';
	push @res, combined_from(sub {
		$ret |= main(qw(
			--esp-to-esm
			--sub parent:rename
			-r
			-v
			),
			$plugin,
		);
	});

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'rename0.esm',
	  'rename2.esm',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
Writing "parent3.esp": [03] rename2.esm
Writing "parent3.esp": [01] rename0.esm
Writing "parent1.esm": [03] rename0.esm
Fallout4.esm (size: 94316):

DLCNukaWorld.esm (size: 94316):

DLCCoast.esm (size: 94316):

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] rename0.esm

DLCworkshop03.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

rename2.esm (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm

DLCworkshop01.esm (size: 94316):

rename0.esm (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

parent3.esp (size: 154):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
EOF
	ok($ret);
}


# --esp-to-esm --copy-plugin-to-esm -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--esp-to-esm
				--copy-plugin-to-esm
				-v
				),
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esm',
	  'compressed.esp',
	  'empty.esm',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esm',
	  'parent2.esp',
	  'parent3.esm',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esm',
	  'plugin with spaces.esp',
	  'plugin.esm',
	  'plugin.esp',
	  'xxxx.esm',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esm (size: 58):
[00] Fallout4.esm
------
compressed.esm (size: 58):
[00] Fallout4.esm
------
empty.esm (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esm (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esm
------
parent2.esm (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esm": [03] parent2.esm
Writing "parent3.esm": [01] parent0.esm
parent3.esm (size: 154):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "parent4.esm": [03] parent2.esm
Writing "parent4.esm": [01] parent0.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "plugin with spaces.esm": [03] parent2.esm
Writing "plugin with spaces.esm": [01] parent0.esm
plugin with spaces.esm (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] master with spaces.esm
------
Writing "plugin.esm": [04] plugin with spaces.esm
Writing "plugin.esm": [03] parent2.esm
Writing "plugin.esm": [01] parent0.esm
plugin.esm (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] plugin with spaces.esm
------
xxxx.esm (size: 94316):
EOF
	ok($ret);
}

# --esp-to-esm --copy-plugin-to-esm --sub -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--esp-to-esm
				--copy-plugin-to-esm
				-v
				),
				'--sub', '/[^A-Za-z0-9_.-]/:_',
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esm',
	  'compressed.esp',
	  'empty.esm',
	  'empty.esp',
	  'master with spaces.esm',
	  'master_with_spaces.esm',
	  'parent0.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esm',
	  'parent2.esp',
	  'parent3.esm',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esm',
	  'plugin.esp',
	  'plugin_with_spaces.esm',
	  'xxxx.esm',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esm (size: 58):
[00] Fallout4.esm
------
compressed.esm (size: 58):
[00] Fallout4.esm
------
empty.esm (size: 58):
[00] Fallout4.esm
------
master_with_spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esm (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esm
------
parent2.esm (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esm": [03] parent2.esm
Writing "parent3.esm": [01] parent0.esm
parent3.esm (size: 154):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "parent4.esm": [03] parent2.esm
Writing "parent4.esm": [01] parent0.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "plugin_with_spaces.esm": [03] parent2.esm
Writing "plugin_with_spaces.esm": [01] parent0.esm
plugin_with_spaces.esm (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] master with spaces.esm
------
Writing "plugin.esm": [04] plugin_with_spaces.esm
Writing "plugin.esm": [03] parent2.esm
Writing "plugin.esm": [01] parent0.esm
plugin.esm (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] plugin_with_spaces.esm
------
xxxx.esm (size: 94316):
EOF
	ok($ret);
}

# --esm-to-esp -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--esm-to-esp
				-v
				), $plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm
------
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# --esm-to-esp --sub -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--esm-to-esp
				--sub parent:rename
				-v
				),
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm
------
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# --esm-to-esp --sub -r -v (parent3.esp only)
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	my $plugin = 'parent3.esp';
	push @res, combined_from(sub {
		$ret |= main(qw(
			--esm-to-esp
			--sub parent:rename
			-r
			-v
			),
			$plugin,
		);
	});

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
Fallout4.esm (size: 94316):

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

DLCworkshop03.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm

parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
EOF
	ok($ret);
}


# --esm-to-esp --copy-plugin-to-esp -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--esm-to-esp
				--copy-plugin-to-esp
				-v
				),
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esp',
	  'parent0.esp',
	  'parent1.esp',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'parent4.esp',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esp (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
parent1.esp (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
Writing "parent2.esp": [03] parent1.esp
unlink parent1.esm
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esp
------
Writing "parent3.esp": [02] parent1.esp
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esp
[03] parent2.esp
------
Writing "parent4.esp": [02] parent1.esp
parent4.esp (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esp
[03] parent2.esp
------
Writing "plugin with spaces.esp": [04] master with spaces.esp
Writing "plugin with spaces.esp": [02] parent1.esp
unlink master with spaces.esm
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esp
[03] parent2.esp
[04] master with spaces.esp
------
Writing "plugin.esp": [02] parent1.esp
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esp
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# --esm-to-esp --copy-plugin-to-esp --sub -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	# add special characters
	foreach (grep !/parent/, @plugins) {
		my $old = $_;
		s/\.esp$/ space right here.esp/g;
		rename($old, $_) or die "rename: $old: $!";
	}

	foreach my $plugin (@plugins) {
		push @res, combined_from(sub {
			$ret |= main(qw(
				--esm-to-esp
				--copy-plugin-to-esp
				-v
				),
				'--sub', '/[^A-Za-z0-9_.-]/:_',
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx space right here.esp',
	  'cell_compressed_xxxx_space_right_here.esp',
	  'compressed space right here.esp',
	  'compressed_space_right_here.esp',
	  'empty space right here.esp',
	  'empty_space_right_here.esp',
	  'master_with_spaces.esp',
	  'parent0.esp',
	  'parent1.esp',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'parent4.esp',
	  'plugin space right here.esp',
	  'plugin with spaces space right here.esp',
	  'plugin_space_right_here.esp',
	  'plugin_with_spaces_space_right_here.esp',
	  'xxxx space right here.esp',
	  'xxxx_space_right_here.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx_space_right_here.esp (size: 58):
[00] Fallout4.esm
------
compressed_space_right_here.esp (size: 58):
[00] Fallout4.esm
------
empty_space_right_here.esp (size: 58):
[00] Fallout4.esm
------
master_with_spaces.esp (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
parent1.esp (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
Writing "parent2.esp": [03] parent1.esp
unlink parent1.esm
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esp
------
Writing "parent3.esp": [02] parent1.esp
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esp
[03] parent2.esp
------
Writing "parent4.esp": [02] parent1.esp
parent4.esp (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esp
[03] parent2.esp
------
Writing "plugin_with_spaces_space_right_here.esp": [04] master_with_spaces.esp
Writing "plugin_with_spaces_space_right_here.esp": [02] parent1.esp
unlink master with spaces.esm
plugin_with_spaces_space_right_here.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esp
[03] parent2.esp
[04] master_with_spaces.esp
------
Writing "plugin_space_right_here.esp": [02] parent1.esp
plugin_space_right_here.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esp
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx_space_right_here.esp (size: 94316):
EOF
	ok($ret);
}

# --esp-to-esm -v
# --esm-to-esp -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @{$res[0]}, combined_from(sub {
			$ret |= main(qw(
				--esp-to-esm
				-v
				), $plugin,
			);
		});
	}

	foreach my $plugin (@plugins) {
		push @{$res[1]}, combined_from(sub {
			$ret |= main(qw(
				--esm-to-esp
				-v
				), $plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("======\n", map join("------\n", @$_), @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esm
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esp": [03] parent2.esm
Writing "parent3.esp": [01] parent0.esm
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "parent4.esm": [03] parent2.esm
Writing "parent4.esm": [01] parent0.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "plugin with spaces.esp": [03] parent2.esm
Writing "plugin with spaces.esp": [01] parent0.esm
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] master with spaces.esm
------
Writing "plugin.esp": [04] plugin with spaces.esm
Writing "plugin.esp": [03] parent2.esm
Writing "plugin.esp": [01] parent0.esm
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] plugin with spaces.esm
------
xxxx.esp (size: 94316):
======
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esp
unlink parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esp": [03] parent2.esp
Writing "parent3.esp": [01] parent0.esp
unlink parent2.esm
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Writing "parent4.esm": [03] parent2.esp
Writing "parent4.esm": [01] parent0.esp
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Writing "plugin with spaces.esp": [03] parent2.esp
Writing "plugin with spaces.esp": [01] parent0.esp
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm
------
Writing "plugin.esp": [04] plugin with spaces.esp
Writing "plugin.esp": [03] parent2.esp
Writing "plugin.esp": [01] parent0.esp
unlink plugin with spaces.esm
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# --esp-to-esm --sub -v
# --esm-to-esp --sub -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @{$res[0]}, combined_from(sub {
			$ret |= main(qw(
				--esp-to-esm
				--sub parent:rename
				-v
				),
				$plugin,
			);
		});
	}

	foreach my $plugin (@plugins) {
		push @{$res[1]}, combined_from(sub {
			$ret |= main(qw(
				--esm-to-esp
				--sub rename:parent
				-v
				),
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("======\n", map join("------\n", @$_), @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] rename0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] rename0.esm
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esp": [03] rename2.esm
Writing "parent3.esp": [01] rename0.esm
parent3.esp (size: 154):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
------
Writing "parent4.esm": [03] rename2.esm
Writing "parent4.esm": [01] rename0.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
------
Writing "plugin with spaces.esp": [03] rename2.esm
Writing "plugin with spaces.esp": [01] rename0.esm
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
[04] master with spaces.esm
------
Writing "plugin.esp": [04] plugin with spaces.esm
Writing "plugin.esp": [03] rename2.esm
Writing "plugin.esp": [01] rename0.esm
plugin.esp (size: 197):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
[04] plugin with spaces.esm
------
xxxx.esp (size: 94316):
======
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esp
unlink rename0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esp": [03] parent2.esp
Writing "parent3.esp": [01] parent0.esp
unlink rename2.esm
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Writing "parent4.esm": [03] parent2.esp
Writing "parent4.esm": [01] parent0.esp
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Writing "plugin with spaces.esp": [03] parent2.esp
Writing "plugin with spaces.esp": [01] parent0.esp
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm
------
Writing "plugin.esp": [04] plugin with spaces.esp
Writing "plugin.esp": [03] parent2.esp
Writing "plugin.esp": [01] parent0.esp
unlink plugin with spaces.esm
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

# --esp-to-esm --sub -r -v
# --esm-to-esp --sub -r -v (parent3.esp only)
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	my $plugin = 'parent3.esp';

	push @{$res[0]}, combined_from(sub {
		$ret |= main(qw(
			--esp-to-esm
			--sub parent:rename
			-r
			-v
			),
			$plugin,
		);
	});

	push @{$res[1]}, combined_from(sub {
		$ret |= main(qw(
			--esm-to-esp
			--sub rename:parent
			-r
			-v
			),
			$plugin,
		);
	});

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esp',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esp',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("======\n", map join("------\n", @$_), @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
Writing "parent3.esp": [03] rename2.esm
Writing "parent3.esp": [01] rename0.esm
Writing "parent1.esm": [03] rename0.esm
Fallout4.esm (size: 94316):

DLCNukaWorld.esm (size: 94316):

DLCCoast.esm (size: 94316):

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] rename0.esm

DLCworkshop03.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

rename2.esm (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm

DLCworkshop01.esm (size: 94316):

rename0.esm (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

parent3.esp (size: 154):
[00] Fallout4.esm
[01] rename0.esm
[02] parent1.esm
[03] rename2.esm
======
Writing "parent3.esp": [03] parent2.esp
Writing "parent3.esp": [01] parent0.esp
Writing "parent1.esm": [03] parent0.esp
unlink rename2.esm
unlink rename0.esm
Fallout4.esm (size: 94316):

DLCNukaWorld.esm (size: 94316):

DLCCoast.esm (size: 94316):

parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp

DLCworkshop03.esm (size: 94316):

DLCworkshop02.esm (size: 94316):

parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm

DLCworkshop01.esm (size: 94316):

parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm

parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
EOF
	ok($ret);
}

# --esp-to-esm --copy-plugin-to-esm -v
# --esm-to-esp -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @{$res[0]}, combined_from(sub {
			$ret |= main(qw(
				--esp-to-esm
				--copy-plugin-to-esm
				-v
				),
				$plugin,
			);
		});
	}

	foreach my $plugin (@plugins) {
		push @{$res[1]}, combined_from(sub {
			$ret |= main(qw(
				--esm-to-esp
				-v
				),
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esm',
	  'compressed.esp',
	  'empty.esm',
	  'empty.esp',
	  'master with spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esm',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esm',
	  'plugin with spaces.esp',
	  'plugin.esm',
	  'plugin.esp',
	  'xxxx.esm',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("======\n", map join("------\n", @$_), @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esm (size: 58):
[00] Fallout4.esm
------
compressed.esm (size: 58):
[00] Fallout4.esm
------
empty.esm (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esm (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esm
------
parent2.esm (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esm": [03] parent2.esm
Writing "parent3.esm": [01] parent0.esm
parent3.esm (size: 154):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "parent4.esm": [03] parent2.esm
Writing "parent4.esm": [01] parent0.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "plugin with spaces.esm": [03] parent2.esm
Writing "plugin with spaces.esm": [01] parent0.esm
plugin with spaces.esm (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] master with spaces.esm
------
Writing "plugin.esm": [04] plugin with spaces.esm
Writing "plugin.esm": [03] parent2.esm
Writing "plugin.esm": [01] parent0.esm
plugin.esm (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] plugin with spaces.esm
------
xxxx.esm (size: 94316):
======
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esp
unlink parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Writing "parent4.esm": [03] parent2.esp
Writing "parent4.esm": [01] parent0.esp
unlink parent2.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master with spaces.esm
------
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}


# --esp-to-esm --copy-plugin-to-esm --sub -v
# --esm-to-esp --sub -v
{
	my ($out, $res, $ret, @res);
	my ($dir, @plugins) = temp_dir_prepare($plugin_dir);
	local $CWD = $dir;

	foreach my $plugin (@plugins) {
		push @{$res[0]}, combined_from(sub {
			$ret |= main(qw(
				--esp-to-esm
				--copy-plugin-to-esm
				-v
				),
				'--sub', '/[^A-Za-z0-9_.-]/:_',
				$plugin,
			);
		});
	}

	foreach my $plugin (@plugins) {
		push @{$res[1]}, combined_from(sub {
			$ret |= main(qw(
				--esm-to-esp
				-v
				),
				'--sub', '/[^A-Za-z0-9_.-]/:_',
				$plugin,
			);
		});
	}

	$out = [
	  'DLCCoast.esm',
	  'DLCNukaWorld.esm',
	  'DLCRobot.esm',
	  'DLCworkshop01.esm',
	  'DLCworkshop02.esm',
	  'DLCworkshop03.esm',
	  'Fallout4.esm',
	  'cell_compressed_xxxx.esm',
	  'cell_compressed_xxxx.esp',
	  'compressed.esm',
	  'compressed.esp',
	  'empty.esm',
	  'empty.esp',
	  'master_with_spaces.esm',
	  'parent0.esp',
	  'parent1.esm',
	  'parent2.esp',
	  'parent3.esm',
	  'parent3.esp',
	  'parent4.esm',
	  'plugin with spaces.esp',
	  'plugin.esm',
	  'plugin.esp',
	  'plugin_with_spaces.esm',
	  'xxxx.esm',
	  'xxxx.esp'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("======\n", map join("------\n", @$_), @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
cell_compressed_xxxx.esm (size: 58):
[00] Fallout4.esm
------
compressed.esm (size: 58):
[00] Fallout4.esm
------
empty.esm (size: 58):
[00] Fallout4.esm
------
master_with_spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esm (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esm
------
parent2.esm (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
Writing "parent3.esm": [03] parent2.esm
Writing "parent3.esm": [01] parent0.esm
parent3.esm (size: 154):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "parent4.esm": [03] parent2.esm
Writing "parent4.esm": [01] parent0.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
------
Writing "plugin_with_spaces.esm": [03] parent2.esm
Writing "plugin_with_spaces.esm": [01] parent0.esm
plugin_with_spaces.esm (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] master with spaces.esm
------
Writing "plugin.esm": [04] plugin_with_spaces.esm
Writing "plugin.esm": [03] parent2.esm
Writing "plugin.esm": [01] parent0.esm
plugin.esm (size: 197):
[00] Fallout4.esm
[01] parent0.esm
[02] parent1.esm
[03] parent2.esm
[04] plugin_with_spaces.esm
------
xxxx.esm (size: 94316):
======
cell_compressed_xxxx.esp (size: 58):
[00] Fallout4.esm
------
compressed.esp (size: 58):
[00] Fallout4.esm
------
empty.esp (size: 58):
[00] Fallout4.esm
------
master with spaces.esm (size: 58, flags: [esm]):
[00] Fallout4.esm
------
parent0.esp (size: 96):
[00] Fallout4.esm
[01] DLCworkshop01.esm
------
Writing "parent1.esm": [03] parent0.esp
unlink parent0.esm
parent1.esm (size: 160, flags: [esm, localized]):
[00] Fallout4.esm
[01] DLCCoast.esm
[02] DLCNukaWorld.esm
[03] parent0.esp
------
parent2.esp (size: 166):
[00] Fallout4.esm
[01] DLCworkshop02.esm
[02] DLCworkshop03.esm
[03] parent1.esm
------
parent3.esp (size: 154):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Writing "parent4.esm": [03] parent2.esp
Writing "parent4.esm": [01] parent0.esp
unlink parent2.esm
parent4.esm (size: 154, flags: [esm]):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
------
Writing "plugin with spaces.esp": [04] master_with_spaces.esm
unlink master with spaces.esm
plugin with spaces.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] master_with_spaces.esm
------
plugin.esp (size: 197):
[00] Fallout4.esm
[01] parent0.esp
[02] parent1.esm
[03] parent2.esp
[04] plugin with spaces.esp
------
xxxx.esp (size: 94316):
EOF
	ok($ret);
}

done_testing();
