#!/usr/local/bin/perl
# $Id: indexer-phase2.pl,v 1.1 2002/07/02 06:07:27 gonter Exp $

use strict;

my @areas= qw(classical blues country data folk jazz newage
  reggae soundtrack misc rock);

my $LUTMAKE_OPTS= '-ms -nh10000 -ctop200.lst';
my $lutmake= '/usr/local/bin/lutmake';
my $tfblut= '/usr/local/bin/tfblut';
my $verbose= 1;
my $doit= 1;

my %UPDATES= ();
my $area;

my $e;
opendir (DIR, '.') || die;
while (defined ($e= readdir (DIR)))
{
  if ($e =~ /^(.+)\.stream-(\d+)/)
  {
    my ($a, $t)= ($1, $2);
    # print "upd: $a $t\n";
    push (@{$UPDATES{$a}}, $t);
  }
}
closedir (DIR);

foreach $area (@areas)
{
  my $actions;

  my $mtime_lut= &mtime ("$area.lut");
  my $mtime_cat= &mtime ("$area.catalog");

  if ($mtime_lut < $mtime_cat)
  {
    my $c2= "$tfblut $area.catalog";
    print "  $c2\n" if ($verbose);
    system ($c2) if ($doit);
    $actions++;
  }

  $actions += &indexer ("$area");
  print "\n" if ($actions);
}

sub indexer
{
  my $area= shift;
  my $actions= 0;

  my $mtime_lt= &mtime ("$area.lt");
  my $mtime_stream= &mtime ("$area.stream");

  if ($mtime_lt < $mtime_stream)
  {
    my $c1= "$lutmake -min2 -l$area.lt $LUTMAKE_OPTS $area.stream";
    print "  $c1\n" if ($verbose);
    system ($c1) if ($doit);
    $actions++;
  }

  my $updates= $UPDATES{$area};
  if (defined ($updates))
  {
    print "updates: ", join (' ', @$updates), "\n";
    my $c2= "$lutmake -min2 -l$area.lt $LUTMAKE_OPTS -r";
    my $t;
    foreach $t (@$updates)
    {
      next if ($t < $mtime_lt);

      $c2 .= " $area.stream-$t";
    }

      print "  $c2\n" if ($verbose);
      system ($c2) if ($doit);
      $actions++;
  }

  $actions;
}

sub mtime
{
  my $fnm= shift;
  my @stat= stat ($fnm);
  (defined (@stat)) ? $stat[9] : 0;
}

__END__
soundtrack.lt : soundtrack.stream
        lutmake -lsoundtrack.lt $(LUTMAKE_OPTS) soundtrack.stream

# ----
blues.lut : blues.catalog
        tfblut blues.catalog


