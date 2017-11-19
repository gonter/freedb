#!/usr/local/bin/perl
# FILE search/indexer-phase1.pl
#
# prepare a reversed index of freedb data
#
# written:       2001-01-28
# latest update: 2001-01-28 16:00:25
# $Id: indexer-phase1.pl,v 1.1 2002/07/02 06:07:27 gonter Exp $
#

use strict;

use lib '.';
use Net::freedb::file;
use Net::freedb::catalog;
use LMD;

my @cats= qw(blues classical country data folk jazz misc newage reggae rock soundtrack);
# @cats= qw(blues);

my $DOCID= 1;
my $OP_MODE= 'lutmake';

# my $lmd= new LMD;

my $arg;
while ($arg= shift (@ARGV))
{
  if ($arg =~ /^-/)
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
      &usage;
      exit (0);
    }
  }
  else
  {
    &process_file ($arg);
  }
}

# my $fnm= shift || 'd410920f';

# $lmd->close;

# ----------------------------------------------------------------------------
sub usage
{
  print <<EOX;
$0 [-opts]

Options:
-dir <dir>   ... specify directory to search for freedb cats/files
-list <file> ... list of db filenames in file
EOX
}

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

    my $lmd_full= new LMD ('stream' => "db/$sub_dir.stream-". time ());
    my $catalog= new Net::freedb::catalog ('category' => $sub_dir,
                                    'path' => "$dir/$sub_dir",
                                    'catalog' => "db/$sub_dir.catalog");
    print "lmd_full= $lmd_full, catalog=$catalog\n";
    unless ($catalog)
    {
      print "ERROR: no catalog object!\n";
      next;
    }

    $catalog->comment ("lmd update $ts");
    my $updates= $catalog->updates ('rcs' => 0);

    my $upd;
    foreach $upd (@$updates)
    { # see also: cat_test.pl
      my $lmd= $upd->{lmd};
      next unless (defined ($lmd));

      my $is_update= 0;
      $is_update= 1 if ($lmd->{'x'} eq 'u');

      my $f= $upd->{'f'};
      my $r= $upd->{'r'};
      # print ">> upd=$upd is_update=$is_update f=$f r=$r\n";

      my $docid= $r->index ();
      my $dtitle= &process_file ($lmd_full, $f, $docid, $is_update);

      $r->lmd_update (time ());
      $r->title ($dtitle);
  # format: docid, mtime, lmd-update, rcs-update, filename, title
  # print FO_catalog join (':', $sequence, $mtime, time, 0, $cddb_fnm, $dtitle), "\n";

      $count++;
      printf ("%6d %s\n", $count, $sub_dir) if (($count % 1000) == 0);
    }

    printf ("%6d %s DONE\n", $count, $sub_dir);
    $lmd_full->close;

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
  my ($lmd, $fnm, $docid, $is_update)= @_;

  my $db= new Net::freedb::file;

  my @st= stat ($fnm);
  $db->{_stat_}= \@st;
  # print ">> $fnm\n";
  $db->read ($fnm);

  my $dtitle;
  if ($OP_MODE eq 'test')
  {
    open (FO, ">\@bla") || die;
    $db->print (*FO);
    close (FO);
    my $diff= `diff \@bla $fnm 2>&1`;
    print "$fnm\n";

    if ($diff)
    {
      # print "$fnm\n";
      print $diff, "\n", '-'x72, "\n";
    }
  }
  elsif ($OP_MODE eq 'lutmake')
  {
    $dtitle= $lmd->write_lutmake_stream ($db, $docid, $is_update);
  }

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
