#!/usr/local/bin/perl
# FILE %gg/work/fbsd/gg-data/recordings/LMD.pm
#
# written:       2001-01-28
# latest update: 2001-07-17 20:27:25
# $Id: LMD.pm,v 1.1 2002/07/02 06:07:27 gonter Exp $
#

package LMD;

use strict;

# ----------------------------------------------------------------------------
sub new
{
  my $class= shift;
  my %pars= @_;

  my $obj=
  {
    'stream'     => $pars{'stream'}  || '@cddb_stream',
    # 'catalog'    => $pars{'catalog'} || '@cddb_toc.tfb',
    'sequence'   => $pars{'sequence'} || 1,
  };
  bless $obj;

  local (*FO1, *FO2);
  # $obj->open_file (*FO1, 'catalog');
  $obj->open_file (*FO2, 'stream');

  $obj;
}

# ----------------------------------------------------------------------------
sub open_file
{
  my $obj= shift;
  local *FO= shift;
  my $what= shift;

  print "creating $what ", $obj->{$what}, "\n";
  open (FO, '>' . $obj->{$what}) || die;
print FO "# file $what='",  $obj->{$what}, "'\n";
  $obj->{'FO_'.$what}= *FO;
}

# ----------------------------------------------------------------------------
sub close_file
{
  my ($obj, $what)= @_;

  print "closing $what ", $obj->{$what}, "\n";
  local *FO= $obj->{'FO_'.$what};
  close (FO);
  $obj->{'FO_'.$what}= undef;
}

# ----------------------------------------------------------------------------
sub close
{
  my $obj= shift;

  # $obj->close_file ('catalog');
  $obj->close_file ('stream');

  1;
}

# ----------------------------------------------------------------------------
sub write_lutmake_stream
{
  my $lmd= shift;       # LMD Object
  my $cddb= shift;      # Net::freedb::file Object
  my $docid= shift;
  my $is_update= shift; # 1 -> LMD index already present

  my $cddb_fnm= $cddb->{'_FILENAME_'};

  # local *FO_catalog= $lmd->{'FO_catalog'};
  my $sequence= $lmd->{'sequence'}++;

  my $dtitle= $cddb->{'DTITLE'};
  my $mtime= $cddb->{_stat_}->[9];

  my ($artist, $title)= split (/\//, $dtitle, 2);

  # build a list of words in the document, the flags are a
  # bit-field that indicate in which field the word is located
  my %words= ();
  &collect_words (\%words, 1, $artist);
  &collect_words (\%words, 2, $title);
  &collect_words (\%words, 8, $cddb->{'EXTD'});

  my $track;
  foreach $track (@{$cddb->{tracks}})
  {
    # print "track= $track\n";
    &collect_words (\%words, 4, $track->{'TTITLE'});
    &collect_words (\%words, 8, $track->{'EXTT'});
  }

  # sort word list by flag value
  my %flags;
  my ($word, $flag);
  foreach $word (keys %words)
  {
    my $flag= $words{$word};
    # printf (">>> flags=%02X word='%s'\n", $flag, $word);
    push (@{$flags{$flag}}, $word);
  }
  
  # write word stream
  local *FO_stream= $lmd->{FO_stream};
  print FO_stream <<EOX;
# sequence=$sequence, docid=$docid fnm=$cddb_fnm
DOCID $docid
EOX
  if ($is_update) { print FO_stream "DOCDEL\n"; }

  foreach $flag (keys %flags)
  {
    print FO_stream <<EOX;
LOCCODE $flag
DATA
EOX

    foreach $word (@{$flags{$flag}})
    {
      print FO_stream $word, "\n";
    }
    print FO_stream ".\n";
  }

  $dtitle;
}

# ----------------------------------------------------------------------------
sub collect_words
{
  my ($list, $flags, $str)= @_;
  my @words= &get_words ($str);
  foreach $str (@words)
  {
    $list->{$str} |= $flags;
  }
}

# ----------------------------------------------------------------------------
sub get_words
{
  my $s= shift;

  $s=~ tr/A-Z/a-z/;
  $s=~ tr/\x00-\/:-\@\[-_\x7B-\xFF/ /s;
  $s=~ s/^ //;
  $s=~ s/ $//;
  my @s= split (' ', $s);

  (wantarray) ? @s : \@s;
}

1;
