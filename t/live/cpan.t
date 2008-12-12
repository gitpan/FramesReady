print "1..2\n";

use strict;
use Net::HTTP;


# my $s = Net::HTTP->new(Host => "ftp.activestate.com",
my $s = Net::HTTP->new(Host => "cpan.llarian.net",
		       KeepAlive => 1,
		       Timeout => 15,
		       PeerHTTPVersion => "1.1",
		       MaxLineLength => 512) || die "$@";

for (1..2) {
#     $s->write_request(TRACE => "/libwww-perl",
    $s->write_request(TRACE => "/pub/CPAN",
		      'User-Agent' => 'Mozilla/5.0',
		      'Accept-Language' => 'no,en',
		      'Accept' => '*/*');

    my($code, $mess, %h) = $s->read_response_headers;
    print "$code $mess\n";
    my $err;
    $err++ unless $code eq "200";
    $err++ unless $h{'Content-Type'} eq "message/http";

    my $buf;
    while (1) {
        my $tmp;
	my $n = $s->read_entity_body($tmp, 20);
	last unless $n;
	$buf .= $tmp;
    }
    $buf =~ s/\r//g;

    $err++ unless $buf eq "TRACE /pub/CPAN HTTP/1.1
Host: cpan.llarian.net
User-Agent: Mozilla/5.0
Accept-Language: no,en
Accept: */*

";

    print "not " if $err;
    print "ok $_\n";
}

