#!/usr/local/bin/perl
# FILE %gg/work/fbsd/gg-data/recordings/cddb-locate.pl
#
# simple search engine, uses LMD data for retrieval
#
# written:       2001-01-28
# latest update: 2001-05-07 17:08:00
# $Id: freedb-locate.pl,v 1.1 2002/07/02 06:07:27 gonter Exp $
#

use strict;
use Net::freedb::file;
use lib 'misc';
use tfb;

# configure this
my $db=     '/www/CD/db';
# my $FMT=  'http://whisky.wu-wien.ac.at/cgi-bin/cdfmt';
my $FMT=    '/cgi-bin/cdfmt';
my $deref=  '/usr/local/bin/deref';
my $tfbget= '/usr/local/bin/tfbget';

# initialization
my @areas= qw(blues classical country data folk jazz
              misc newage reggae rock soundtrack);
my %fields= ('artist' => 1, 'title' => '2', 'track' => '4', 'rest' => 8);
my $fields; # bit-field indicating the selected fields from above

my @words= ();
my $fmt= 'plain'; # 'html';
my %par= ( 'allcats' => 'YES', 'allfields' => 'YES', 'grouping' => 'cats',
           'freedb-id' => 'NO' );

my %LMDQS_cache= ();

my %cats;
my $arg;
while ($arg= shift (@ARGV))
{
  if ($arg =~ /^[A-Za-z0-9\*]+$/)
  {
    $arg=~ tr/A-Z/a-z/;
    push (@words, $arg);
  }
}

if ($ENV{'GATEWAY_INTERFACE'})
{
  print <<EO_HTML;
Content-Type: text/html

<html>
<head>
<title>freedb.org</title>
</head>

<body bgcolor="#FFFFFF" text="#000000" link="#101070" vlink="#101070">

<table border=0>
<td bgcolor="#ffffff">
 <table border=0 width="100%" cellpadding=0 cellspacing=0>
  <td bgcolor=#101070>
   <table border=0>
    <td bgcolor=#ffffff><font face="Arial,Helvetica,Lucida" color="#101070" size=8><b>freedb</b></td>
    <td bgcolor=#101070><font face="Arial,Helvetica,Lucida" color="#ffffff" size=8><b>.org</b></td>
   </table>
  </td>
  <tr>
  <td align=right><font face="Arial,Helvetica,Lucida" color="#101070" size=2><b>a free approach to cddbp
 </table>
</td>
</table>
<h1>freedb database search results</h1>
You know, this is "under construction" ...
<hr>
<pre>
EO_HTML

  my $parameter_list= $ENV{'QUERY_STRING'} if ($ENV{'QUERY_STRING'});

  if ($ENV{'CONTENT_LENGTH'})
  {
    my $sollen= $ENV{'CONTENT_LENGTH'};
    my $len= read(STDIN, $parameter_list, $sollen);
  }
  my @av_pair= split(/&/, $parameter_list);
  my $av_pair;
  foreach $av_pair (@av_pair)
  {
    my ($av_name, $av_val)= split(/=/, $av_pair);
    $av_val=~ tr/+/ /;
    $av_val=~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    $par{$av_name}= $av_val;

    # print "av_name='$av_name' av_val='$av_val'\n";

    # Check Boxes
    if ($av_name eq 'cats')   { $cats{$av_val}= 1; }
    if ($av_name eq 'fields') { $fields |= $fields{$av_val}; }

    # Submit Buttons
    if ($av_name eq 'b_fields')
    {
      $fields= $fields{$av_val};
      $par{'allfields'}="NO";
    }
  }

  $fmt= 'html';
  print "</pre><hr>\n";

  my $words= $par{'words'};
  $words=~ tr/A-Z/a-z/;
  $words=~ tr/\0-\/:-\@\x5B-\x60\x7B-\x7F/ /s; # do not allow meta characters!

  if ($par{'allcats'} eq 'YES')
  {
    my $cat;
    foreach $cat (@areas) { $cats{$cat}= 1; }
  }
  if ($par{'allfields'} eq 'YES') { $fields= 255; }

  push (@words, split (' ', $words));
}
else # interactive operation
{
  my $cat;
  foreach $cat (@areas) { $cats{$cat}= 1; }
  $fields= 255;
}

