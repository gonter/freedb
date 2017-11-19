#!/usr/local/bin/perl
# FILE freedb2cvs.pl
#
# update a CVS repository containng freedb database files
#
# written:       2002-03-28
# latest update: 2002-03-28 19:16:20
# $Id: freedb2cvs.pl,v 1.1 2002/07/02 06:07:27 gonter Exp $
#

use strict;

use Net::freedb::file;
use Net::freedb::catalog;
# my @cats= qw(blues classical country data folk jazz misc newage reggae rock soundtrack);
my @cats= qw(blues data folk);

my $CVSROOT= '/archive/cddb/cvsroot';
my $DB_SUBDIR= '/db';
$ENV{TMPDIR}= '/tmp';  # used by ci!

my $arg;
while ($arg= shift (@ARGV))
{
  if ($arg eq '-dir')
  {
    &process_dir (shift (@ARGV));
  }
  elsif ($arg eq '-list')
  {
    &process_list (shift (@ARGV));
  }
  else
  {
    &process_file ($arg);
  }
}

exit (0);

# ----------------------------------------------------------------------------
sub process_dir
{
  my $dir= shift;

  local *DIR;
  my ($sub_dir, $e);
  foreach $sub_dir (@cats)
  {
    unless (-d "$dir/$sub_dir")
    {
      print "no such directory: $dir/$sub_dir\n";
      next;
    }
    my $count;
    my $ts= &ts;

    my $catalog= new Net::freedb::catalog ('category' => $sub_dir,
                                    'path' => "$dir/$sub_dir",
                                    'catalog' => "db/$sub_dir.catalog");
    print "catalog=$catalog\n";
    unless ($catalog)
    {
      print "ERROR: no catalog object!\n";
      next;
    }

    $catalog->comment ("cvs update $ts");
    my $updates= $catalog->updates ('lmd' => 0);
    my $rcs_dir= $CVSROOT . $DB_SUBDIR . '/' . $sub_dir;
    unless (-d $rcs_dir)
    {
      my $cmd= "mkdir -p $rcs_dir";
      print ">> $cmd\n";
      system ($cmd);
    }

    my $upd;
    foreach $upd (@$updates)
    { # see also: cat_test.pl
      my $rcs= $upd->{rcs};
      next unless (defined ($rcs));

      my $is_update= 0;
      $is_update= 1 if ($rcs->{'x'} eq 'u');

      my $f= $upd->{'f'};
      my $r= $upd->{'r'};
      my $e= $upd->{'e'};
      # print ">> upd=$upd is_update=$is_update f=$f r=$r\n";

      my $dtitle= &process_file ($f, $rcs_dir, $e, $is_update);

      $r->rcs_update (time ());
      $r->title ($dtitle);
  # format: docid, mtime, lmd-update, rcs-update, filename, title
  # print FO_catalog join (':', $sequence, $mtime, time, 0, $cddb_fnm, $dtitle), "\n";

      $count++;
      printf ("%6d %s\n", $count, $sub_dir) if (($count % 1000) == 0);
    }

    printf ("%6d %s DONE\n", $count, $sub_dir);

    $catalog->save ();
  }
}

# ----------------------------------------------------------------------------
sub process_list
{
  my $lmd= shift;
  my $list= shift;
  local *LIST;
  open (LIST, $list) || die;
  while (<LIST>)
  {
    chop;
    next if (/^#/ || /^\s*$/);
    my ($fnm)= split;
    &process_file ($lmd, $fnm);
  }
  close (LIST);
}

# ----------------------------------------------------------------------------
sub process_file
{
  my ($fnm, $rcs_dir, $entry, $is_update)= @_;

  my $db= new Net::freedb::file;

  my @st= stat ($fnm);
  $db->{_stat_}= \@st;
  # print ">> $fnm\n";
  $db->read ($fnm);

  my $dtitle;
  # print "process_file: db='$db' fnm='$fnm' entry='$entry' is_update=$is_update\n";
  my $cmd;
  my $rcs_file= $rcs_dir . '/' .  $entry . ',v';
  if ($is_update)
  {
    $cmd= "ci -mupdate $fnm $rcs_file";
  }
  else
  {
    $cmd= "ci -l '-t-new file' $fnm $rcs_file";
  }
  print ">> $cmd\n";
  system ($cmd);

  $dtitle;
}

# ----------------------------------------------------------------------------
sub ts
{
  my $time= shift || time;
  my @ts= localtime ($time);
 
  sprintf ("%d-%02d-%02d %2d:%02d:%02d",
                   1900 + $ts[5], $ts[4]+1, $ts[3],
                   $ts[2], $ts[1], $ts[0]);
}
