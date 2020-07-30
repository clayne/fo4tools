#!/usr/bin/perl

use File::Spec qw(join);
use File::Temp qw(tempfile tempdir);
use Test::Differences;
use Test::More;
use Test::Deep;
use Data::Dumper;
use Carp qw(cluck confess);

use strict;
use autodie qw(:all);
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;

local $Data::Dumper::Deepcopy = 1;
local $Data::Dumper::Sortkeys = 1;

use TES::Plugin::Common qw(file_sub);

# noop
{
my $in = 'Scripts/Source/User/UFO4P/UFO4PRetroactive103Script.psc';
my $out = 'Scripts/Source/User/UFO4P/UFO4PRetroactive103Script.psc';
my $ret = file_sub($in);

eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# sanitize, esp -> esm
{
my $in = 'sound/voice/Unofficial Fallout 4 Patch.esp/PlayerVoiceFemale01/00016D03_1.fuz';
my $out = 'sound/voice/Unofficial_Fallout_4_Patch.esm/PlayerVoiceFemale01/00016D03_1.fuz';
my $ret = file_sub($in,
	sub => [ [ qr/[^A-Za-z0-9_.\/-]/, '_' ] ],
	sub_ext => [ [ 'esp', 'esm' ] ],
);

eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# sanitize, esp -> esm, use split
{
my $in = 'sound/voice/Unofficial Fallout 4 Patch.esp/PlayerVoiceFemale01/00016D03_1.fuz';
my $out = 'sound/voice/Unofficial_Fallout_4_Patch.esm/PlayerVoiceFemale01/00016D03_1.fuz';
my $ret = file_sub($in,
	sub => [ [ qr/[^A-Za-z0-9_.\/-]/, '_' ] ],
	sub_ext => [ 'esp:esm' ],
);

eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# sanitize, esp -> esm, match
{
my $in = 'sound/voice/Unofficial Fallout 4 Patch.esp/PlayerVoiceFemale01/00016D03_1.fuz';
my $out = 'sound/voice/Unofficial_Fallout_4 Patch.esp/PlayerVoiceFemale01/00016D03_1.fuz';
my $ret = file_sub($in,
	sub => [ [ qr/\s/, '_' ] ],
	sub_ext => [ [ 'esp', 'esm' ] ],
	match => 'Unofficial Fallout 4',
);

eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# sanitize, esp -> esm, match, match_ext
{
my $in = 'sound/voice/Unofficial Fallout 4 Patch.esp/PlayerVoiceFemale01/00016D03_1.fuz';
my $out = 'sound/voice/Unofficial_Fallout_4 Patch.esm/PlayerVoiceFemale01/00016D03_1.fuz';
my $ret = file_sub($in,
	sub => [ [ qr/\s/, '_' ] ],
	sub_ext => [ [ 'esp', 'esm' ] ],
	match => 'Unofficial Fallout 4',
	match_ext => qr/([^\/]+\.esp)/,
);

eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# bad sub (from/to)
{
my $in = 'sound/voice/Unofficial Fallout 4 Patch.esp/PlayerVoiceFemale01/00016D03_1.fuz';
my $out = qr/Problem with parsing from\/to/;
my $ret = eval { file_sub($in, sub => [ [ qr/[^\/]+/ ] ]) };

like($@, $out) or print STDERR explain $ret, "\n";
}

# bad sub (sub doesn't preserve length)
{
my $in = 'sound/voice/Unofficial Fallout 4 Patch.esp/PlayerVoiceFemale01/00016D03_1.fuz';
my $out = qr/Unequal substitution lengths/;
my $ret = eval { file_sub($in, sub => [ [ qr/[^\/]+/, '_' ] ]) };

like($@, $out) or print STDERR explain $ret, "\n";
}

done_testing();

