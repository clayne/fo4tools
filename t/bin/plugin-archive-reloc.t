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

package ba2dump;
require 'bin/ba2dump';
*main::ba2dump = \&ba2dump::main;;

package main;
require 'bin/plugin-archive-reloc';

my $archive_dir = 't/data';

sub ls_dir {
	my $src = shift;

	opendir(my $dh, $src) || die "opendir: $!";
	my @archives = grep /\.ba2/, readdir($dh);
	closedir $dh or die "closedir: $!";

	return [ sort @archives ];
}

sub temp_dir_prepare {
	my $src = shift;
	my $dst = tempdir(CLEANUP => 1);

	opendir(my $dh, $src) || die "opendir: $!";
	my @archives = grep /\.ba2/, readdir($dh);
	closedir $dh or die "closedir: $!";

	foreach my $archive (@archives) {
		my $filename_src = File::Spec->join($src, $archive);
		my $filename_dst = File::Spec->join($dst, $archive);
		cp($filename_src, $filename_dst) or die "cp: $archive";
	}

	return ($dst, @archives);
}

# noop
{
	my ($out, $res, $ret, @res, @dump);
	my ($dir, @archives) = temp_dir_prepare($archive_dir);
	local $CWD = $dir;

	foreach my $archive (@archives) {
		push @res, combined_from(sub {
			$ret |= main(
				$archive,
			);
		});
		push @dump, combined_from(sub {
			$ret |= ba2dump('-vl', $archive);
		});
	}

	$out = [
	  'Test - Main.ba2',
	  'Test - Textures.ba2',
	  'master with spaces - Main.ba2',
	  'parent0 - Main.ba2',
	  'parent0 - Textures.ba2',
	  'plugin - Main.ba2',
	  'plugin with spaces - Main.ba2'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
------
------
------
------
------
------
EOF
	$res = join("------\n", @dump);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
                     filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
master with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xc54ee2b2 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/master with spaces.esm/CM0001E4EB.NIF
master with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x70ae44d9 | 0x00100100 | dlst | Strings/master with spaces_en.dlstrings
master with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x70ae44d9 | 0x00100100 | ilst | Strings/master with spaces_en.ilstrings
master with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x70ae44d9 | 0x00100100 | stri | Strings/master with spaces_en.strings
------
          filename | size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
parent0 - Main.ba2 |  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
parent0 - Main.ba2 |  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
------
              filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
parent0 - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
parent0 - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
parent0 - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
parent0 - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
------
         filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | ext | name
plugin - Main.ba2 | 18538 |   5438 |  70.67% | 0x0deaf72b | 0xb6c56cdf | 0x00100100 | nif | Meshes/plugin.esp/CM0001E4EB.NIF
------
                     filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xc54ee2b2 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/master with spaces.esm/CM0001E4EB.NIF
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x9267b542 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/parent2.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xff2333e9 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/plugin with spaces.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xa82ed1a5 | 0x00100100 | dlst | Strings/plugin with spaces_en.dlstrings
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xa82ed1a5 | 0x00100100 | ilst | Strings/plugin with spaces_en.ilstrings
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xa82ed1a5 | 0x00100100 | stri | Strings/plugin with spaces_en.strings
------
       filename | size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
Test - Main.ba2 |  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
Test - Main.ba2 |  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
------
           filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
Test - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
Test - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
Test - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
Test - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
EOF
	ok($ret);
}

# noop -v
{
	my ($out, $res, $ret, @res, @dump);
	my ($dir, @archives) = temp_dir_prepare($archive_dir);
	local $CWD = $dir;

	foreach my $archive (@archives) {
		push @res, combined_from(sub {
			$ret |= main(
				qw(
					-v
				),
				$archive,
			);
		});
		push @dump, combined_from(sub {
			$ret |= ba2dump('-vl', $archive);
		});
	}

	$out = [
	  'Test - Main.ba2',
	  'Test - Textures.ba2',
	  'master with spaces - Main.ba2',
	  'parent0 - Main.ba2',
	  'parent0 - Textures.ba2',
	  'plugin - Main.ba2',
	  'plugin with spaces - Main.ba2'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
master with spaces - Main.ba2	Meshes/master with spaces.esm/CM0001E4EB.NIF
master with spaces - Main.ba2	Strings/master with spaces_en.dlstrings
------
------
------
plugin - Main.ba2	Meshes/plugin.esp/CM0001E4EB.NIF
------
plugin with spaces - Main.ba2	Meshes/master with spaces.esm/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Meshes/parent2.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Meshes/plugin with spaces.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Strings/plugin with spaces_en.dlstrings
------
------
EOF
	$res = join("------\n", @dump);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
                     filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
master with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xc54ee2b2 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/master with spaces.esm/CM0001E4EB.NIF
master with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x70ae44d9 | 0x00100100 | dlst | Strings/master with spaces_en.dlstrings
master with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x70ae44d9 | 0x00100100 | ilst | Strings/master with spaces_en.ilstrings
master with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x70ae44d9 | 0x00100100 | stri | Strings/master with spaces_en.strings
------
          filename | size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
parent0 - Main.ba2 |  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
parent0 - Main.ba2 |  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
------
              filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
parent0 - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
parent0 - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
parent0 - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
parent0 - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
------
         filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | ext | name
plugin - Main.ba2 | 18538 |   5438 |  70.67% | 0x0deaf72b | 0xb6c56cdf | 0x00100100 | nif | Meshes/plugin.esp/CM0001E4EB.NIF
------
                     filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xc54ee2b2 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/master with spaces.esm/CM0001E4EB.NIF
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x9267b542 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/parent2.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xff2333e9 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/plugin with spaces.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xa82ed1a5 | 0x00100100 | dlst | Strings/plugin with spaces_en.dlstrings
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xa82ed1a5 | 0x00100100 | ilst | Strings/plugin with spaces_en.ilstrings
plugin with spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xa82ed1a5 | 0x00100100 | stri | Strings/plugin with spaces_en.strings
------
       filename | size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
Test - Main.ba2 |  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
Test - Main.ba2 |  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
------
           filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
Test - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
Test - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
Test - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
Test - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
EOF
	ok($ret);
}

# --esp-to-esm -v
{
	my ($out, $res, $ret, @res, @dump);
	my ($dir, @archives) = temp_dir_prepare($archive_dir);
	local $CWD = $dir;

	foreach my $archive (@archives) {
		# archive may be renamed as part of substitutions
		my ($archive_base, $archive_type) = (basename($archive) =~ /^(.+) - (.+)\.ba2$/);
		my $archive_base_new = file_sub($archive_base, sub => [ qr/[^A-Za-z0-9_.-]/, '_' ]);
		my $archive_new = join('.', join(' - ', $archive_base_new, $archive_type), 'ba2');

		push @res, combined_from(sub {
			$ret |= main(
				qw(
					-v
					--esp-to-esm
				),
				$archive,
			);
		});
		push @dump, combined_from(sub {
			$ret |= ba2dump('-vl', $archive_new);
		});
	}

	$out = [
	  'Test - Main.ba2',
	  'Test - Main.ba2.save',
	  'Test - Textures.ba2',
	  'Test - Textures.ba2.save',
	  'master with spaces - Main.ba2',
	  'master with spaces - Main.ba2.save',
	  'master_with_spaces - Main.ba2',
	  'parent0 - Main.ba2',
	  'parent0 - Main.ba2.save',
	  'parent0 - Textures.ba2',
	  'parent0 - Textures.ba2.save',
	  'plugin - Main.ba2',
	  'plugin - Main.ba2.save',
	  'plugin with spaces - Main.ba2',
	  'plugin with spaces - Main.ba2.save',
	  'plugin_with_spaces - Main.ba2'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
master with spaces - Main.ba2	Meshes/master with spaces.esm/CM0001E4EB.NIF
master with spaces - Main.ba2	Strings/master with spaces_en.dlstrings
------
------
------
plugin - Main.ba2	Meshes/plugin.esp/CM0001E4EB.NIF
------
plugin with spaces - Main.ba2	Meshes/master with spaces.esm/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Meshes/parent2.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Meshes/plugin with spaces.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Strings/plugin with spaces_en.dlstrings
------
------
EOF
	$res = join("------\n", @dump);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
                     filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
master_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xf91890a4 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/master_with_spaces.esm/CM0001E4EB.NIF
master_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x253883fd | 0x00100100 | dlst | Strings/master_with_spaces_en.dlstrings
master_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x253883fd | 0x00100100 | ilst | Strings/master_with_spaces_en.ilstrings
master_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x253883fd | 0x00100100 | stri | Strings/master_with_spaces_en.strings
------
          filename | size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
parent0 - Main.ba2 |  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
parent0 - Main.ba2 |  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
------
              filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
parent0 - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
parent0 - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
parent0 - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
parent0 - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
------
         filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | ext | name
plugin - Main.ba2 | 18538 |   5438 |  70.67% | 0x6eec9bf2 | 0xb6c56cdf | 0x00100100 | nif | Meshes/plugin.esm/CM0001E4EB.NIF
------
                     filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xf91890a4 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/master_with_spaces.esm/CM0001E4EB.NIF
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xf161d99b | 0xb6c56cdf | 0x00100100 |  nif | Meshes/parent2.esm/CM0001E4EB.NIF
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xa0732d26 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/plugin_with_spaces.esm/CM0001E4EB.NIF
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xfdb81681 | 0x00100100 | dlst | Strings/plugin_with_spaces_en.dlstrings
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xfdb81681 | 0x00100100 | ilst | Strings/plugin_with_spaces_en.ilstrings
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xfdb81681 | 0x00100100 | stri | Strings/plugin_with_spaces_en.strings
------
       filename | size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
Test - Main.ba2 |  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
Test - Main.ba2 |  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
------
           filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
Test - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
Test - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
Test - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
Test - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
EOF
	ok($ret);
}

# --esp-to-esm --inplace -v
{
	my ($out, $res, $ret, @res, @dump);
	my ($dir, @archives) = temp_dir_prepare($archive_dir);
	local $CWD = $dir;

	foreach my $archive (@archives) {
		# archive may be renamed as part of substitutions
		my ($archive_base, $archive_type) = (basename($archive) =~ /^(.+) - (.+)\.ba2$/);
		my $archive_base_new = file_sub($archive_base, sub => [ qr/[^A-Za-z0-9_.-]/, '_' ]);
		my $archive_new = join('.', join(' - ', $archive_base_new, $archive_type), 'ba2');

		push @res, combined_from(sub {
			$ret |= main(
				qw(
					-v
					--esp-to-esm
					--inplace
				),
				$archive,
			);
		});
		push @dump, combined_from(sub {
			$ret |= ba2dump('-vl', $archive_new);
		});
	}

	$out = [
	  'Test - Main.ba2',
	  'Test - Main.ba2.save',
	  'Test - Textures.ba2',
	  'Test - Textures.ba2.save',
	  'master with spaces - Main.ba2',
	  'master with spaces - Main.ba2.save',
	  'master_with_spaces - Main.ba2',
	  'parent0 - Main.ba2',
	  'parent0 - Main.ba2.save',
	  'parent0 - Textures.ba2',
	  'parent0 - Textures.ba2.save',
	  'plugin - Main.ba2',
	  'plugin - Main.ba2.save',
	  'plugin with spaces - Main.ba2',
	  'plugin with spaces - Main.ba2.save',
	  'plugin_with_spaces - Main.ba2'
	];

	$res = ls_dir($dir);
	eq_or_diff($res, $out) or print STDERR explain $res, "\n";

	$res = join("------\n", @res);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
master with spaces - Main.ba2	Meshes/master with spaces.esm/CM0001E4EB.NIF
master with spaces - Main.ba2	Strings/master with spaces_en.dlstrings
------
------
------
plugin - Main.ba2	Meshes/plugin.esp/CM0001E4EB.NIF
------
plugin with spaces - Main.ba2	Meshes/master with spaces.esm/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Meshes/parent2.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Meshes/plugin with spaces.esp/CM0001E4EB.NIF
plugin with spaces - Main.ba2	Strings/plugin with spaces_en.dlstrings
------
------
EOF
	$res = join("------\n", @dump);
	eq_or_diff($res, <<'EOF') or print STDERR explain $res, "\n";
                     filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
master_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xf91890a4 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/master_with_spaces.esm/CM0001E4EB.NIF
master_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x253883fd | 0x00100100 | dlst | Strings/master_with_spaces_en.dlstrings
master_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x253883fd | 0x00100100 | ilst | Strings/master_with_spaces_en.ilstrings
master_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0x253883fd | 0x00100100 | stri | Strings/master_with_spaces_en.strings
------
          filename | size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
parent0 - Main.ba2 |  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
parent0 - Main.ba2 |  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
------
              filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
parent0 - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
parent0 - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
parent0 - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
parent0 - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
------
         filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | ext | name
plugin - Main.ba2 | 18538 |   5438 |  70.67% | 0x6eec9bf2 | 0xb6c56cdf | 0x00100100 | nif | Meshes/plugin.esm/CM0001E4EB.NIF
------
                     filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xf91890a4 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/master_with_spaces.esm/CM0001E4EB.NIF
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xf161d99b | 0xb6c56cdf | 0x00100100 |  nif | Meshes/parent2.esm/CM0001E4EB.NIF
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0xa0732d26 | 0xb6c56cdf | 0x00100100 |  nif | Meshes/plugin_with_spaces.esm/CM0001E4EB.NIF
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xfdb81681 | 0x00100100 | dlst | Strings/plugin_with_spaces_en.dlstrings
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xfdb81681 | 0x00100100 | ilst | Strings/plugin_with_spaces_en.ilstrings
plugin_with_spaces - Main.ba2 | 18538 |   5438 |  70.67% | 0x29f6b58b | 0xfdb81681 | 0x00100100 | stri | Strings/plugin_with_spaces_en.strings
------
       filename | size | packed |   ratio |   dir_hash |  name_hash |      flags |  ext | name
Test - Main.ba2 |  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
Test - Main.ba2 |  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
------
           filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
Test - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
Test - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
Test - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
Test - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
EOF
	ok($ret);
}


done_testing();
