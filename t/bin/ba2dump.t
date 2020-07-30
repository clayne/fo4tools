#!/usr/bin/perl

use File::Spec qw(join);
use File::Temp qw(tempfile tempdir);
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
require 'bin/ba2dump';

# noop
{
	my $ret = main();
	ok($ret);
}

# dump
{
	my $ret;
	my $out = combined_from(sub {
		$ret = main(
			't/data/Test - Main.ba2',
			't/data/Test - Textures.ba2'
		);
	});

	eq_or_diff($out, <<'EOF') or print STDERR explain $out, "\n";
Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
Materials/Weapons/RocketHammer/RocketHammer.BGSM
Textures/Actors/FeralGhoulEye_d.DDS
Textures/Effects/WepLaserRedRingGrad.dds
Textures/Sky/SkyrimCloudsFill.DDS
Textures/Vehicles/Rust01LGrad_d.DDS
EOF

	ok($ret);
}

# dump -l
{
	my $ret;
	my $out = combined_from(sub {
		$ret = main(
			'-l',
			't/data/Test - Main.ba2',
			't/data/Test - Textures.ba2'
		);
	});

	eq_or_diff($out, <<'EOF') or print STDERR explain $out, "\n";
    t/data/Test - Main.ba2	Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
    t/data/Test - Main.ba2	Materials/Weapons/RocketHammer/RocketHammer.BGSM
t/data/Test - Textures.ba2	Textures/Actors/FeralGhoulEye_d.DDS
t/data/Test - Textures.ba2	Textures/Effects/WepLaserRedRingGrad.dds
t/data/Test - Textures.ba2	Textures/Sky/SkyrimCloudsFill.DDS
t/data/Test - Textures.ba2	Textures/Vehicles/Rust01LGrad_d.DDS
EOF

	ok($ret);
}

# dump -v
{
	my $ret;
	my $out = combined_from(sub {
		$ret = main(
			'-v',
			't/data/Test - Main.ba2',
			't/data/Test - Textures.ba2'
		);
	});

	eq_or_diff($out, <<'EOF') or print STDERR explain $out, "\n";
 size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips |  ext | name
  376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 |        |       |      | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
  433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 |        |       |      | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 |  dds | Textures/Actors/FeralGhoulEye_d.DDS
 4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 |  dds | Textures/Effects/WepLaserRedRingGrad.dds
 1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 |  dds | Textures/Sky/SkyrimCloudsFill.DDS
11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 |  dds | Textures/Vehicles/Rust01LGrad_d.DDS
EOF

	ok($ret);
}

# dump -vl
{
	my $ret;
	my $out = combined_from(sub {
		$ret = main(
			'-vl',
			't/data/Test - Main.ba2',
			't/data/Test - Textures.ba2'
		);
	});

	eq_or_diff($out, <<'EOF') or print STDERR explain $out, "\n";
                  filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips |  ext | name
    t/data/Test - Main.ba2 |   376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 |        |       |      | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
    t/data/Test - Main.ba2 |   433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 |        |       |      | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
t/data/Test - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 |  dds | Textures/Actors/FeralGhoulEye_d.DDS
t/data/Test - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 |  dds | Textures/Effects/WepLaserRedRingGrad.dds
t/data/Test - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 |  dds | Textures/Sky/SkyrimCloudsFill.DDS
t/data/Test - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 |  dds | Textures/Vehicles/Rust01LGrad_d.DDS
EOF

	ok($ret);
}

# dump -vvl
{
	my $ret;
	my $out = combined_from(sub {
		$ret = main(
			'-vvl',
			't/data/Test - Main.ba2',
			't/data/Test - Textures.ba2'
		);
	});

	eq_or_diff($out, <<'EOF') or print STDERR explain $out, "\n";
                  filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | cmap | dxgi | mips |  ext | name
    t/data/Test - Main.ba2 |   376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 |        |       |      |      |      | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
    t/data/Test - Main.ba2 |   433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 |        |       |      |      |      | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
t/data/Test - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 | 2048 |   71 |    8 |  dds | Textures/Actors/FeralGhoulEye_d.DDS
                           | 10936 |   4439 |  59.41% |            |            |            |        |       |      |      |  0-7 |      | 
t/data/Test - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 | 2048 |   87 |    1 |  dds | Textures/Effects/WepLaserRedRingGrad.dds
                           |  4096 |   2486 |  39.31% |            |            |            |        |       |      |      |    0 |      | 
t/data/Test - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 | 2048 |   77 |    6 |  dds | Textures/Sky/SkyrimCloudsFill.DDS
                           |  1392 |     28 |  97.99% |            |            |            |        |       |      |      |  0-5 |      | 
t/data/Test - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 | 2048 |   77 |    9 |  dds | Textures/Vehicles/Rust01LGrad_d.DDS
                           | 11024 |   3820 |  65.35% |            |            |            |        |       |      |      |  0-8 |      | 
EOF

	ok($ret);
}

# dump -vl --sort
{
	my $ret;
	my $out = combined_from(sub {
		$ret = main(
			'-vl',
			'--sort',
			't/data/Test - Main.ba2',
			't/data/Test - Textures.ba2'
		);
	});

	eq_or_diff($out, <<'EOF') or print STDERR explain $out, "\n";
                  filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips | ext | name
t/data/Test - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 | dds | Textures/Actors/FeralGhoulEye_d.DDS
t/data/Test - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 | dds | Textures/Effects/WepLaserRedRingGrad.dds
t/data/Test - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 | dds | Textures/Sky/SkyrimCloudsFill.DDS
t/data/Test - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 | dds | Textures/Vehicles/Rust01LGrad_d.DDS
EOF

	ok($ret);
}

# dump -vl --sort=size
{
	my $ret;
	my $out = combined_from(sub {
		$ret = main(
			'-vl',
			'--sort=size',
			't/data/Test - Main.ba2',
			't/data/Test - Textures.ba2'
		);
	});

	eq_or_diff($out, <<'EOF') or print STDERR explain $out, "\n";
                  filename |  size | packed |   ratio |   dir_hash |  name_hash |      flags | height | width | mips |  ext | name
    t/data/Test - Main.ba2 |   376 |    189 |  49.73% | 0x04136f5c | 0x7f49cd0f | 0x00100100 |        |       |      | bgsm | Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM
    t/data/Test - Main.ba2 |   433 |    192 |  55.66% | 0xe0e19227 | 0x00a0aced | 0x00100100 |        |       |      | bgsm | Materials/Weapons/RocketHammer/RocketHammer.BGSM
t/data/Test - Textures.ba2 |  1392 |     28 |  97.99% | 0x4fae90a3 | 0x1442ea39 | 0x00000000 |     32 |    32 |    6 |  dds | Textures/Sky/SkyrimCloudsFill.DDS
t/data/Test - Textures.ba2 |  4096 |   2486 |  39.31% | 0xea3c9738 | 0xc3754f64 | 0x00000000 |     32 |    32 |    1 |  dds | Textures/Effects/WepLaserRedRingGrad.dds
t/data/Test - Textures.ba2 | 10936 |   4439 |  59.41% | 0x809b60e0 | 0x3903d937 | 0x00000000 |    128 |   128 |    8 |  dds | Textures/Actors/FeralGhoulEye_d.DDS
t/data/Test - Textures.ba2 | 11024 |   3820 |  65.35% | 0xd36f43b4 | 0xf8380096 | 0x00000000 |    256 |    32 |    9 |  dds | Textures/Vehicles/Rust01LGrad_d.DDS
EOF

	ok($ret);
}

done_testing();
