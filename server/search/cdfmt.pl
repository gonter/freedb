#!/usr/local/bin/perl
# FILE %gg/work/fbsd/gg-data/recordings/cdfmt.pl
#
# written:       2001-01-28
# latest update: 2001-01-28 16:00:25
# $Id: cdfmt.pl,v 1.1 2002/07/02 06:07:27 gonter Exp $
#

use strict;
use Net::freedb::file;
use Net::freedb::tools;

# configure this
my $db_base= 'http://whisky.wu-wien.ac.at/freedb/db';
my $my_url=  'http://whisky.wu-wien.ac.at/cgi-bin/cdfmt';
my $base=    '/archive/cddb/db';

# initialization
my @cats= qw(blues classical country data folk jazz
 misc newage reggae rock soundtrack);

my $cat= 'undef';
my $fmt= 'plain';

my @IDS= ();
my $arg;
while ($arg= shift (@ARGV))
{
     if ($arg eq '-cat') { $cat= shift (@ARGV); }
  elsif ($arg eq '-fmt') { $fmt= shift (@ARGV); }
  else
  {
    push (@IDS, $arg);
  }
}
  # my $fnm= shift || 'd410920f';

if ($ENV{'GATEWAY_INTERFACE'})
{
  my $parameter_list= $ENV{'QUERY_STRING'} if ($ENV{'QUERY_STRING'});

  if ($ENV{'CONTENT_LENGTH'})
  {
    my $sollen= $ENV{'CONTENT_LENGTH'};
    my $len= read(STDIN, $parameter_list, $sollen);
  }
  my @av_pair= split(/&/, $parameter_list);
  my $av_pair;
  my %par;
  foreach $av_pair (@av_pair)
  {
    my ($av_name, $av_val)= split(/=/, $av_pair);
    $av_val=~ tr/+/ /;
    $av_val=~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    $par{$av_name}= $av_val;
  }

  # ------------------
  $cat= $par{'cat'};
  push (@IDS, split (' ', $par{'id'}));

  $fmt= 'html';
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
EO_HTML
}

foreach $arg (@IDS)
{
  &show_data ($fmt, $cat, $arg);
}

if ($ENV{'GATEWAY_INTERFACE'})
{
  print <<EOX;
</body>
</html>
EOX
}
exit (0);

# ----------------------------------------------------------------------------
sub show_data
{
  my $fmt= shift;
  my $cat= shift;
  my $id= shift;

  my $fnm= "$base/$cat/$id";

  my $db= new Net::freedb::file;
  $db->read ($fnm);

  my $cnt= $db->track_count;
  my $tt= 75 * $db->length;   # unfortunately, we do not have disc length in frames!
  my ($tt_m, $tt_s, $tt_f)= Net::freedb::tools::offset2time ($tt);
  my $md5= Net::freedb::tools::get_exp_id ($db);

  if ($fmt eq 'plain')
  {
    print $db->title, "\n";
    printf ("tracks: %2d tt: %2d:%02d\n", $cnt, $tt_m, $tt_s);
    print   "cddbid: ", join (',', @{$db->discids}), "\n";
    printf ("exp_id: %s\n", $md5);
  }
  elsif ($fmt eq 'html')
  {
    print "<h2>", $db->title, "</h2>\n";
    printf ("tracks: %2d<br>\ntotal time: %2d:%02d<br>\n",
            $cnt, $tt_m, $tt_s);
    printf ("year: %s<br>\n", $db->dyear);
    printf ("genre: %s<br>\n", $db->dgenre);
    printf ("ids: %s /", $cat);
    my $x;
    foreach $x (@{$db->discids})
    {
      print " <a href=\"$db_base/$cat/$x\">$x</a>\n";
    }
    printf ("<br>\nalternative cats: ");

    foreach $x (&find_cats ($cat, $id))
    {
      print " <a href=\"$my_url?cat=$x&id=$id\">$x</a>\n";
    }

    printf ("<br>\nexp_id: %s\n", $md5);

    my $db_ext= $db->ext ();
    if ($db_ext)
    {
      print "<br><hr><center><table width=\"98%\"><tr><td bgcolor=\"#E8E8E8\"><pre>\n",
            &text2html ($db_ext), "</pre></tr></td></table></center>\n";
    }

    print <<EO_HTML;
<hr>
<table border=0>
EO_HTML
# <tr><th>Track</th><th>time</th><th>title</th></tr>
  }

  my ($i, $track_more);
  for ($i= 0; $i < $cnt; $i++)
  {
    my $track= $db->track ($i); # returns a Net::freedb::track object
    my $next_track= $db->track ($i+1);

    my $off= $track->offset;
    my ($m, $s, $f)= Net::freedb::tools::offset2time ($off);
    my $off_next= (defined ($next_track)) ? $next_track->offset : $tt;
    my $duration= $off_next - $off;
    my $duration= 75 * int (($duration+37) / 75); # round to nearest seconds
    my ($d_m, $d_s, $d_f)= Net::freedb::tools::offset2time ($duration);

    my $track_num= $i+1;
    if ($fmt eq 'plain')
    {
      printf ("[%2d] %2d:%02d.%02d %s\n",
              $track_num, $d_m, $d_s, $d_f, $track->title);
    }
    elsif ($fmt eq 'html')
    {
      my $ext= $track->ext ();
      my ($ext_link1, $ext_link2);
      if ($ext && 0)
      {
        $ext= &text2html ($ext);
        $track_more .= <<EO_HTML;
<h2><a name="Track$track_num">Track $track_num</h2>
EO_HTML
        $track_more .= $ext;

        $ext_link1= "<a href=\"#Track$track_num\">";
        $ext_link2= "</a>";
      }

      printf ("<tr><td valign=top>%2d.</td><td valign=top>%2d:%02d</td><td><b>%s%s%s</b>\n",
              $track_num, $d_m, $d_s,
              $ext_link1, $track->title, $ext_link2);

      if ($ext && 1)
      {
        $ext= &text2html ($ext);
        print "<br>\n<font size=small>", $ext, "</font>\n";
      }

      print "<br><br></td></tr>\n";
    }
  }

  if ($fmt eq 'html')
  {
    print <<EO_HTML;
</table>
<hr>
EO_HTML
    if ($track_more)
    {
      print '<pre>', $track_more, "</pre>\n<hr>\n";
    }
  }
}

# ----------------------------------------------------------------------------
sub text2html
{
  my $ext= shift;

    $ext=~ s/&/&amp;/g;
    $ext=~ s/</&lt;/g;
    $ext=~ s/</&gt;/g;
    $ext=~ s#(http:[^, \r\n]+)#<a href="$1">$1</a>#g;

  $ext;
}

# ----------------------------------------------------------------------------
sub find_cats
{
  my $cat1= shift;
  my $id= shift;
  my $cat;
  my @res= ();
  foreach $cat (@cats)
  {
    next if ($cat eq $cat1);
    my $fnm= join ('/', $base, $cat, $id);
    push (@res, $cat) if (-f $fnm);
  }
  @res;
}
