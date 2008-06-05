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

my $pw_file = '/etc/passwd';
my $shadow_file = '/etc/shadow';
my $merge_file = '/etc/passwd.M';
my $MAGICUSER = "-xxxxxx";
my $MAGICLINE = "-xxxxxx:x:0:0:WARNING...Everything after this line changed by mkcpasswd::";
my $shadow_pwstr = "*K*";

# Check for existence and writeability of above files
# Open files for reading
# * Sanity check number of passwd entries above the magic line
# * "Cook" the files if necessary (probably not necessary for first pass)
my $pw_dir = dirname($pw_file);
if ( ! -w abs_path($pw_dir) ) { die "Cannot write to $pw_dir." };
if ( ! -r $pw_file ) { die "Cannot read passwd file ($pw_file)" };
open(PWFILE,$pw_file) or die "Cannot open passwd file ($pw_file)";

my %pw_hash = ();
my $localacct = 1;

# Read passwd file and populate pw_hash
# * set 'localacct' flag for entries above the magic line
while ( <PWFILE> ) {
  chomp;
  my ($username, $pw, $uid, $gid, $gcos, $homedir, $loginshell) = split(/:/);

  #printf "Processing $username...\n";

  if ( $username eq $MAGICUSER ) {
    if ( ! $localacct ) {
      print STDERR "WARNING: Multiple magic lines in file!\n";
      next;
    } else {
      #printf "Encountered magic line; non-local accounts from now on\n";
      $localacct = 0;
      next;
    }
  }

  if ( exists $pw_hash{$username} ) {
    print STDERR "WARNING: user $username already processed: ";
    if ( $localacct and $pw_hash{$username}{localacct} )  {
      print STDERR "replacing local account\n";
      delete $pw_hash{$username};
    } else {
      print STDERR "skipping.\n";
      next;
    }
  } else {
  }

  $pw_hash{$username} = {
      username => $username,
      passwd => $pw,
      uid => $uid,
      gid => $gid,
      gcos => $gcos,
      homedir => $homedir,
      shell => $loginshell,
      localacct => $localacct,
      preserve => $localacct,
  };
}
close(PWFILE) or warn "Error closing passwd file\n";

# Read shadow file and update pw_hash entries
# * if entry not found in pw_hash, error and exit

my $shadow_dir = dirname($shadow_file);
if ( ! -w abs_path($shadow_dir) ) { die "Cannot write to $shadow_dir." };
if ( ! -r $shadow_file ) { die "Cannot read passwd file ($shadow_file)" };
open(SHADOWFILE,$shadow_file) or die "Cannot open passwd file ($shadow_file)";

# Read shadow file and populate pw_hash
# if account is not a local account in the pw_hash, disregard!!
while ( <SHADOWFILE> ) {
  chomp;
  my ($username, $cryptpw, $lastchange, $nextchange, $mustchange, $expire, $disableafterexpire, $disable, $reserved) = split(/:/);

  if ( exists $pw_hash{$username} ) {
    if ( ! $pw_hash{$username}{localacct} )  {
      print STDERR "WARNING: user $username in shadow file not a local account ($pw_hash{$username}{localacct}): dropping\n";
      next;
    }
  } else {
    print STDERR "WARNING: user $username in shadow file not in passwd file:  dropping.\n";
    next;
  }

  $pw_hash{$username}{cryptpw} = $cryptpw;
  $pw_hash{$username}{lastchange} = $lastchange;
  $pw_hash{$username}{nextchange} = $nextchange;
  $pw_hash{$username}{mustchange} = $mustchange;
  $pw_hash{$username}{expire} = $expire;
  $pw_hash{$username}{disableafterexpire} = $disableafterexpire;
  $pw_hash{$username}{disable} = $disable;
  $pw_hash{$username}{reserved} = $reserved;
}
close(SHADOWFILE) or warn "Error closing shadow file\n";

#for my $outerkey ( keys %pw_hash ) {
#  for my $innerkey ( keys %{$pw_hash{$outerkey}} ) {
#    print "\$pw_hash{$outerkey}{$innerkey} => ${pw_hash{$outerkey}{$innerkey}}\n";
#  }
#}

# Read merge passwd file and merge into pw_hash according to
#    policy indicated on command line (policy selection TBI)
# * set 'updated' flag on any fields that are changed (for -v/reporting) (TBI)
# * set preserve flag for entries that appear in merge_file
if ( ! -r $merge_file ) { die "Cannot read merge file ($merge_file)" };
open(MERGEFILE,$merge_file) or die "Cannot open merge file ($merge_file)";

