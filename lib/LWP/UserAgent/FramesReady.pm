################################################################################
# LWP::UserAgent::FramesReady -- set up an environment for tracking frames
# and framesets
#
# $Id: FramesReady.pm,v 1.16 2004/03/06 05:26:39 aederhaag Exp $
################################################################################
# Allow POST to be redirected as well

package LWP::UserAgent::FramesReady;
use LWP::UserAgent;
use URI::URL;
use vars qw/$VERSION @redirects/;
@ISA = qw(LWP::UserAgent);

use HTTP::Response::Tree;
use HTML::TokeParser;
use LWP::Debug ();

@redirects = ('GET', 'HEAD', 'POST');
$VERSION = sprintf("%d.%03d", q$Revision: 1.16 $ =~ /(\d+)\.(\d+)/);

# constant for checking for a valid schema
our @schema = ('http', 'ftp', 'nntp', 'gopher', 'wais', 'news', 'https');

sub new {
  my ($class, $cnf) = @_;

  LWP::Debug::trace('()');
  my $callback = delete $cnf->{callback};
  $callback = \&LWP::UserAgent::FramesReady::callback unless defined $callback;
  my $size = delete $cnf->{size};
  $size = 8192 unless defined $size;
  my $nomax = delete $cnf->{nomax};
  $nomax = 0 unless defined $nomax;
  my $self = $class->SUPER::new();
  my $credent = delete $cnf->{credent};
  $credent = '' unless defined $credent;
  $self->{callback} = $callback;
  $self->{size} = $size;
  $self->{nomax} = $nomax;
  $self->{credent} = $credent;
  $self->requests_redirectable(\@redirects) if @redirects;
  $self->max_depth(3);

  bless ($self, $class);
  return $self;
}

=head1 NAME

LWP::UserAgent::FramesReady - a frames-capable version of LWP::UserAgent

=head1 SYNOPSIS

 use LWP::UserAgent::FramesReady;

 $ua = new LWP::UserAgent::FramesReady;
 $ua = new LWP::UserAgent::FramesReady({'callback'=>\&callback
      [,'size'=>$size]});
 $ua = new LWP::UserAgent::FramesReady({'nomax'=>1,
      'callback'=>\&LWP::UserAgent::FramesReady::callback
      [,'size'=>$size]});

 $response = $ua->request($http_request);

=head1 DESCRIPTION

LWP::UserAgent::FramesReady is a version of LWP::UserAgent that is smart
enough to recognize the presence of frames in HTML and load them
automatically.

The subroutine variant requires a hash reference to a callback routine
that is supplied to the request to process the content in chunks to
look for, for instance, immediate refreshes and alter them to be
redirects which LWP::UserAgent->request will follow out as it does all
other redirects.  If size (supplied as an additional hash element) is
supplied it will be the suggested chunk size.  If the subroutine
variant is requested without a size, the size will default to 8K.  The
default is to use the callback() function defined with the class
object.

The LWP::UserAgent::FramesReady::callback is supplied as the default
callback routine and the $cnf->{'nomax'} can be supplied and used by that
routine to enforce truncation of received content even if the request
to do so is not honored by the server called for the content.

To override the default behavior and not use an actual callback, the
$ua->callbk should be called supplying 'undef' as the subroutine to
use as in '$ua->callbk(undef)'.  Not defining a code ref will default
to the callback defined here.

Because a framed HTML page actually consists of several HTML pages and
requires more than one HTTP response, LWP::UserAgent::FramesReady
returns framed pages as HTTP::Response::Tree objects.  Responses that
don't have the Content-type of 'text/html' or have a return code < 400
are still returned but as HTTP::Response objects as frames processing
is probably not valid for them. B<Note:> a
$response->isa('HTTP::Response::FramesReady') type check should be
done before attempting to use this module's methods.

=head1 METHODS

LWP::UserAgent::FramesReady inherits most of its methods from
LWP::UserAgent.  The following method overrides the LWP::UserAgent
version:

=over 4

=item $ua->request($request)

