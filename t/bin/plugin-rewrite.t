#!/usr/bin/perl

use File::Spec qw(join);
use File::Temp qw(tempfile tempdir);
use File::Copy qw(cp);
use File::Basename qw(dirname basename);
use File::stat qw(stat);
use File::chdir;
use List::Util qw(uniq);
use Test::Differences;
use Test::More;
use Test::Deep;
use Test::Output;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Carp qw(cluck confess);
use Sereal::Encoder qw(encode_sereal SRL_SNAPPY);
use Sereal::Decoder qw();

use strict;
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;
sub fatal { local $SIG{__DIE__}; die @_, "\n" }

local $Data::Dumper::Deepcopy = 1;
local $Data::Dumper::Sortkeys = 1;

use lib '.';

package ba2dump;
require 'bin/ba2dump';
*main::ba2dump = \&ba2dump::main;;

package main;
require 'bin/plugin-rewrite';

my $data_dir = 't/data';
my $res_dir = File::Spec->join(dirname($0), 'res');
my $test_file = basename($0);

my @plugins = grep /\.es[pml]/, dir_ls($data_dir);
my @archives = grep /\.ba2/, dir_ls($data_dir);

sub md5sum {
	open(my $fd, '<', $_[0]) or die "open: $!";

	my $ctx = Digest::MD5->new;
	$ctx->addfile($fd);
	my $digest = $ctx->hexdigest;

	close($fd) or die "close: $!";

	return $digest;
}

sub dir_ls {
	my $src = shift;

	opendir(my $dh, $src) || die "opendir: $!";
	my @files = grep /\.(?:ba2|es[pml])/, readdir($dh);
	closedir $dh or die "closedir: $!";

	# XXX: filter out fake vanilla files
	@files = grep !/^(?:DLC.*|Fallout4)\.esm$/, @files;

	return sort @files;
}

sub dir_cmp {
	my ($src, $dst) = @_;

	my $src_dir = ref $src ne 'HASH' ? $src : undef;
	my $dst_dir = ref $dst ne 'HASH' ? $dst : undef;
	my $src_tab = ref $src eq 'HASH' ? $src : {};
	my $dst_tab = ref $dst eq 'HASH' ? $dst : {};

	foreach (
		[ $src_tab, $src_dir ],
		[ $dst_tab, $dst_dir ],
	) {
		my ($tab, $dir) = @$_;
		next unless ($dir);

		opendir(my $dh, $dir) || die "opendir: $!";
		my @files = grep /\.(?:ba2|es[pml])/, readdir($dh);
		closedir $dh or die "closedir: $!";

		# XXX: filter out fake vanilla files
		@files = grep !/^(?:DLC.*|Fallout4)\.esm$/, @files;
		foreach (@files) {
			$tab->{$_} = {
				mtime => stat($_)->mtime,
				inode => stat($_)->ino,
				size => stat($_)->size,
				sum => md5sum($_),
			};
		}
	}

	if (!$src || !$dst) {
		return ($src_tab, $dst_tab);
	}

	my (@out, %out);
	foreach (sort { $a cmp $b } uniq (keys %$src_tab, keys %$dst_tab)) {
		if (!exists $src_tab->{$_}) {
			push @{$out{'add'}}, $_;
		} elsif (!exists $dst_tab->{$_}) {
			push @{$out{'rem'}}, $_;
		} else {
			my @changed;
			foreach my $key (qw(mtime inode size sum)) {
				push @changed, $key if ($src_tab->{$_}{$key} ne $dst_tab->{$_}{$key});
			}
			push @{$out{'chg'}}, [ $_, sort @changed ] if (@changed);
		}
	}

	return \%out;
}