while ( <MERGEFILE> ) {
  chomp;
  my ($username, $pw, $uid, $gid, $gcos, $homedir, $loginshell) = split(/:/);

  if ( exists $pw_hash{$username} ) {
    print STDERR "user $username already in pw_hash: ";
    if ( $pw_hash{$username}{localacct} ) {
      print STDERR "local account - ignoring\n";
    } else {
      $pw_hash{$username}{passwd} = $pw;
      $pw_hash{$username}{uid} = $uid;
      $pw_hash{$username}{gid} = $gid;
      $pw_hash{$username}{gcos} = $gcos;
      $pw_hash{$username}{homedir} = $homedir;
      $pw_hash{$username}{shell} = $loginshell;
      $pw_hash{$username}{preserve} = 1;
      print STDERR "updating information\n";
    }
  } else {
    print STDERR "updating pw_hash with $username from merge file\n";
    $pw_hash{$username} = {
        username => $username,
        passwd => $pw,
        uid => $uid,
        gid => $gid,
        gcos => $gcos,
        homedir => $homedir,
        shell => $loginshell,
        localacct => 0,
        cryptpw => $shadow_pwstr,
        lastchange => '',
        nextchange => '',
        mustchange => '',
        expire => '',
        disableafterexpire => '',
        disable => '',
        reserved => '',
        preserve => 1
    };
  }

}
close(MERGEFILE) or warn "Error closing merge file";

for my $outerkey ( keys %pw_hash ) {
  for my $innerkey ( keys %{$pw_hash{$outerkey}} ) {
    print "\$pw_hash{$outerkey}{$innerkey} => ${pw_hash{$outerkey}{$innerkey}}\n";
  }
}


# dump pw_hash, discarding entries preserved flag set to false
#
# This is pretty hack-ish, but sometime when I actually know perl, I'll
# refactor it.
#
# The code below creates a passwd and shadow file.  The entries above the
# line in the passwd file (and the corresponding entries in the shadow file)
# are ordered by the uid, and the entries below the line are ordered
# alphanumerically by username
#
# I couldn't make sort work on a substring of the list entry, and I also
# couldn't come up with a clever way to sort the entries above the line in the
# passwd file and apply the same sort to the list of shadow entries.  So I am
# just condensing the passwd and shadow entries into one string and breaking it
# up when I writethem out.
#

my @pw_atl_list;  # "above the line"
my @pw_btl_list;  # "below the line"

for my $username ( keys %pw_hash ) {
  print "$username...";
  if ( ! $pw_hash{$username}{preserve} ) {
    print "skipping\n";
    next;
  }
  print "processing\n";

  # Hack #1: Prepend the uid to the list entry for sorting
  my $pwstr = "";
  if ( ! $pw_hash{$username}{localacct} ) {
    $pwstr = "$username";
  }
  else {
    $pwstr = "$pw_hash{$username}{uid}##$username";
  }

  foreach ( "passwd", "uid", "gid", "gcos", "homedir", "shell" ) {
    $pwstr .=  ":$pw_hash{$username}{$_}";
  }

  if ( ! $pw_hash{$username}{localacct} ) {
    $pwstr .= "\n";
    push(@pw_btl_list,$pwstr);
  } else {
    # Hack #2: Append the shadow entry to the passwd entry so they get sorted
    #          together
    $pwstr .=  "##";
    $pwstr .= "$username";

    foreach ( "cryptpw", "lastchange", "nextchange", "mustchange", "expire", "disableafterexpire", "disable", "reserved" ) {
      $pwstr .=  ":$pw_hash{$username}{$_}";
    }
    $pwstr .= "\n";
    push(@pw_atl_list,$pwstr);
  }
}

my ($tmp_pw_fh, $tmp_pw_file) = tmpnam();
my ($tmp_shadow_fh, $tmp_shadow_file) = tmpnam();
my @sorted_pw_atl_list = sort { $a <=> $b } @pw_atl_list;
#print @sorted_pw_atl_list;
foreach my $line (@sorted_pw_atl_list) {
  my $linecopy = $line;
  $line =~ s/^\d+##(.*?)##.*/$1/;
  $linecopy =~ s/^\d+##.*?##(.*)/$1/;
  print $tmp_pw_fh $line;
  print $tmp_shadow_fh $linecopy;
}
close($tmp_shadow_fh);
print $tmp_pw_fh "$MAGICLINE\n";
print $tmp_pw_fh sort @pw_btl_list;
close($tmp_pw_fh);

move($tmp_pw_file,$pw_file) or die "unable to rename $tmp_pw_file to $pw_file";
move($tmp_shadow_file,$shadow_file) or die "unable to rename $tmp_shadow_file to $shadow_file";
#print $tmp_shadow_fh sort @shadow_list;
#print sort { $a =~ /[^:]*:[^:]*:(\d+)/ <=> $b =~ /[^:]*:[^:]*:(\d+)/ } @pw_atl_list;
#print sort { $b =~ /^[^:]*:[^:]*:(\d+)/ <=> $a =~ /^[^:]*:[^:]*:(\d+)/ } @shadow_list;
# safely replace pw_file with pw_hash dump