This behaves like LWP::UserAgent's request method, except that it
takes only one parameter (an HTTP::Request object as usual).  Further
parameters may generate a warning and be ignored.  Such attempts
usually are due to a proxy request, redirect override, authentication
or moved file condition that the base class function can handle
properly, anyway.

In addition to request()'s usual behavior (authenticating, following
redirects, etc.), this will attempt to follow frames if it detects an
HTML page that contains them.  All responses collected as a result of
following frames will be returned in an HTTP::Response::Tree object
except as denoted above.

=cut

sub request {
  my $self = shift;

  # Try a different approach..  we already know to call ourselves with
  # the proper number of parameters.
  if (scalar @_ > 3){
    LWP::Debug::trace('(' . join(',',@_) . ')');
    LWP::Debug::debug("Called with more than three params; "
		      . "LWP::UserAgent::request will be used instead");
    return $self->SUPER::request(@_);
  }

  my $req = shift;
  unless (eval{$req->isa('HTTP::Request')}) {
    warn "request() not called with an HTTP::Request";
    return undef;
  }

#  Just throw away any other parameters
#    if (defined($_[0]) && ref ($_[0]) eq 'CODE') {
#      shift; shift;		# Remove callback and size
#    }

  my $tree = $self->SUPER::request($req, $self->{callback}, $self->{size});

  # Don't track frames for possible redirects or 404 error pages
  #  or LWP::RobotUA robot configuration files
  return $tree if $tree->code >= 400 || $tree->code < 200 ||
    $tree->request->uri =~ /robots.txt$/;

  # Only valid to track frames in HTML or SHTML--use HTTP::Headers method
  return $tree unless $tree->content_type =~ m#text/html#;

  $tree = HTTP::Response::Tree->new($tree) unless
    $tree->isa('HTTP::Response::Tree');
  $tree->max_depth($self->max_depth);

  my @resp_queue = ($tree);
  my $parent;
  while ($parent = shift @resp_queue) {
    next unless $parent->max_depth;
    my @children = $self->_extract_frame_uris($parent);
    foreach (@children) {
      my $request = $parent->request->clone;
      $request->uri($_);
      $request->headers->{'pragma'} = 'no_wait';
      my $child = $parent->add_child($self->SUPER::request($request,
							   $self->{callback},
							   $self->{size}));
      if ($child) {
	push @resp_queue, $child;
      } else {
	LWP::Debug::debug("add_child failed");
      }
    }
  }
  return $tree;
}

sub _extract_frame_uris {
  my $self = shift;
  my $response = shift;
  my $base_path = $response->request->uri;
  my @uris = ();

  my $p = HTML::TokeParser->new(\$response->content);
  while (my $frm = $p->get_tag('frame')) {
    next unless $self->valid_scheme($frm->[1]{'src'});
    my $nurl = URI->new_abs($frm->[1]{'src'}, $base_path);
    push @uris, $nurl;
  }
  $p = HTML::TokeParser->new(\$response->content);
  while (my $tag = $p->get_tag('iframe')) {
    next unless $self->valid_scheme($tag->[1]{'src'});
    my $nurl = URI->new_abs($tag->[1]{'src'}, $base_path);
    push @uris, $nurl;
  }
  return @uris;
}

=back 4

The following method is new:

=over 4

=item $ua->max_depth([$depth])

This gets or sets the maximum depth that the user agent is allowed to go
to fetch framed pages.  0 means it will not fetch any frames, 1 means it
will fetch only the frames for the topmost page and not any sub-frames,
and so on.  The default is 3.

=cut

sub max_depth {
  my $self = shift;
  my $depth = shift;

  if (defined($depth)) {
    $self->{_luf_max_depth} = int($depth);
  }
  return $self->{_luf_max_depth};
}


=item $ua->callbk([\&callback])

Get/set the callback subroutine to use to process input as it is
gathered.  This causes the input to be chunked and the routine must
either process the data itself or append it to the
$response->{_content} in order for the final content to be processed
all at one time.

=item $ua->size([$size])

Get/Set the size suggested for chunks when the callback routine is used.

=item $ua->credent([$credentials])

Get/set the credentials for authentification if called for.

=cut

