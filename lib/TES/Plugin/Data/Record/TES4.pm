package TES::Plugin::Data::Record::TES4;
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
	F_MASTER => (0x1 << 1),
	F_LOCALIZED => (0x1 << 7),
	F_MASTER_LIGHT => (0x1 << 9),
};

sub masters {
	my ($self, $masters) = @_;
	if (defined $masters) {
		$self->parsed->{'master'} = [ map +{ filename => $_, size => 0 }, @$masters ];
		$self->parsed->dirty(1);
	}
	return [ map $_->{'filename'}, @{$self->parsed->{'master'}} ];
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

	for (my $i = 0; $i < scalar @{$self->parsed->{'master'}}; $i++) {
		my $master = $self->parsed->{'master'}[$i];
		my $filename = $master->{'filename'};
		my $filename_new = file_sub($filename,
			sub => $sub_file // $sub,
			sub_ext => $sub_file_ext // $sub_ext,
			verbose => $verbose,
		);
		next if ($filename eq $filename_new);

		if ($cb) {
			my $ret = $cb->($filename, $filename_new, $cb_args ? @$cb_args : ()) || next;
			fatal "callback failed" if ($ret < 0);
		}

		# XXX: should probably be handled by the callback
		printf STDERR ("Writing%s: %s %s\n",
			$basename ? " $basename" : "",
			sprintf($hex ? '[%02X]' : '[%02d]', $i),
			$filename_new,
		) if ($verbose);

		$master->{'filename'} = $filename_new;
		$self->parsed->dirty(1);
		$rewrite++;
	}

	return $rewrite;
}

sub data_tab {
	return {
		HEDR => [ [ qw(version record_count object_id_next) ] => 'a4LL' ],
		CNAM => [ author => 'Z*' ],
		SNAM => [ description => 'Z*' ],
		MAST => {
			read => sub { $_[0]->{master}[$_[2]]{filename} = unpack('Z*', $_[1]) },
			write => sub { $_[0] = pack('Z*', $_[1]->{master}[$_[2]]{filename}) },
		},
		DATA => {
			read => sub { $_[0]->{master}[$_[2]]{size} = unpack('Q', $_[1]) },
			write => sub { $_[0] = pack('Q', $_[1]->{master}[$_[2]]{size}) },
		},
#		ONAM => {
#			read => sub { $_[0]->{overridden_formid}[$_[2]] = [ unpack('L*', $_[1]) ] },
#			write => sub { $_[0] = pack('L*', $_[1]->{overridden_formid}[$_[2]]) },
#		},
#		TNAM => {
#			read => sub { $_[0]->{transient_type}[$_[2]] = [ unpack('(LL)*', $_[1]) ] },
#			write => sub { $_[0] = pack('(LL)*', $_[1]->{transient_type}[$_[2]]) },
#		},
		INTV => [ version_internal => 'L' ],
		INCC => [ internal_cell_count => 'L' ],
	};
}

use Class::XSAccessor (
	accessors => { map +($_, $_), qw(
	) }
);

1;

__END__
