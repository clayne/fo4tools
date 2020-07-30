#!/usr/bin/perl

use File::Spec qw(join);
use File::Temp qw(tempfile tempdir);
use Test::Differences;
use Test::More;
use Test::Deep;
use Data::Dumper;
use Digest::MD5 qw();
use Carp qw(cluck confess);

use strict;
use autodie qw(:all);
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;

local $Data::Dumper::Deepcopy = 1;
local $Data::Dumper::Sortkeys = 1;

use TES::Plugin::Archive::BA2 qw();

sub ba2_gnrl_gen {
	my $offset = 0;
	my $ba2 = TES::Plugin::Archive::BA2->new(
		signature => 'BTDX',
		version => 0x1,
		type => 'GNRL',
		file_count => 4,
	);

	$offset += $ba2->header_size;

	for (my $i = 0; $i < $ba2->{'file_count'}; $i++) {
		my $name = $i
			 ? File::Spec->join($i, join('.', $i, 'dir'), join('.', 'archive test', $i, 'test'))
			 : File::Spec->join('Strings', join('_', 'archive test', 'strings'));

		my $ent = $ba2->ent_class->new(
			name => $name,
			flags => 0x0,
			offset => $offset,
			size_packed => 8,
			size => 8,
			check => 0xbaadf00d,
		);
		$ba2->ent_push($ent);
		$offset += $ent->header_size;
	}

	$ba2->{'data'} = 'DATA';
	$ba2->{'data_offset'} = $offset;
	$ba2->{'data_size'} = length($ba2->{'data'});
	$offset += $ba2->{'data_size'};

	$ba2->{'name_table_offset'} = $offset;

	for (my $i = 0; $i < $ba2->{'file_count'}; $i++) {
		my $ent = $ba2->{'ents'}[$i] || die;

		# S/a
		$offset += 2 + length($ent->{'name'});
	}

	$ba2->{'file_size'} = $offset;
	$ba2->{'name_table_size'} = $ba2->{'file_size'} - $ba2->{'name_table_offset'};

	return $ba2;
}

sub ba2_dx10_gen {
	my $offset = 0;
	my $ba2 = TES::Plugin::Archive::BA2->new(
		signature => 'BTDX',
		version => 0x1,
		type => 'DX10',
		file_count => 4,
	);

	$offset += $ba2->header_size;

	for (my $i = 0; $i < $ba2->{'file_count'}; $i++) {
		my $name = File::Spec->join($i, join('.', $i, 'dir'), join('.', 'archive test', $i, 'dds'));

		my $ent = $ba2->ent_class->new(
			name => $name,
			flags => 0x0,
			chunk_count => 2,
			chunk_header_size => 24,
			height => 1024,
			width => 1024,
			mip_count => 1,
			dxgi_format => 0,
			cubemaps => 0,
			size => 512,
			size_packed => 512,
		);
		$ba2->ent_push($ent);
		$offset += $ent->header_size;

		for (my $j = 0; $j < $ent->{'chunk_count'}; $j++) {
			my $chunk = $ent->chunk_class->new(
				offset => $offset,
				size_packed => 256,
				size => 256,
				mip_start => 0,
				mip_end => 0,
				check => 0xbaadf00d,
			);
			$ent->chunk_push($chunk);
			$offset += $chunk->header_size;
		}
	}

	$ba2->{'data'} = 'DATA';
	$ba2->{'data_offset'} = $offset;
	$ba2->{'data_size'} = length($ba2->{'data'});
	$offset += $ba2->{'data_size'};

	$ba2->{'name_table_offset'} = $offset;

	for (my $i = 0; $i < $ba2->{'file_count'}; $i++) {
		my $ent = $ba2->{'ents'}[$i] || die;

		# S/a
		$offset += 2 + length($ent->{'name'});
	}

	$ba2->{'file_size'} = $offset;
	$ba2->{'name_table_size'} = $ba2->{'file_size'} - $ba2->{'name_table_offset'};

	return $ba2;
}

# write (GNRL)
{
	my $fd = tempfile(UNLINK => 1, SUFFIX => ' - Main.ba2');
	my $ba2 = ba2_gnrl_gen;
	$ba2->write($fd);

	seek($fd, 0, 0);

	my $ctx = Digest::MD5->new;
	$ctx->addfile($fd);
	my $digest = $ctx->hexdigest;

	eq_or_diff($digest, 'eaf92186f86ab7f48dd3b06567a05162');
}