sub plugin_rewrite_test {
	my ($plugin, %opts) = @_;
	my $args = $opts{'args'};
	my $plugin_match = $opts{'plugin_match'};
	my $archives_all = $opts{'archives_all'};
	my $plugins = $opts{'plugins'} // 1;
	my $archives = $opts{'archives'} // 1;
	return if (defined $plugin_match && $plugin !~ /$plugin_match/);

	my $basename = basename($plugin);
	my ($plugin_base, $plugin_ext) = ($basename =~ /^(.+)\.(es[pml])$/);

	my $dir = temp_dir_prepare($data_dir);
	local $CWD = $dir;

	my @plugin_res;

	my ($cmp_res_pre) = dir_cmp($dir);
	if ($plugins) {
		if (ref $args->[0] ne 'ARRAY') {
			$args = [ $args ];
		}
		foreach my $args (@$args) {
			push @plugin_res, combined_from(sub { main($plugin, @$args) });
		}
	}
	my $cmp_res = dir_cmp($cmp_res_pre, $dir);

	if ($archives) {
		my @archives;
		if ($archives_all) {
			my $archive_match = $archives_all ? qr// : ($plugin_base =~ s/\s+/\./gr);
			@archives = grep /^$archive_match - \w+\.ba2/, dir_ls($dir);
		} elsif (scalar keys %$cmp_res) {
			@archives = grep /\.ba2/,
				map +(ref ? $_->[0] : $_),
				map @{$cmp_res->{$_}}, grep exists $cmp_res->{$_}, qw(chg add);
		}
		push @plugin_res, combined_from(sub { ba2dump('-vl', @archives) } );
	}

	if (scalar keys %$cmp_res) {
		my @out;
		foreach (@{$cmp_res->{'rem'}}) {
			push @out, sprintf("Removed: %s", $_);
		}
		foreach (@{$cmp_res->{'chg'}}) {
			my ($file, @changed) = @$_;
			push @out, sprintf("Changed: %s (%s)", $file, join(', ', sort @changed));
		}
		foreach (@{$cmp_res->{'add'}}) {
			push @out, sprintf("Added: %s", $_);
		}
		push @plugin_res, join('', map sprintf("%s\n", $_), @out);
	}

	return join("-" x 16 . "\n", grep +(defined && $_ ne ''), @plugin_res);
}

sub rewrite_test {
	my ($plugins, %opts) = @_;

	my @res = map { plugin_rewrite_test($_, %opts) } (@$plugins);
	my $res = join("=" x 32 . "\n", @res);
	my $args = ref $opts{'args'}->[0] ne 'ARRAY' ? [ $opts{'args'} ] : $opts{'args'};
	my $name = sprintf("%s (%s)",
		join(', ', map join(' ', @$_), @$args),
		join(':',(caller(0))[1,2])
	);

	my $test_key = md5_hex(encode_sereal([ $plugins, \%opts ], { canonical => 1 }));
	my $res_file = File::Spec->join($res_dir, join('.', $test_file, $test_key, 'res'));
	my $regen = ($ENV{'TEST_REGEN'} || ($ENV{'TEST_REGEN_UPDATE'} && -f $res_file));

	if ($regen) {
		my $encoder = Sereal::Encoder->new({ compress => SRL_SNAPPY, dedupe_strings => 1 });
		$encoder->encode_to_file($res_file, $res);
	}

	my $out = -f $res_file ? Sereal::Decoder->decode_from_file($res_file) : 'NO RES';
	eq_or_diff($res, $out, $name, { context => 10 }) or print STDERR explain $res, "\n";
}

sub temp_dir_prepare {
	my $src = shift;
	my $dst = tempdir(CLEANUP => 1);

	opendir(my $dh, $src) || die "opendir: $!";
	my @files = grep /\.(?:ba2|es[pml])/, readdir($dh);
	closedir $dh or die "closedir: $!";

	foreach my $file (@files) {
		my $filename_src = File::Spec->join($src, $file);
		my $filename_dst = File::Spec->join($dst, $file);
		cp($filename_src, $filename_dst) or die "cp: $file";
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

	return $dst;
}

# noop
{
	rewrite_test(\@plugins,
		args => [ qw() ],
	);
}

# noop -q
{
	rewrite_test(\@plugins,
		args => [ qw(-q) ],
	);
}

# noop -q -r
{
	rewrite_test(\@plugins,
		args => [ qw(-q -r) ],
	);
}

# noop -q -r --include-self
{
	rewrite_test(\@plugins,
		args => [ qw(-q -r --include-self) ],
	);
}

# noop -v
{
	rewrite_test(\@plugins,
		args => [ qw(-v) ],
	);
}

# noop -v --include-self
{
	rewrite_test(\@plugins,
		args => [ qw(-v --include-self) ],
	);
}

# --esp-to-esm -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm -v) ],
	);
}

# --esm-to-esp -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp -v) ],
	);
}

# --esp-to-esm --archives -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --archives -v) ],
	);
}

# --esm-to-esp --archives -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --archives -v) ],
	);
}

# --esp-to-esm --archives -r -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --archives -r -v) ],
	);
}

# --esm-to-esp --archives -r -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --archives -r -v) ],
	);
}

# --esp-to-esm --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --archives -r -v) ],
		plugin_match => 'plugin.esp',
	);
}

# --esm-to-esp --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --archives -r -v) ],
		plugin_match => 'plugin.esp',
	);
}

# --esp-to-esm --archives -v
# --esm-to-esp --archives -v
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --archives -v) ],
			[ qw(--esm-to-esp --archives -v) ],
		],
	);
}

# --esp-to-esm --archives -r -v
# --esm-to-esp --archives -r -v
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --archives -r -v) ],
			[ qw(--esm-to-esp --archives -r -v) ],
		],
	);
}

