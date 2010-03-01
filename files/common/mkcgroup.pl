#!/usr/bin/perl -w

use strict 'vars';
use strict 'subs';

use Cwd qw/ abs_path /;
use File::Basename qw/ dirname basename /;
use File::Temp qw/ :POSIX /;
use File::Copy;

# Only allow one instance to run at a time
use Fcntl qw (:flock);
open SELF, "< $0" or die "unable to open SELF";
flock SELF, LOCK_EX | LOCK_NB or die "SELF Locked.  Previous process still running?";

my $group_file = '/etc/group';
my $merge_file = '/etc/group.M';
my $group_mode = 0644;
my $MAGICUSER = "-xxxxxx";
my $MAGICLINE = "-xxxxxx::0:";
my $SQUASHLINE = "IGNORE";

# Check for existence and writeability of above files
# Open files for reading
# * Sanity check number of group entries above the magic line
# * "Cook" the files if necessary (probably not necessary for first pass)
my $group_dir = dirname($group_file);
if ( ! -w abs_path($group_dir) ) { die "Cannot write to $group_dir." };
if ( ! -r $group_file ) { die "Cannot read passwd file ($group_file)" };
open(GRPFILE,$group_file) or die "Cannot open passwd file ($group_file)";

# First things first.  Check the .M file.  If it consist of a single special
# line, then abort right now and leave the current passwd file in place.
if ( ! -r $merge_file ) { die "Cannot read merge file ($merge_file)" };
open(MERGEFILE,$merge_file) or die "Cannot open merge file ($merge_file)";
my $firstline = <MERGEFILE>;
close(MERGEFILE); 
chomp($firstline);
if ( $firstline eq $SQUASHLINE ) {
  close(GRPFILE);
  exit 0;
}

my %grp_hash = ();
my $localacct = 1;

# Read group file and populate grp_hash
# * set 'localacct' flag for entries above the magic line
while ( <GRPFILE> ) {
  chomp;
  my ($groupname, $pw, $gid, $userlist) = split(/:/);

  #printf "Processing $groupname...\n";

  if ( $groupname eq $MAGICUSER ) {
    if ( ! $localacct ) {
      print STDERR "WARNING: Multiple magic lines in file!\n";
      next;
    } else {
      #printf "Encountered magic line; non-local accounts from now on\n";
      $localacct = 0;
      next;
    }
  }

  if ( exists $grp_hash{$groupname} ) {
    print STDERR "WARNING: group $groupname already processed: ";
    if ( $localacct and $grp_hash{$groupname}{localacct} )  {
      print STDERR "replacing local account\n";
      delete $grp_hash{$groupname};
    } else {
      print STDERR "skipping.\n";
      next;
    }
  } else {
    # cool
  }

  $grp_hash{$groupname} = {
      groupname => $groupname,
      passwd => $pw,
      gid => $gid,
      userlist => $userlist,
      localacct => $localacct,
      preserve => $localacct,
  };
}
close(GRPFILE) or warn "Error closing group file\n";


#for my $outerkey ( keys %pw_hash ) {
#  for my $innerkey ( keys %{$pw_hash{$outerkey}} ) {
#    print "\$pw_hash{$outerkey}{$innerkey} => ${pw_hash{$outerkey}{$innerkey}}\n";
#  }
#}

# Read merge group file and merge into grp_hash according to
#    policy indicated on command line (policy selection TBI)
# * set 'updated' flag on any fields that are changed (for -v/reporting) (TBI)
# * set preserve flag for entries that appear in merge_file
if ( ! -r $merge_file ) { die "Cannot read merge file ($merge_file)" };
open(MERGEFILE,$merge_file) or die "Cannot open merge file ($merge_file)";

while ( <MERGEFILE> ) {
  chomp;
  my ($groupname, $pw, $gid, $userlist) = split(/:/);

  if ( exists $grp_hash{$groupname} ) {
    print STDERR "group $groupname already in grp_hash: ";
    if ( $grp_hash{$groupname}{localacct} ) {
      print STDERR "local group - ignoring\n";
    } else {
      $grp_hash{$groupname}{passwd} = $pw;
      $grp_hash{$groupname}{gid} = $gid;
      $grp_hash{$groupname}{userlist} = $userlist;
      $grp_hash{$groupname}{preserve} = 1;
      print STDERR "updating information\n";
    }
  } else {
    print STDERR "updating grp_hash with $groupname from merge file\n";
    $grp_hash{$groupname} = {
        groupname => $groupname,
        passwd => $pw,
        gid => $gid,
        userlist => $userlist,
        localacct => 0,
        preserve => 1
    };
  }

}
close(MERGEFILE) or warn "Error closing merge file";

for my $outerkey ( keys %grp_hash ) {
  for my $innerkey ( keys %{$grp_hash{$outerkey}} ) {
    print "\$grp_hash{$outerkey}{$innerkey} => ${grp_hash{$outerkey}{$innerkey}}\n";
  }
}


# dump grp_hash, discarding entries preserved flag set to false
#
# This is pretty hack-ish, but sometime when I actually know perl, I'll
# refactor it.
#
# The code below creates a group file.  The entries above the
# line are grouped and ordered by gid, and the entries below the line are
# grouped and ordered by gid.
#

my @grp_atl_list;  # "above the line"
my @grp_btl_list;  # "below the line"

for my $groupname ( keys %grp_hash ) {
  print "$groupname...";
  if ( ! $grp_hash{$groupname}{preserve} ) {
    print "skipping\n";
    next;
  }
  print "processing\n";

  my $grpstr = "$grp_hash{$groupname}{gid}##$groupname";
  foreach ( "passwd", "gid", "userlist" ) {
    $grpstr .= ":$grp_hash{$groupname}{$_}";
  }
  $grpstr .= "\n";

  if ( ! $grp_hash{$groupname}{localacct} ) {
    push(@grp_btl_list,$grpstr);
  } else {
    push(@grp_atl_list,$grpstr);
  }
}

my ($tmp_grp_fh, $tmp_grp_file) = tmpnam();
my @sorted_grp_atl_list = sort { $a <=> $b } @grp_atl_list;
#print @sorted_grp_atl_list;
foreach my $line (@sorted_grp_atl_list) {
  $line =~ s/^.*?##(.*)/$1/;
  print $tmp_grp_fh $line;
}

print $tmp_grp_fh "$MAGICLINE\n";

my @sorted_grp_btl_list =  sort { $a <=> $b } @grp_btl_list;
foreach my $line (@sorted_grp_btl_list) {
  $line =~ s/^.*?##(.*)/$1/;
  print $tmp_grp_fh $line;
}
close($tmp_grp_fh);

move($tmp_grp_file,$group_file) or die "unable to rename $tmp_grp_file to $group_file";
chmod($group_mode, $group_file);
#print $tmp_shadow_fh sort @shadow_list;
#print sort { $a =~ /[^:]*:[^:]*:(\d+)/ <=> $b =~ /[^:]*:[^:]*:(\d+)/ } @grp_atl_list;
# safely replace grp_file with grp_hash dump
