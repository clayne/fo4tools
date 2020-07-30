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

use TES::Plugin::Archive::BA2::Ent qw();

# pp_fast
{
my $in = 'Scripts/Source/User/UFO4P/UFO4PRetroactive103Script.psc';
my $out = 1722047686;
my $ret = TES::Plugin::Archive::BA2::Ent::crc32_bs_pp_fast($in);

eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# pp
{
my $in = 'Scripts/Source/User/UFO4P/UFO4PRetroactive103Script.psc';
my $out = 1722047686;
my $ret = TES::Plugin::Archive::BA2::Ent::crc32_bs_pp($in);

eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# xs
{
my $in = 'Scripts/Source/User/UFO4P/UFO4PRetroactive103Script.psc';
my $out = 1722047686;
my $ret = TES::Plugin::Archive::BA2::Ent::crc32_bs_xs($in);

eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

done_testing();