# --esp-to-esm --archives -r -v (single plugin only)
# --esm-to-esp --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --archives -r -v) ],
			[ qw(--esm-to-esp --archives -r -v) ],
		],
		plugin_match => 'plugin.esp',
	);
}

# --esp-to-esm --sanitize --archives -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize --archives -v) ],
	);
}

# --esm-to-esp --sanitize --archives -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize --archives -v) ],
	);
}

# --esp-to-esm --sanitize --archives -r -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize --archives -r -v) ],
	);
}

# --esm-to-esp --sanitize --archives -r -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize --archives -r -v) ],
	);
}

# --esp-to-esm --sanitize --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize --archives -r -v) ],
		plugin_match => 'plugin.esp',
	);
}

# --esm-to-esp --sanitize --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize --archives -r -v) ],
		plugin_match => 'plugin.esp',
	);
}

# --esp-to-esm --sanitize --archives -v
# --esm-to-esp --sanitize --archives -v
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize --archives -v) ],
			[ qw(--esm-to-esp --sanitize --archives -v) ],
		],
	);
}

# --esp-to-esm --sanitize --archives -r -v
# --esm-to-esp --sanitize --archives -r -v
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize --archives -r -v) ],
			[ qw(--esm-to-esp --sanitize --archives -r -v) ],
		],
	);
}

# --esp-to-esm --sanitize --archives -r -v (single plugin only)
# --esm-to-esp --sanitize --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize --archives -r -v) ],
			[ qw(--esm-to-esp --sanitize --archives -r -v) ],
		],
		plugin_match => 'plugin.esp',
	);
}

# --esp-to-esm --sanitize-self --archives -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize-self --archives -v) ],
	);
}

# --esm-to-esp --sanitize-self --archives -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize-self --archives -v) ],
	);
}

# --esp-to-esm --sanitize-self --archives -r -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize-self --archives -r -v) ],
	);
}

# --esm-to-esp --sanitize-self --archives -r -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize-self --archives -r -v) ],
	);
}

# --esp-to-esm --sanitize-self --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize-self --archives -r -v) ],
		plugin_match => 'plugin.esp',
	);
}

# --esm-to-esp --sanitize-self --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize-self --archives -r -v) ],
		plugin_match => 'plugin.esp',
	);
}

# --esp-to-esm --sanitize-self --archives -v
# --esm-to-esp --sanitize-self --archives -v
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize-self --archives -v) ],
			[ qw(--esm-to-esp --sanitize-self --archives -v) ],
		],
	);
}

# --esp-to-esm --sanitize-self --archives -r -v
# --esm-to-esp --sanitize-self --archives -r -v
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize-self --archives -r -v) ],
			[ qw(--esm-to-esp --sanitize-self --archives -r -v) ],
		],
	);
}

# --esp-to-esm --sanitize-self --archives -r -v (single plugin only)
# --esm-to-esp --sanitize-self --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize-self --archives -r -v) ],
			[ qw(--esm-to-esp --sanitize-self --archives -r -v) ],
		],
		plugin_match => 'plugin.esp',
	);
}

# --esp-to-esm --sanitize-parents --archives -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize-parents --archives -v) ],
	);
}

# --esm-to-esp --sanitize-parents --archives -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize-parents --archives -v) ],
	);
}

# --esp-to-esm --sanitize-parents --archives -r -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize-parents --archives -r -v) ],
	);
}

# --esm-to-esp --sanitize-parents --archives -r -v
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize-parents --archives -r -v) ],
	);
}

# --esp-to-esm --sanitize-parents --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [ qw(--esp-to-esm --sanitize-parents --archives -r -v) ],
		plugin_match => 'plugin.esp',
	);
}

# --esm-to-esp --sanitize-parents --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [ qw(--esm-to-esp --sanitize-parents --archives -r -v) ],
		plugin_match => 'plugin.esp',
	);
}

# --esp-to-esm --sanitize-parents --archives -v
# --esm-to-esp --sanitize-parents --archives -v
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize-parents --archives -v) ],
			[ qw(--esm-to-esp --sanitize-parents --archives -v) ],
		],
	);
}

# --esp-to-esm --sanitize-parents --archives -r -v
# --esm-to-esp --sanitize-parents --archives -r -v
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize-parents --archives -r -v) ],
			[ qw(--esm-to-esp --sanitize-parents --archives -r -v) ],
		],
	);
}

# --esp-to-esm --sanitize-parents --archives -r -v (single plugin only)
# --esm-to-esp --sanitize-parents --archives -r -v (single plugin only)
{
	rewrite_test(\@plugins,
		args => [
			[ qw(--esp-to-esm --sanitize-parents --archives -r -v) ],
			[ qw(--esm-to-esp --sanitize-parents --archives -r -v) ],
		],
		plugin_match => 'plugin.esp',
	);
}

done_testing();
