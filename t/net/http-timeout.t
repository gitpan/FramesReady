#
# Check timeouts via HTTP.
#

print "1..1\n";

require "net/config.pl";
require HTTP::Status;
require LWP::Protocol::http;
require LWP::UserAgent::FramesReady;
require URI;

my $ua = new LWP::UserAgent::FramesReady;    # create a useragent to test

$ua->timeout(4);

$netloc = $net::httpserver;
$script = $net::cgidir . "/timeout";

$url = new URI->new("http://$netloc$script");

my $request = new HTTP::Request('GET', $url);

print $request->as_string;

my $response = $ua->request($request, undef);

my $str = $response->as_string;

print "$str\n";

if ($response->is_error and
    $str =~ /timeout/) {
    print "ok 1\n";
}
else {
    print "nok ok 1\n";
}

# avoid -w warning
$dummy = $net::httpserver;
$dummy = $net::cgidir;