# write then read (GNRL)
{
	my ($fd, $filename) = tempfile(UNLINK => 1, SUFFIX => ' - Main.ba2');
	my $ba2 = ba2_gnrl_gen;
	$ba2->write($filename);

	my $out = $ba2;
	my $ret = TES::Plugin::Archive::BA2->read($filename);

	eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# write (DX10)
{
	my $fd = tempfile(UNLINK => 1, SUFFIX => ' - Textures.ba2');
	my $ba2 = ba2_dx10_gen;
	$ba2->write($fd);

	seek($fd, 0, 0);

	my $ctx = Digest::MD5->new;
	$ctx->addfile($fd);
	my $digest = $ctx->hexdigest;

	eq_or_diff($digest, 'a2d0ff4f7519a694ad5f791abd8600f7');
}

# write then read (DX10)
{
	my ($fd, $filename) = tempfile(UNLINK => 1, SUFFIX => ' - Textures.ba2');
	my $ba2 = ba2_dx10_gen;
	$ba2->write($filename);

	my $out = $ba2;
	my $ret = TES::Plugin::Archive::BA2->read($filename);

	eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# write then read then rewrite (GNRL)
{
	my ($fd, $filename) = tempfile(UNLINK => 1, SUFFIX => ' - Main.ba2');
	my $ba2 = ba2_gnrl_gen;
	$ba2->write($filename);

	my $archive_base = 'archive test';
	$ba2 = TES::Plugin::Archive::BA2->read($filename);
	$ba2->rewrite(
		archive_base => $archive_base,
		archive_type => 'Main',
		match_string => qr/(\Q$archive_base\E)[_\b].+/i,
		match_file => qr/(\Q$archive_base\E)[_.\b].+/i,
		match_dir => qr/([\d.\w]+)/,
		sub => [ [ qr/[^A-Za-z014-9_.\/-]/, '_' ] ],
		sub_file => [ [ qr/\s+/, '-' ] ],
		sub_dir_ext => [ [ 'dir', 'DIR' ] ],
	);

	my $out = bless( {
	  'data' => 'DATA',
	  'data_offset' => 168,
	  'data_size' => 4,
	  'ents' => [
	    bless( {
	      'check' => 3131961357,
	      'dir_hash' => 704034187,
	      'extension' => '',
	      'flags' => 0,
	      'name' => 'Strings/archive_test_strings',
	      'name_hash' => 733452139,
	      'offset' => 24,
	      'size' => 8,
	      'size_packed' => 8
	    }, 'TES::Plugin::Archive::BA2::Ent::GNRL' ),
	    bless( {
	      'check' => 3131961357,
	      'dir_hash' => 3961424979,
	      'extension' => 'test',
	      'flags' => 0,
	      'name' => '1/1.DIR/archive-test.1.test',
	      'name_hash' => 1463909489,
	      'offset' => 60,
	      'size' => 8,
	      'size_packed' => 8
	    }, 'TES::Plugin::Archive::BA2::Ent::GNRL' ),
	    bless( {
	      'check' => 3131961357,
	      'dir_hash' => 295006919,
	      'extension' => 'test',
	      'flags' => 0,
	      'name' => '_/_.DIR/archive-test.2.test',
	      'name_hash' => 3460836811,
	      'offset' => 96,
	      'size' => 8,
	      'size_packed' => 8
	    }, 'TES::Plugin::Archive::BA2::Ent::GNRL' ),
	    bless( {
	      'check' => 3131961357,
	      'dir_hash' => 295006919,
	      'extension' => 'test',
	      'flags' => 0,
	      'name' => '_/_.DIR/archive-test.3.test',
	      'name_hash' => 3108969821,
	      'offset' => 132,
	      'size' => 8,
	      'size_packed' => 8
	    }, 'TES::Plugin::Archive::BA2::Ent::GNRL' )
	  ],
	  'file_count' => 4,
	  'file_size' => 289,
	  'name_table_offset' => 172,
	  'name_table_size' => 117,
	  'signature' => 'BTDX',
	  'type' => 'GNRL',
	  'version' => 1
	}, 'TES::Plugin::Archive::BA2' );

	my $ret = $ba2;

	eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# read (GNRL, Archive2 generated)
{
	my $out = bless( {
	  'data_offset' => 96,
	  'data_size' => 381,
	  'ents' => [
	    bless( {
	      'check' => 3131961357,
	      'dir_hash' => 68382556,
	      'extension' => 'bgsm',
	      'flags' => 1048832,
	      'name' => 'Materials/SetDressing/PaintingsGeneric/PaintingAbstract22.BGSM',
	      'name_hash' => 2135543055,
	      'offset' => 96,
	      'size' => 376,
	      'size_packed' => 189
	    }, 'TES::Plugin::Archive::BA2::Ent::GNRL' ),
	    bless( {
	      'check' => 3131961357,
	      'dir_hash' => 3772879399,
	      'extension' => 'bgsm',
	      'flags' => 1048832,
	      'name' => 'Materials/Weapons/RocketHammer/RocketHammer.BGSM',
	      'name_hash' => 10530029,
	      'offset' => 285,
	      'size' => 433,
	      'size_packed' => 192
	    }, 'TES::Plugin::Archive::BA2::Ent::GNRL' )
	  ],
	  'file_count' => 2,
	  'file_size' => 591,
	  'name_table_offset' => 477,
	  'name_table_size' => 114,
	  'signature' => 'BTDX',
	  'type' => 'GNRL',
	  'version' => 1
	}, 'TES::Plugin::Archive::BA2' );

	my $filename = 't/data/Test - Main.ba2';
	my $ret = TES::Plugin::Archive::BA2->read($filename, data_skip => 1);

	eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# read then write (GNRL, Archive2 generated)
{
	my $filename = 't/data/Test - Main.ba2';
	my $fd = tempfile(UNLINK => 1, SUFFIX => ' - Main.ba2');

	my $ba2 = TES::Plugin::Archive::BA2->read($filename);
	$ba2->write($fd);

	seek($fd, 0, 0);

	my $ctx = Digest::MD5->new;
	$ctx->addfile($fd);
	my $digest = $ctx->hexdigest;

	eq_or_diff($digest, '36db979fd8fe3af91b5bd5602d3260d2');
}

# read then write (GNRL, data skip, Archive2 generated)
{
	my $filename = 't/data/Test - Main.ba2';
	my $fd = tempfile(UNLINK => 1, SUFFIX => ' - Main.ba2');

	my $ba2 = TES::Plugin::Archive::BA2->read($filename, data_skip => 1);
	$ba2->write($fd, data_skip => 1);

	seek($fd, 0, 0);

	my $ctx = Digest::MD5->new;
	$ctx->addfile($fd);
	my $digest = $ctx->hexdigest;

	eq_or_diff($digest, '5ecc1e94f0ab4e939246c711ddd0ce62');
}

# read (DX10, Archive2 generated)
{
	my $out = bless( {
	  'data_offset' => 216,
	  'data_size' => 10773,
	  'ents' => [
	    bless( {
	      'chunk_count' => 1,
	      'chunk_header_size' => 24,
	      'chunks' => [
		bless( {
		  'check' => 3131961357,
		  'mip_end' => 7,
		  'mip_start' => 0,
		  'offset' => 216,
		  'size' => 10936,
		  'size_packed' => 4439
		}, 'TES::Plugin::Archive::BA2::Ent::DX10::Chunk' )
	      ],
	      'cubemaps' => 2048,
	      'dir_hash' => 2157666528,
	      'dxgi_format' => 71,
	      'extension' => 'dds',
	      'flags' => 0,
	      'height' => 128,
	      'mip_count' => 8,
	      'name' => 'Textures/Actors/FeralGhoulEye_d.DDS',
	      'name_hash' => 956553527,
	      'size' => 10936,
	      'size_packed' => 4439,
	      'width' => 128
	    }, 'TES::Plugin::Archive::BA2::Ent::DX10' ),
	    bless( {
	      'chunk_count' => 1,
	      'chunk_header_size' => 24,
	      'chunks' => [
		bless( {
		  'check' => 3131961357,
		  'mip_end' => 0,
		  'mip_start' => 0,
		  'offset' => 4655,
		  'size' => 4096,
		  'size_packed' => 2486
		}, 'TES::Plugin::Archive::BA2::Ent::DX10::Chunk' )
	      ],
	      'cubemaps' => 2048,
	      'dir_hash' => 3929839416,
	      'dxgi_format' => 87,
	      'extension' => 'dds',
	      'flags' => 0,
	      'height' => 32,
	      'mip_count' => 1,
	      'name' => 'Textures/Effects/WepLaserRedRingGrad.dds',
	      'name_hash' => 3279245156,
	      'size' => 4096,
	      'size_packed' => 2486,
	      'width' => 32
	    }, 'TES::Plugin::Archive::BA2::Ent::DX10' ),
	    bless( {
	      'chunk_count' => 1,
	      'chunk_header_size' => 24,
	      'chunks' => [
		bless( {
		  'check' => 3131961357,
		  'mip_end' => 5,
		  'mip_start' => 0,
		  'offset' => 7141,
		  'size' => 1392,
		  'size_packed' => 28
		}, 'TES::Plugin::Archive::BA2::Ent::DX10::Chunk' )
	      ],
	      'cubemaps' => 2048,
	      'dir_hash' => 1336840355,
	      'dxgi_format' => 77,
	      'extension' => 'dds',
	      'flags' => 0,
	      'height' => 32,
	      'mip_count' => 6,
	      'name' => 'Textures/Sky/SkyrimCloudsFill.DDS',
	      'name_hash' => 339929657,
	      'size' => 1392,
	      'size_packed' => 28,
	      'width' => 32
	    }, 'TES::Plugin::Archive::BA2::Ent::DX10' ),
	    bless( {
	      'chunk_count' => 1,
	      'chunk_header_size' => 24,
	      'chunks' => [
		bless( {
		  'check' => 3131961357,
		  'mip_end' => 8,
		  'mip_start' => 0,
		  'offset' => 7169,
		  'size' => 11024,
		  'size_packed' => 3820
		}, 'TES::Plugin::Archive::BA2::Ent::DX10::Chunk' )
	      ],
	      'cubemaps' => 2048,
	      'dir_hash' => 3547284404,
	      'dxgi_format' => 77,
	      'extension' => 'dds',
	      'flags' => 0,
	      'height' => 256,
	      'mip_count' => 9,
	      'name' => 'Textures/Vehicles/Rust01LGrad_d.DDS',
	      'name_hash' => 4164419734,
	      'size' => 11024,
	      'size_packed' => 3820,
	      'width' => 32
	    }, 'TES::Plugin::Archive::BA2::Ent::DX10' )
	  ],
	  'file_count' => 4,
	  'file_size' => 11140,
	  'name_table_offset' => 10989,
	  'name_table_size' => 151,
	  'signature' => 'BTDX',
	  'type' => 'DX10',
	  'version' => 1
	}, 'TES::Plugin::Archive::BA2' );

	my $filename = 't/data/Test - Textures.ba2';
	my $ret = TES::Plugin::Archive::BA2->read($filename, data_skip => 1);

	eq_or_diff($ret, $out) or print STDERR explain $ret, "\n";
}

# read then write (DX10, Archive2 generated)
{
	my $filename = 't/data/Test - Textures.ba2';
	my $fd = tempfile(UNLINK => 1, SUFFIX => ' - Textures.ba2');

	my $ba2 = TES::Plugin::Archive::BA2->read($filename);
	$ba2->write($fd);

	seek($fd, 0, 0);

	my $ctx = Digest::MD5->new;
	$ctx->addfile($fd);
	my $digest = $ctx->hexdigest;

	eq_or_diff($digest, 'ccd48113c0c3483dacdd2ed13525efa3');
}

# read then write (DX10, data skip, Archive2 generated)
{
	my $filename = 't/data/Test - Textures.ba2';
	my $fd = tempfile(UNLINK => 1, SUFFIX => ' - Textures.ba2');

	my $ba2 = TES::Plugin::Archive::BA2->read($filename, data_skip => 1);
	$ba2->write($fd, data_skip => 1);

	seek($fd, 0, 0);

	my $ctx = Digest::MD5->new;
	$ctx->addfile($fd);
	my $digest = $ctx->hexdigest;

	eq_or_diff($digest, '38b1c06a2bd106ae46316211a48d6aff');
}

done_testing();