sub callbk   { shift->_elem('callback', @_); }
sub size     { shift->_elem('size', @_); }
sub nomax    { shift->_elem('nomax', @_); }
sub credent  { shift->_elem('credent', @_); }

=item callback()

The callback routine is a sample of how to revise the way the
immediate refresh responses are processed by converting them into
redirects.  Since the routine is called whenever there is chunked
response data available by use of the alternate
LWP::UserAgent::request() method, and we only change headers for
immediate refreshes.  We must also deal with the fact that the
callback was originally designed for processing the content.  The
$resp->{_content} field must have the unprocessed data element
appended back in..  appended, as this data is chunked and there may
already be content from a previous chunk that was processed.

=cut

sub callback {
  my ($data, $resp, $proto) = @_;

  # LWP::UserAgent should be populating the refresh header process it here
  if (exists($resp->headers->{'refresh'})) {
    if ($resp->headers->{'refresh'} =~ /^[0-9];.*URL=([^">]+)/is) {
      my $url = $1;
      unless ($url =~ /^(file|java|vb)/is ) {
          delete $resp->headers->{'refresh'};
          $resp->headers->{'location'} = $url;
          $resp->code(&HTTP::Status::RC_MOVED_TEMPORARILY);
      }
    }
  } elsif ($data =~ /HTTP-EQUIV=\"?REFRESH\"? CONTENT=\"?\s?[0-9];.*URL=([^">]+)/is){
    # if headers->{refresh} was not generated (in content instead of header)
    my $loc = $1;
    unless ($loc =~ /^(file|java|vb)/is ) {
	delete $resp->headers->{'refresh'} if
	    exists $resp->headers->{'refresh'};
	$resp->headers->{'location'} = $loc;
	$resp->code(&HTTP::Status::RC_MOVED_TEMPORARILY);
    }
  }

  # Fixup to correct override by server for request for max bytes
  # Servers have no compulsion to follow the request but if we made it
  # want it enforced here unless told otherwise
  if (defined($resp->request->headers->{'range'}) && ! $self->{nomax}) {
    my ($maxs) = $resp->request->headers->{'range'} =~ /bytes=0-(.*)/;
    if ($maxs && length($resp->content) > $maxs) {
      $data = '';
      if ($resp->code ne &HTTP::Status::RC_PARTIAL_CONTENT) {
	  $resp->headers->{'content-length'} = length($resp->content);
	  $resp->code(&HTTP::Status::RC_PARTIAL_CONTENT);
	  $resp->{_msg} = HTTP::Status::status_message($resp->code);
      }
    }
  }

    # We must restore the _content since the parent assumes we deal with it
  $resp->{_content} .= $data;
  return undef;
}

=item $ua->valid_scheme()

The valid_scheme validates the frame src entry to scheme types we can
process.  If LWP::Debug is set, there will be reporting of the reason
for skipping this entry.

=cut

sub valid_scheme ($) {
  my $self   = shift;
  my $urlchk = shift;
  my $scheme = '';

  if ($urlchk =~ s/^([^:]*)://) {
    $scheme = lc($1);
  }

  if ($scheme && ! grep {$scheme eq $_} @schema) {
    LWP::Debug::debug("Invalid scheme [$scheme]");
    return 0;
  }

  return 1;
}

=item $ua->get_basic_credentials()

This routine overloads the LWP::UserAgent::get_basic_credentials in
order to supply authorization if it has been pre-loaded an initial/new
or by use of the $ua->credent() routine.  Supplies a return in a list
context of a UserID and a Password to LWP::UserAgent::credentials().

=cut

sub get_basic_credentials {
  my($self, $realm, $uri) = @_;
  if ($self->{credent}) {
    LWP::Debug::debug("Credent: $realm (", $uri->as_string, ")");
    return split(':', $self->{credent}, 2);
  } else {
    return (undef, undef);
  }
}

=back

=head1 NOTES

Processing other embedded objects in an HTML page is similar to processing
frames.  Perhaps someday there will be yet another version of this that
can also handle things like in-line images, layers, etc.

=head1 BUGS

Any known bugs will be noted here and documented in the source with "BUG:"
in the comments.

=head1 COPYRIGHT

Copyright 2002 N2H2, Inc.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
