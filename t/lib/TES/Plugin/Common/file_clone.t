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

use TES::Plugin::Common qw(file_clone);

sub stat_compare {
	my ($pre, $pst) = @_;
	return eq_or_diff([ @$pre[0,2,4..12] ], [ @$pst[0,2,4..12] ]);
}

# no overwrite, same file, noop
{
my ($fd, $filename) = tempfile(UNLINK => 1);
my @stat_pre = stat($filename) or die "stat: $!";
file_clone($filename, $filename);
my @stat_pst = stat($filename) or die "stat: $!";
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";
}

# no overwrite, new file
{
my ($fd, $filename) = tempfile(UNLINK => 1);
my @stat_pre = stat($filename) or die "stat: $!";
file_clone($filename, "$filename.new");
my @stat_pst = stat("$filename.new") or die "stat: $!";
unlink("$filename.new") or die "unlink: $!";

isnt($stat_pre[1], $stat_pst[1], 'different inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";
}

# overwrite, same file, no backup
{
my ($fd, $filename) = tempfile(UNLINK => 1);
my @stat_pre = stat($filename) or die "stat: $!";
file_clone($filename, $filename, overwrite => 1);
my @stat_pst = stat($filename) or die "stat: $!";

isnt($stat_pre[1], $stat_pst[1], 'different inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";
}

# overwrite, same file, backup
{
my ($fd, $filename) = tempfile(UNLINK => 1);
my @stat_pre = stat($filename) or die "stat: $!";
file_clone($filename, $filename, overwrite => 1, backup => 1);
my @stat_pst = stat("$filename.backup") or die "stat: $!";
unlink("$filename.backup") or die "unlink: $!";

is($stat_pre[1], $stat_pst[1], 'same inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";

@stat_pst = stat($filename) or die "stat: $!";
isnt($stat_pre[1], $stat_pst[1], 'different inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";
}

# overwrite, new file
{
my ($fd, $filename) = tempfile(UNLINK => 1);
my @stat_pre = stat($filename) or die "stat: $!";
file_clone($filename, "$filename.new", overwrite => 1);
my @stat_pst = stat($filename) or die "stat: $!";

is($stat_pre[1], $stat_pst[1], 'same inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";

@stat_pst = stat("$filename.new") or die "stat: $!";
unlink("$filename.new") or die "unlink: $!";
isnt($stat_pre[1], $stat_pst[1], 'different inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";
}

# overwrite, new file, backup, backup_always, backup extension
{
my ($fd, $filename) = tempfile(UNLINK => 1);
my @stat_pre = stat($filename) or die "stat: $!";
file_clone($filename, "$filename.new", overwrite => 1, backup => 1, backup_always => 1, backup_extension => 'save');
my @stat_pst = stat($filename) or die "stat: $!";

is($stat_pre[1], $stat_pst[1], 'same inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";

@stat_pst = stat("$filename.save") or die "stat: $!";
unlink("$filename.save") or die "unlink: $!";
is($stat_pre[1], $stat_pst[1], 'same inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";

@stat_pst = stat("$filename.new") or die "stat: $!";
unlink("$filename.new") or die "unlink: $!";
isnt($stat_pre[1], $stat_pst[1], 'different inode');
stat_compare(\@stat_pre, \@stat_pst) or print STDERR explain \@stat_pst, "\n";

}



#print STDERR Dumper { pre => \@stat_pre, pst => \@stat_pst };

done_testing();

