#!/usr/bin/perl -t
#
# Check GET via HTTP.
#

print "1..10\n";

use LWP::UserAgent::FramesReady;
use HTTP::Response::Tree;
use LWP::Protocol ();

LWP::Protocol::implementor(http => 'myhttp');

my $ua = LWP::UserAgent::FramesReady->new;    # create a useragent to test
$ua->callbk(undef);
# $ua->proxy('ftp' => "http://www.sn.no/");

$req = HTTP::Request->new(GET => 'http://www.foo.com/');
$req->header(Cookie => "perl=cool");

$res = $ua->request($req);

print $res->as_string;

my $tree_good = 0;
if ($res->is_success and $res->isa('HTTP::Response::Tree')) {
  $tree_good = 1;
} else {
  print "not ";
}
print "ok 4\n";

unless ($tree_good and scalar $res->descendants == 2) {
  print "not ";
}
print "ok 5\n";
unless ($tree_good and scalar $res->children == 2) {
  print "not ";
}
print "ok 6\n";

unless ($tree_good and $res->max_depth == 3 ) {
  print "not ";
}
print "ok 7\n";

if ($tree_good) {
  @childrn = $res->children;
  $chld = shift @childrn;
  unless ($chld->max_depth == 2) {
    print "not ";
  }
  print "ok 8\n";
  unless ($chld->code == 200) {
    print "not ";
  }
  print "ok 9\n";
  $chld = shift @childrn;
  unless ($chld->code == 200) {
    print "not ";
  }
  print "ok 10\n";
} else {
  for (6..8) {
    print "not ok $_\n";
  }
}

#----------------------------------
package myhttp;

BEGIN {
   @ISA=qw(LWP::Protocol);
}

our $cntr;

sub new
{
  my $class = shift;
  print "CTOR: $class->new(@_)\n";
  my($prot) = @_;
  print "not " unless $prot eq "http";
  $cntr++;
  print "ok $cntr\n";
  my $self = $class->SUPER::new(@_);
  for (keys %$self) {
    my $v = $self->{$_};
    $v = "<undef>" unless defined($v);
    print "$_: $v\n";
  }
  $self;
}

sub request
{
  my $self = shift;
  print "REQUEST: $self->request(",
    join(",", (map defined($_)? $_ : "UNDEF", @_)), ")\n";

  my($request, $proxy, $arg, $size, $timeout) = @_;
  my $data;
  my $data1 = q!<HTML>
<HEAD>
<TITLE>Coolpics</TITLE>
<META NAME="keywords" CONTENT="Free,xxx,Movies,Pics,Pic,Bilder,pics,pic,Tumbs">
<META NAME="description" CONTENT="Free Pics,Movies,Babes,TeensEbony">
<META NAME="robots" CONTENT="INDEX, FOLLOW">
<META NAME="revisit-after" CONTENT="10 days">
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=iso-8859-1">
<script language="JavaScript">
if(top.frames.length > 0)
top.location.href=self.location;
</script>
</HEAD>

<FRAMESET ROWS="100%,*" FRAMEBORDER="NO" BORDER="0" FRAMESPACING="0">
<FRAME NAME="main_frame1" SRC="/frame1">
<FRAME NAME="main_frame2" SRC="/frame2">
</FRAMESET>

<NOFRAMES>
<BODY bgcolor="#FFFFFF" text="#000000">
<a href="/noframe"> No Frames</a>
</BODY>
</NOFRAMES>
</HTML>
!;

my $data2 = q!<HTML>
<HEAD>
<TITLE>Frame1</TITLE>
<META NAME="keywords" CONTENT="Free,xxx,Movies,Pics,Pic,Bilder,pics,pic,Tumbs">
<META NAME="description" CONTENT="Free Pics,Movies">
<META NAME="robots" CONTENT="INDEX, FOLLOW">
<META NAME="revisit-after" CONTENT="10 days">
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=iso-8859-1">
<script language="JavaScript">
if(top.frames.length > 0)
top.location.href=self.location;
</script>
</HEAD>

<BODY BGCOLOR="#FFFFFF" TEXT="#000000">
<a href="http://localhost:80/cgi-bin/lwp/frame1"> 1 Frame </a>
</BODY>
</HTML>
!;

my $data3 = q!<HTML>
<HEAD>
<TITLE>Frame2</TITLE>
<META NAME="keywords" CONTENT="Free,xxx,Movies,Pics,Pic,Bilder,pics,pic,Tumbs">
<META NAME="description" CONTENT="Free Pics,Movies">
<META NAME="robots" CONTENT="INDEX, FOLLOW">
<META NAME="revisit-after" CONTENT="10 days">
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=iso-8859-1">
<script language="JavaScript">
if(top.frames.length > 0)
top.location.href=self.location;
</script>
</HEAD>

<BODY BGCOLOR="#FFFFFF" TEXT="#000000">
<a href="http://localhost:80/cgi-bin/lwp/frame2"> 1 Frame </a>
</BODY>
</HTML>
!;
  print $request->as_string;

  my $res = HTTP::Response::Tree->new();
  $res->code(200);
  $res->content_type("text/html");
  $res->date(time);
  if ($request->{_uri} =~ /frame1/) {
    #       print "ok 6\n";
    $data = $data2;
  } elsif ($request->{_uri} =~ /frame2/) {
    #       print "ok 7\n";
    $data = $data3;
  } else {
    #       print "ok 5\n";
    $data = $data1;
  }
  $self->collect_once($arg, $res, "$data\n");
  $res;
}
