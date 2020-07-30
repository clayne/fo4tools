#!/usr/bin/perl

use Scalar::Util qw(weaken);
use File::Basename qw(basename dirname);
use File::Spec qw(join);
use File::Temp qw(tempfile tempdir);
use Test::Differences;
use Test::More;
use Test::Deep;
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Carp qw(cluck confess);
use Sereal::Encoder qw(encode_sereal SRL_SNAPPY);
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

unified_diff;

# test all plugins in data directory
my $plugin_dir = 't/data';
my $res_dir = File::Spec->join(dirname($0), 'res');
my $test_file = basename($0);

sub md5sum {
	open(my $fd, '<', $_[0]) or die "open: $!";

	my $ctx = Digest::MD5->new;
	$ctx->addfile($fd);
	my $digest = $ctx->hexdigest;

	close($fd) or die "close: $!";

	return $digest;
}

sub out_get {
	my ($plugin_base, $test, $res) = @_;

	my $test_key = md5_hex(encode_sereal([ $plugin_base, $test ], { canonical => 1 }));
	my $res_file = File::Spec->join($res_dir, join('.', $test_file, $test_key, 'res'));
	my $regen = ($ENV{'TEST_REGEN'} || ($ENV{'TEST_REGEN_UPDATE'} && -f $res_file));

	if ($regen) {
		my $encoder = Sereal::Encoder->new({ compress => SRL_SNAPPY, dedupe_strings => 1 });
		$encoder->encode_to_file($res_file, $res);
	}

	return -f $res_file ? Sereal::Decoder->decode_from_file($res_file) : 'NO RES';
}

opendir(my $dh, $plugin_dir) || die "opendir: $!";
my @plugins = grep /\.es[pml]$/, readdir($dh);
closedir $dh or die "closedir: $!";