if (@words)
{
# print "<pre>searching...\n";
# print "cats: ", join (', ', %cats), "\n";
# print "</pre>\n";

  my $area;

my $BUG= <<EOX;
BUG [2001-08-03]
A compound search like "bach kantatenwerk" in "blues" will not match if
"bach" is only found in the "artist" field while "kantatenwerk" is only
in the "title" field.
EOX

  my %SORT;
  my $total_hits;
  foreach $area (sort keys %cats)
  {
# print "area=$area\n";
    next if ($area eq 'ALL');

    my $catalog= "$db/$area.catalog";
    my $catalog_lut= "$db/$area.lut";
    my $lt= "$db/$area.lt";

# print "<pre>\n";
    my %DOCS_pre= ();
    my $cnt= &deref ($lt, \%DOCS_pre, @words);
    # print "$area/$field cnt=$cnt\n";

    my %DOCS;
    my $doc;
    my $hits= 0;
    foreach $doc (keys %DOCS_pre)
    {
      my $flag= $DOCS_pre{$doc};
      # printf (">>> doc=%10d flag=%02X fields=%02X\n", $doc, $flag, $fields);

      if ($flag & $fields)
      {
        $DOCS{$doc}= 1;
        $hits++
      }
    }

    # print "DOCS: %DOCS, ", join (' ', keys %DOCS), "\n";
    # print "</pre>\n";
    if ($par{'grouping'} eq 'cats')
    {
      %SORT= ();
      # print "hits=$hits\n";
      if ($hits)
      {
        &lookup_catalog ($area, $catalog, $catalog_lut, \%DOCS, \%SORT);
        &display_results ($area, \%SORT);
      }
    }
    else
    {
      if ($hits)
      {
        &lookup_catalog ($area, $catalog, $catalog_lut, \%DOCS, \%SORT);
        $total_hits += $hits;
      }
    }
  }

  if ($par{'grouping'} eq 'none' && $total_hits)
  {
    &display_results ('all categories', \%SORT);
  }
}

if ($ENV{'GATEWAY_INTERFACE'})
{
  print <<EO_HTML;
</body>
</html>
EO_HTML
}
exit (0);

