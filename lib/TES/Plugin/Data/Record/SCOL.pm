package TES::Plugin::Data::Record::SCOL;
use parent 'TES::Plugin::Data::Record';

use FindBin;
use lib "$FindBin::Bin/../lib";

use TES::Plugin::Common qw(file_sub);
use List::Util qw(pairkeys pairvalues pairmap);
use Scalar::Util qw(blessed);
use File::Basename qw(basename dirname);
use File::stat qw(stat);
use Fcntl qw(SEEK_SET);
use Data::Dumper;
use Carp qw(confess);

use strict;
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;
sub fatal { local $SIG{__DIE__}; die @_, "\n" }

local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Useqq = 1;

our $VERSION = '$Id$';

use constant {
	F_NON_OCCLUDER => (0x1 << 4),
	F_DELETED => (0x1 << 5),
	F_HIDDEN => (0x1 << 9),
	F_UNKNOWN_10 => (0x1 << 10),
	F_PLATFORM => (0x1 << 11),
	F_IGNORED => (0x1 << 12),
	F_DISTANT_LOD => (0x1 << 15),
	F_OBSTACLE => (0x1 << 25),
	F_NAVMESH_FILTER => (0x1 << 26),
	F_NAVMESH_BOUNDING_BOX => (0x1 << 27),
	F_NAVMESH_GROUND => (0x1 << 30),
};

sub model {
	my ($self, $model) = @_;
	if (defined $model) {
		$self->parsed->{'model'} = $model;
		$self->parsed->dirty(1);
	}
	return $self->parsed->{'model'};
}

sub rewrite {
	my ($self, %opts) = @_;
	my $verbose = $opts{'verbose'} // $self->{'verbose'} // 0;
	my $sub_file_ext = delete $opts{'sub_file_ext'};
	my $sub_file = delete $opts{'sub_file'};
	my $sub_ext = delete $opts{'sub_ext'};
	my $sub = delete $opts{'sub'};
	my $basename = delete $opts{'basename'};
	my $hex = delete $opts{'hex'};
	my $cb = delete $opts{'cb'};
	my $cb_args = delete $opts{'cb_args'};
	my $rewrite = 0;

	my $model = $self->parsed->{'model'};
	my $model_new = file_sub($model,
		sub => $sub_file // $sub,
		sub_ext => $sub_file_ext // $sub_ext,
		verbose => $verbose,
	);
	return if ($model eq $model_new);

	if ($cb) {
		my $ret = $cb->($model, $model_new, $cb_args ? @$cb_args : ()) || next;
		fatal "callback failed" if ($ret < 0);
	}

	printf STDERR ("Writing%s: %s\n",
		$basename ? " \"%basename\"" : "",
		$model_new,
	) if ($verbose);

	$self->parsed->{'model'} = $model_new;
	$self->parsed->dirty(1);
	$rewrite++;

	return $rewrite;
}

sub data_tab {
	return {
		EDID => [ editor_id => 'Z*' ],
		OBND => [ object_bounds => 's6', array => 1 ],
		PTRN => [ preview_transform => 'L' ],
		MODL => [ model => 'Z*' ],
		MODT => [ model_hash => 'a*' ],
		MODC => [ color_remapping_index => 'a4' ],
		MODS => [ material_swap => 'L' ],
		MODF => [ modf_unknown => 'a*' ],
		FLTR => [ filter => 'Z*' ],
		ONAM => {
			read => sub { $_[0]->{parts}[$_[2]]{static} = unpack('L', $_[1]) },
			write => sub { $_[0] = pack('L', $_[1]->{parts}[$_[2]]{static}) },
		},
		DATA => {
			# 7 4-byte values per placement
			read => sub {
				# unpack will return groups of 7 a4s as a single list, hence the
				# initial unpack and map needed to split them up into 28-byte units
				my @tmp = map [ unpack('(a4)7', $_) ], unpack('(a28)*', $_[1]);
				for (my $i = 0; $i < scalar @tmp; $i++) {
					@{$_[0]->{parts}[$_[2]]{placement}[$i]}{ qw(
						pos_x
						pos_y
						pos_z
						rot_x
						rot_y
						rot_z
						scale
					) } = @{$tmp[$i]};
				}
			},
			write => sub {
				$_[0] = pack('((a4)7)*', map {
					@$_{ qw(
						pos_x
						pos_y
						pos_z
						rot_x
						rot_y
						rot_z
						scale
					) }
				} @{$_[1]->{parts}[$_[2]]{placement}});
			},
		},
	},
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
	) }
);

1;

__END__
