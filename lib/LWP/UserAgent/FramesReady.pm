################################################################################
# LWP::UserAgent::FramesReady -- set up an environment for tracking frames
# and framesets
#
# $Id: FramesReady.pm,v 1.13 2002/04/19 17:03:30 ewippre Exp $
################################################################################

package LWP::UserAgent::FramesReady;
use LWP::UserAgent;
use vars qw/$VERSION/;
@ISA = qw(LWP::UserAgent);

use HTTP::Response::Tree;
use HTML::TokeParser;
use LWP::Debug ();

$VERSION = sprintf("%d.%03d", q$Revision: 1.13 $ =~ /(\d+)\.(\d+)/);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  LWP::Debug::trace('()');
  my $self = $class->SUPER::new();
  bless ($self, $class);
  $self->max_depth(3);
  return $self;
}

=head1 NAME

LWP::UserAgent::FramesReady - a frames-capable version of LWP::UserAgent

=head1 SYNOPSIS

use LWP::UserAgent::FramesReady;

$ua = new LWP::UserAgent::FramesReady;

$response = $ua->request($http_request);

=head1 DESCRIPTION

LWP::UserAgent::FramesReady is a version of LWP::UserAgent that is smart
enough to recognize the presence of frames in HTML and load them
automatically.

Because a framed HTML page actually consists of several HTML pages and
requires more than one HTTP response, LWP::UserAgent::FramesReady
returns framed pages as HTTP::Response::Tree objects.  Responses that
don't have the Content-type of 'text/html' or have a return code < 400
are still returned as HTTP::Response objects as frames processing is
probably not valid for them. B<Note:> a
$response->isa('HTTP::Response::FramesReady') type check should be
done before attempting to use this modules methods.

=head1 METHODS

LWP::UserAgent::FramesReady inherits most of its methods from
LWP::UserAgent.  The following method is changed from the LWP::UserAgent
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
redirects, etc.), this will attempt to follow frames if it detects an HTML
page that contains them.  All responses collected as a result of following
frames will be returned in an HTTP::Response::Tree object.

=cut

sub request {
  my $self = shift;

  # Try a different approach..  we already know to call ourselves with
  # the proper number of parameters.
  return $self->SUPER::request(@_) if scalar @_ > 1;

  LWP::Debug::trace('('.join(',',@_).')');

  if (scalar @_ > 1) {
    warn "request() called with more than one param; "
      . "the extras will be ignored";
  }
  unless (eval{$_[0]->isa('HTTP::Request')}) {
    warn "request() not called with an HTTP::Request";
    return undef;
  }

  my $req = shift;
  my $tree = $self->SUPER::request($req);

  # Don't track frames for possible redirects, 404 error pages even if framed.
  # Also, provision is made to skip RobotUA subrequests for robot rules.
  return $tree if $tree->code >= 400 || $tree->request->uri =~ /robots.txt$/;

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
      my $child = $parent->add_child($self->SUPER::request($request));
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
    my $nurl = URI->new_abs($frm->[1]{'src'}, $base_path);
    push @uris, $nurl;
  }
  $p = HTML::TokeParser->new(\$response->content);
  while (my $tag = $p->get_tag('iframe')) {
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