# ----------------------------------------------------------------------------
sub lookup_catalog
{
  my $category= shift;
  my $catalog= shift;
  my $catalog_lut= shift;
  my $results= shift;
  my $SORT= shift;

  my @idx= keys %$results;
  return 0 unless ($#idx >= 0);

  my $tfb= tfb::new_TFB_HANDLE ($catalog, $catalog_lut);
  my $idx;
  foreach $idx (@idx)
  {
    my $res= tfb::tfb_fetch_entry2 ($tfb, $idx);
    my ($docid, $ts_fnm, $ts_lmd, $ts_rcs, $fnm, $title)= split (':', $res, 6);
    my ($artist, $dtitle)= split (/\s*\/\s*/, $title, 2);
    $SORT->{$artist}->{$dtitle}->{$docid}= $fnm;
  }
}

# ----------------------------------------------------------------------------
sub lookup_catalog_bin
{
  my $category= shift;
  my $catalog= shift;
  my $catalog_lut= shift;
  my $results= shift;
  my $SORT= shift;

  # open (CAT, $catalog) || return -1;
  my @idx= keys %$results;
  return 0 unless ($#idx >= 0);
  my $cmd= "$tfbget $catalog " . join (' ', @idx);
  print "<pre>cmd: $cmd\n";
  open (CAT, "$cmd|") || die;
  while (<CAT>)
  {
    chop;
    my ($docid, $ts_fnm, $ts_lmd, $ts_rcs, $fnm, $title)= split (':', $_, 6);
    my ($artist, $dtitle)= split (/\s*\/\s*/, $title, 2);
    $SORT->{$artist}->{$dtitle}->{$docid}= $fnm;
  }
  close (CAT);
  1;
}

# ----------------------------------------------------------------------------
sub display_results
{
  my $category= shift;
  my $SORT= shift;

  my ($fnm, $title, $artist, $dtitle);
  if ($fmt eq 'html')
  {
    print <<EO_HTML;
<h2>$category</h2>
<table border=0>
EO_HTML
# <tr><th>Title</th></tr>
  }

  foreach $artist (sort keys %$SORT)
  {
    my $r1= $SORT->{$artist};

    foreach $dtitle (sort keys %$r1)
    {
      my $r2= $r1->{$dtitle};

      my @docid_list= (sort keys %$r2);
      my $docid= shift (@docid_list);
      my $fnm= $r2->{$docid};

      my @path= split ('/', $fnm);
      my $cddb_id= pop (@path);
      my $area= pop (@path);

      printf ("<tr><td><a href=\"$FMT?cat=%s&id=%s\">%s / %s</a><br>",
              $area, $cddb_id, $artist, $dtitle);

      my $seq= 2;    # the first item is displayed above!
      foreach $docid (@docid_list)
      {
        $fnm= $r2->{$docid};

        @path= split ('/', $fnm);
        $cddb_id= pop (@path);
        $area= pop (@path);
        printf ("<a href=\"$FMT?cat=%s&id=%s\"><font size=-1>%d</font></a>&nbsp;\n", $area, $cddb_id, $seq++);
      }
      print "<br>" if (@docid_list);

      # end-processing for artist/title-pair

      if ($fmt eq 'plain')
      {
        print "\n";
      }
      elsif ($fmt eq 'html')
      {
        print "<br></tr>\n";
      }
    }
  }

  if ($fmt eq 'html')
  {
    print <<EO_HTML;
</table>
EO_HTML
  }
}

# ----------------------------------------------------------------------------
# old deref interface using the deref binary
sub deref_bin
{
  my $lt= shift;
  my $DOCS= shift;    # hash of (document-number, hit-count)
  my $res;
  
  my $cmd= "$deref -l$lt -eand '". join ("' '", @_). "'";

  # print "<pre>\n";
  # print "cmd: $cmd\n";
  open (DEREF, "$cmd|") || return undef;
  while (<DEREF>)
  {
    chop;
    # print $_, "\n";
    if (/^hit:\s+(\d+)\s+(\d+)\s+0x([A-Fa-f\d]+)\s+0x([A-Fa-f\d]+)/)
    {
      my ($hits, $doc_id, $loc_ptr, $loc_code)= ($1, $2, $3, $4);
      $res += $hits;
      $DOCS->{$doc_id}= hex ($loc_code);
    }
  }
  # print join (', ', keys %$DOCS), "\n";
  close (DEREF);
  $res;
}

# ----------------------------------------------------------------------------
sub deref
{
  my $lt= shift;
  my $DOCS= shift;    # hash of (document-number, hit-count)
  my @words= @_;      # search words;

  my $res;
  my $lmdqs;
  unless (defined ($lmdqs= $LMDQS_cache{$lt}))
  {
    $lmdqs= $LMDQS_cache{$lt}= tfb::new_LMDQS ($lt);
  }

  # print "<pre>\n";
  # print "deref: lt='$lt' lmdqs='$lmdqs'\n";
  my $word;
  foreach $word (@words)
  {
    my $wrl= tfb::lmd_deref1 ($lmdqs, $word, 3, 100);
    # print "wrl=$wrl\n";
    next unless (defined ($wrl));
    # print "string= ", tfb::WRL_string ($wrl), "\n";

    my $dil= tfb::WRL_DIL ($wrl);
    # tfb::lmd_print_document_info_list_stdout ($dil);
    for (; $dil; $dil= tfb::DIL_next ($dil))
    {
      my $id= tfb::DIL_document_id ($dil);
      my $cnt= tfb::DIL_hit_count ($dil);
      my $pos= tfb::DIL_pos ($dil, 0); 
      # print "id=$id cnt=$cnt pos=$pos\n";

      $res++;  # where is the hits counter?
      $DOCS->{$id}= hex ($pos);
    }
  }
  $res;
}