foreach my $plugin (@plugins) {
	my $filename = File::Spec->join($plugin_dir, $plugin);
	my ($plugin_base, $plugin_ext) = ($plugin =~ /^(.+)\.(es[pml])$/) or die;

# read
{
	my $test = 'read';
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	my $out = out_get($plugin_base, $test, $ret);

	eq_or_diff($ret, $out, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read (no field_parse)
{
	my $test = 'read-no-field-parse';
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 0,
	);

	my $out = out_get($plugin_base, $test, $ret);

	eq_or_diff($ret, $out, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read (no record_parse, no field_parse)
{
	my $test = 'read-no-record-field-parse';
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 1,
		record_parse => 0,
		field_parse => 0,
	);

	my $out = out_get($plugin_base, $test, $ret);

	eq_or_diff($ret, $out, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read (no data_parse, no record_parse, no field_parse)
{
	my $test = 'read-no-data-record-field-parse';
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 0,
		record_parse => 0,
		field_parse => 0,
	);

	my $out = out_get($plugin_base, $test, $ret);

	eq_or_diff($ret, $out, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read (data_skip)
{
	my $test = 'read-data-skip';
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 1,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	my $out = out_get($plugin_base, $test, $ret);

	eq_or_diff($ret, $out, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read/write/read
{
	my $test = 'read-write-read';
	my $ref = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	my ($fd, $filename2) = tempfile(UNLINK => 1, SUFFIX => ".$plugin_ext");
	$ref->write($fd,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);
	close($fd);

	my $digest_cur = md5sum($filename);
	my $digest_new = md5sum($filename2);

	eq_or_diff($digest_new, $digest_cur, "$plugin: $test: checksum") or print STDERR explain $digest_new, "\n";

	my $ret = TES::Plugin::File->read($filename2,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	# These keys will legitimately differ.
	foreach my $plugin ($ref, $ret) {
		foreach (qw(plugin_base plugin_dir plugin_path plugin_file)) {
			delete $plugin->{$_};
		}
	}

	eq_or_diff($ret, $ref, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read/write/read (fd only)
{
	my $test = 'read-write-read-fd';
	open(my $fd, '<', $filename) or die "open: $filename: $!";
	my $ref = TES::Plugin::File->read($fd,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	my ($fd2, $filename2) = tempfile(UNLINK => 1, SUFFIX => ".$plugin_ext");
	$ref->write($fd2,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);
	close($fd2);

	my $digest_cur = md5sum($filename);
	my $digest_new = md5sum($filename2);

	eq_or_diff($digest_new, $digest_cur, "$plugin: $test: checksum") or print STDERR explain $digest_new, "\n";

	open($fd2, '<', $filename2) or die "open: $filename2: $!";
	my $ret = TES::Plugin::File->read($fd2,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	# These keys will legitimately differ.
	foreach my $plugin ($ref, $ret) {
		foreach (qw(plugin_base plugin_dir plugin_path plugin_file)) {
			delete $plugin->{$_};
		}
	}

	eq_or_diff($ret, $ref, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read/write/read (filename only)
{
	my $test = 'read-write-read-filename';
	my $ref = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	my (undef, $filename2) = tempfile(UNLINK => 1, SUFFIX => ".$plugin_ext");
	$ref->write($filename2,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	my $digest_cur = md5sum($filename);
	my $digest_new = md5sum($filename2);

	eq_or_diff($digest_new, $digest_cur, "$plugin: $test: checksum") or print STDERR explain $digest_new, "\n";

	my $ret = TES::Plugin::File->read($filename2,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	# These keys will legitimately differ.
	foreach my $plugin ($ref, $ret) {
		foreach (qw(plugin_base plugin_dir plugin_path plugin_file)) {
			delete $plugin->{$_};
		}
	}

	eq_or_diff($ret, $ref, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read/rewrite
{
	my $test = 'read-rewrite';
	my $ret = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	$ret->rewrite(
		header_rewrite => {
			sub_ext => [ [ 'esm', 'esl' ] ],
		},
	);

	my $out = out_get($plugin_base, $test, $ret);

	eq_or_diff($ret, $out, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read/rewrite/write/read (header)
{
	my $test = 'read-rewrite-header-write-read';
	my ($fd, $filename2) = tempfile(UNLINK => 1, SUFFIX => ".$plugin_ext");

	my $ref = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	$ref->rewrite(
		header_rewrite => {
			sub_ext => [ [ 'esm', 'esl' ] ],
		}
	);

	$ref->write($fd,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	close($fd);

	my $sum_tab = {
		parent0 => 'de3de04dec1c6fc4f71fb914f3229da1',
		parent1 => '9757f94f981099549c85bb2e872ba0d0',
		parent2 => '5b803b319283bde7b8f9bb987f1c2846',
		parent3 => 'b5a61a3fdda3d477496b48fcc5c13a5a',
		parent4 => '36eef681b8ae5287d5e0ecc4fdcc20bb',
		xxxx => 'fd2c58f88805b481372020c2f2a49592',
		empty => '2ee672ab922f3aba7c2ff19b65c0ffa7',
		compressed => '450b60bd1680fa79e268346ec2ddcfd7',
		cell_compressed_xxxx => 'c5261582de2420bbbf252e2f684808bc',
		plugin => 'f7c9f628139e8fdca1dbff1566022f49',
		'plugin with spaces' => '05cc50745fb31be21327237fb35c3199',
		'master with spaces' => 'b9898aaede477d266a1b0ecd9ecdb10c',
	};
	my $digest_cur = $sum_tab->{$plugin_base};
	my $digest_new = md5sum($filename2);

	eq_or_diff($digest_new, $digest_cur, "$plugin: $test: checksum") or print STDERR explain $digest_new, "\n";

	my $ret = TES::Plugin::File->read($filename2,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	# These keys will legitimately differ.
	foreach my $plugin ($ret) {
		foreach (qw(plugin_base plugin_dir plugin_path plugin_file)) {
			delete $plugin->{$_};
		}
	}

	my $out = out_get($plugin_base, $test, $ret);

	eq_or_diff($ret, $out, "$plugin: $test") or print STDERR explain $ret, "\n";
}

# read/rewrite/write/read (all)
{
	my $test = 'read-rewrite-all-write-read';
	my ($fd, $filename2) = tempfile(UNLINK => 1, SUFFIX => ".$plugin_ext");

	my $ref = TES::Plugin::File->read($filename,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	$ref->rewrite(
		sub => [ qr/[^A-Za-z0-9_.-\/\\]/, '_' ],
		sub_ext => [ [ 'esp', 'esm' ], [ 'esm', 'esl' ] ],
	);

	$ref->write($fd,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	close($fd);

	my $sum_tab = {
		parent0 => '140a279aec2e08a36e91a9e7e17a185b',
		parent1 => '8566dacbb01209772669ee76f85f9b9e',
		parent2 => 'de4f6a68f4f6126b8ce4affa0b7eea8b',
		parent3 => '7ef382fa3cb41f9fb5b599e78d97b35b',
		parent4 => 'ad8beec1674a1d2e145c084060d0052a',
		xxxx => 'fd2c58f88805b481372020c2f2a49592',
		empty => '2ee672ab922f3aba7c2ff19b65c0ffa7',
		compressed => 'f1e4fe79248607cf292a8d1ef971ca47',
		cell_compressed_xxxx => 'c5261582de2420bbbf252e2f684808bc',
		plugin => '691ab779e9d29c02d5e49ba13adad42d',
		'plugin with spaces' => 'fec479b162e6b4e21684e4383691901a',
		'master with spaces' => 'aa651b9d9933f82dd2fdf98ae451e23a',
	};
	my $digest_cur = $sum_tab->{$plugin_base};
	my $digest_new = md5sum($filename2);

	eq_or_diff($digest_new, $digest_cur, "$plugin: $test: checksum") or print STDERR explain $digest_new, "\n";

	my $ret = TES::Plugin::File->read($filename2,
		data_skip => 0,
		data_parse => 1,
		record_parse => 1,
		field_parse => 1,
	);

	# These keys will legitimately differ.
	foreach my $plugin ($ret) {
		foreach (qw(plugin_base plugin_dir plugin_path plugin_file)) {
			delete $plugin->{$_};
		}
	}

	my $out = out_get($plugin_base, $test, $ret);

	eq_or_diff($ret, $out, "$plugin: $test") or print STDERR explain $ret, "\n";
}

}

done_testing();
