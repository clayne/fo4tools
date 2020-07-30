package TES::Plugin::Common;

use FindBin;
use lib "$FindBin::Bin/../lib";

use File::stat qw(stat);
use File::Basename qw(dirname);
use File::Temp qw(tempfile);
use File::Copy qw(cp);
use File::Spec qw();
use Carp qw(confess);
use Data::Dumper;

use strict;
use warnings FATAL => qw(all);

local $SIG{__DIE__} = \&confess;
sub fatal { local $SIG{__DIE__}; die @_, "\n" }

local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Useqq = 1;

our $VERSION = '$Id$';

sub file_join {
	my ($dirname, $basename) = @_;
	return File::Spec->join(defined $dirname && $dirname ne '.' ? $dirname : (), $basename);
}

sub file_sub_proc {
	my ($from_to) = @_;
	my ($from, $to) = (ref $from_to ne 'ARRAY') ? split(':', $_, 2) : @$from_to;
	return ($from && $to) ? ($from, $to)
		: fatal "Problem with parsing from/to:"
		. Dumper { from => $from, to => $to, __from_to => $from_to };
}

sub file_sub {
	my ($file, %opts) = @_;
	my $check_length = $opts{'check_length'} // 1;
	my $sub = $opts{'sub'};
	my $sub_ext = $opts{'sub_ext'};
	my $match = $opts{'match'};
	my $match_ext = $opts{'match_ext'};
	my $verbose = $opts{'verbose'} // 0;
	my $file_sub = $file;

	foreach ($match, $match_ext) {
		if (defined && ref ne 'Regexp') {
			$_ = /^\/([^\/]+)\/$/ ? qr/$1/ : qr/(\Q$_\E)/;
		}
	}

	# 0: Any generic substitution outside of extension
	# 1: Specifically for extensions
	foreach ([ $sub, 0 ], [ $sub_ext, 1 ]) {
		my ($sub, $ext) = @$_;
		next unless (defined $sub && scalar @$sub);

		# If sub is not an array and doesn't contain a split separator
		# turn it into an array. This is to support passing in just a single
		# array of from/to patterns.
		$sub = [ $sub ] unless (ref $sub->[0] eq 'ARRAY' || scalar @$sub == 1);

		foreach (@$sub) {
			my ($from, $to) = file_sub_proc($_);
			if ($ext) {
				if (ref $from ne 'Regexp') {
					# Remove any leading dots in passed in extensions if specified
					$from = '.' . ($from =~ s/^\.//r);
					$from = ($from =~ /^\/([^\/]+)\/$/) ? qr/$1/ : qr/\Q$from\E(?=[\/\\]|$)/;
				}

				$to = '.' . ($to =~ s/^\.//r);
			} else {
				if (ref $from ne 'Regexp') {
					$from = ($from =~ /^\/([^\/]+)\/$/) ? qr/$1/ : qr/(\Q$from\E)/;
				}
			}

			if (!defined $match) {
				my $file_sub_orig = $file_sub; $file_sub =~ s/$from/$to/g;
				print STDERR Dumper { from => $from, to => $to, file_sub => [ $file_sub_orig, $file_sub ] }
					if ($verbose > 1);
				next;
			}

			my $atom_match = ($ext && $match_ext ? $match_ext : $match);
			my @atoms = ($file_sub =~ /$atom_match/g);
			print STDERR Dumper { file => $file, file_sub => $file_sub, atoms => \@atoms, atom_match => $atom_match, ext => $ext }
				if ($verbose > 1);
			foreach (@atoms) {
				my ($pre, $pst) = ($_, s/$from/$to/gr);
				my $file_sub_orig = $file_sub; $file_sub =~ s/\Q$pre\E/$pst/;
				print STDERR Dumper { file_sub => [ $file_sub_orig, $file_sub ], pre => $pre, pst => $pst, from => $from, to => $to }
					if ($verbose > 1);
			}
		}
	}

	if ($check_length && length($file_sub) != length($file)) {
		fatal "Unequal substitution lengths: '$file_sub' vs '$file'";
	}

	return $file_sub;
}

sub file_clone {
	my ($src, $dst, %opts) = @_;
	my $link = $opts{'link'};
	my $rename = $opts{'rename'};
	my $overwrite = $opts{'overwrite'};
	my $timestamp = $opts{'timestamp'};
	my $backup = $opts{'backup'};
	my $backup_always = $opts{'backup_always'};
	my $backup_overwrite = $opts{'backup_overwrite'};
	my $backup_extension = $opts{'backup_extension'} // 'backup';
	return unless (! -f $dst || $overwrite);

	# Copy src to dst and clone atime/mtime.
	if ($backup && ($backup_always || $src eq $dst)) {
		my $backup = join('.', $src, $backup_extension);
		if (! -f $backup || $backup_overwrite) {
			unlink($backup) or die "unlink: $backup: $!"  if (-f $backup);
			link($src, $backup) or die "link: $src -> $backup: $!";
		}
	}

	my $stat = stat($src) or die "stat: $!: $src";
	if ($rename) {
		rename($src, $dst) or die "rename: $src -> $dst: $!";
	} elsif ($link) {
		unlink($dst) or die "unlink: $dst: $!" if (-f $dst);
		link($src, $dst) or die "link: $src -> $dst: $!";
	} else {
		# cp() cannot handle src == dst
		my (undef, $tmp) = tempfile(UNLINK => 0, DIR => dirname($src));
		cp($src, $tmp) or die "copy: $src -> $tmp: $!";
		rename($tmp, $dst) or die "rename: $tmp -> $dst: $!";
	}

	utime($timestamp // $stat->atime, $timestamp // $stat->mtime, $dst)
		or die "utime: $dst: $!";

	return 1;
}

sub fmt_print
{
	my $ent = $_[0] || return;			# arrays of hashes to format
	my $tab = $_[1] || return;			# format table
	my $sep = $_[2] // ' | ';			# field separator
	my $hdp = $_[3];				# header print (0 == no, 1 == stdout)
	my $str = (defined $_[4] ? "" : undef);		# return as string?
	my @tab = grep defined, @$tab;
	my @out = ();

	# Ordered list of just the keys from the format table.
	my @key = map $_->[0], @tab;

	# Pre-compute min lengths based on keys passed in.
	my %len = map +($_, length $_), @key;

	# For all entries passed in, figure out the longest length of
	# each field based on the data in each entry while at the same
	# time dumping each field to an array based on format table
	# key order. This output will then be fed to *printf using a
	# synthesized format string that takes length into account.
	foreach my $ent (@$ent) {
		next unless (scalar %$ent);
		push @out, [ map {
			my $val = defined $ent->{$_} ? $ent->{$_} : '';
			my $len = length $val;
			$len{$_} = $len unless ($len < $len{$_});
			$val;
		} (@key) ];
	}

	# For each format entry, synthesize a per-field format based
	# on minimum calculated length. Concatenate each per-field
	# format into a single line format which will be used with
	# each entry in the output array.

	my @fmt;
	for (my ($i, $m) = (0, scalar @tab); $i < $m; $i++) {
		my $t = $tab->[$i] || next;
		my ($min, $max) = scalar(@$t) > 2 ? ($t->[1], $t->[2]) : (0, $t->[1]);
		my $cur = $len{$t->[0]};

		if ($max) {
			# If max length is negative, left justify.
			my $_jst = ($max < 0 ? '-' : '');

			# Effective length constrained within $min and $max.
			$cur = $cur < abs $min ? abs $min
			     : $cur > abs $max ? abs $max
			     : $cur;

			# Synthesize per-field format.
			push @fmt, sprintf "%%%s%ss", $_jst, $cur ? "$cur.$cur" : '';
		} elsif ($i < $m - 1) {
			push @fmt, sprintf "%%%ss", $cur ? "$cur.$cur" : '';
		} else {
			push @fmt, sprintf "%%s";
		}
	}
	my $fmt = sprintf("%s\n", join($sep, @fmt));

	# If $hdp is explicit, use it to determine if the field headers
	# should be emitted; otherwise emit headers only if there is output.
	if (defined $hdp ? $hdp : scalar @out) {
		if (defined $str) {
			$str .= sprintf($fmt, @key);
		} elsif (defined $hdp && $hdp == 1) {
			printf STDOUT ($fmt, @key);
		} else {
			printf STDERR ($fmt, @key);
		}
	}

	# Dump output to string or stdout.
	foreach (@out) {
		if (defined $str) {
			$str .= sprintf($fmt, @$_);
		} else {
			printf STDOUT ($fmt, @$_);
		}
	}

	return (defined $str ? $str : 1);
}

use Exporter 'import';
our @EXPORT_OK = qw(file_sub file_clone file_join fmt_print);

1;

__END__
