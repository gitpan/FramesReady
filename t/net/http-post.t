#!/usr/local/bin/perl -w
#
# Check POST via HTTP.
#

print "1..2\n";

require "net/config.pl";
require LWP::Protocol::http;
require LWP::UserAgent::FramesReady;
require URI;

$netloc = $net::httpserver;
$script = $net::cgidir . "/test";

my $ua = new LWP::UserAgent::FramesReady;    # create a useragent to test

$url = new URI->new("http://$netloc$script");

my $form = 'searchtype=Substring';

my $request = new HTTP::Request('POST', $url, undef, $form);
$request->header('Content-Type', 'application/x-www-form-urlencoded');

my $response = $ua->request($request, undef, undef);

my $str = $response->as_string;

print "$str\n";

if ($response->is_success and $str =~ /^REQUEST_METHOD\s*=\s*POST$/m) {
    print "ok 1\n";
} else {
    print "not ok 1\n";
}

if ($str =~ /^CONTENT_LENGTH\s*=\s*(\d+)$/m && $1 == length($form)) {
    print "ok 2\n";
} else {
    print "not ok 2\n";
}

# avoid -w warning
$dummy = $net::httpserver;
$dummy = $net::cgidir;