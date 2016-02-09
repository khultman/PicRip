#!/usr/bin/perl -w

use strict;

package rip;

use Carp qw(croak confess);
use Data::Dumper qw(Dumper);
use HTTP::Cookies;
use HTTP::Request::Common qw(GET POST);
use HTML::TreeBuilder;
use LWP::Simple;
use Symbol qw(gensym);
use URI::Split qw(uri_split);

our $AUTOLOAD;
our $VERSION = "0.02";


sub AUTOLOAD
{
  my ($self,$value)= @_ ;
  return if $AUTOLOAD =~ /::DESTROY$/ ;
  (my $attr = $AUTOLOAD) =~ s/.*:://;

  if(! exists $self->{$attr})
  {
    confess("Attribute $attr does not exists in $self");
  }

  my $pkg = ref($self ) ;

  my $code = qq{
    package $pkg ;
    sub $attr {
      my \$self = shift ;
      \@_ ? \$self->{$attr} = shift : \$self->{$attr} ;
               }
       
  };
  eval $code ;
  if( $@ ){
    Carp::confess("Failed to create method $AUTOLOAD : $@");
  }
  goto &$AUTOLOAD ;
}


sub new
{
  my $class = shift;
  my $self = { _class => $class, @_ };
  bless($self);

  $self->sanityCheck();

  $self->{ua} = LWP::UserAgent->new;
  $self->{ua}->agent('Mozilla/8.0');
  $self->{ua}->default_header('Referer' => $self->baseURL());
  $self->{ua}->cookie_jar
  (
    HTTP::Cookies->new
    (
      file => 'cookies.txt',
      autosave => 1
    )
  );

  my ($fID, $tID, $pID) = split(/_|\./, $self->initPage());
  ($self->{fID}, $self->{tID}) = ($fID, $tID);
  ($self->{pID}, $self->{initPageID}) = ($pID, $pID);
 
  return $self;
}


sub sanityCheck
{
  my $self = shift;
  croak "No URL supplied to object" unless defined $self->{url};
  croak "No user supplied to object" unless defined $self->{user};
  croak "No pass supplied to object" unless defined $self->{pass};
}


sub mo2dec
{
  my ($self, $month) = @_;
  my $mo = { qw( Jan 01 Feb 02 Mar 03 Apr 04 May 05 Jun 06 Jul 07 Aug 08 Sep 09 Oct 10 Nov 11 Dec 12 ) };
  croak "Fatal error, bad month: $month", ref($self) unless ( exists $mo->{$month} );
  return $mo->{$month};
}


sub rip
{
  my $self = shift;
  $self->logon();
  #scrapeAllPages();
}


sub logon
{
  my $self = shift;
  ## Self explanitory, the username and password field names
  my $user_field = 'user_usr';
  my $pass_field = 'user_pwd';

  my $req = POST $self->baseURL() . '/index.php', [ $user_field => $self->user(), $pass_field => $self->pass(), 'mode' => 'login', 'queryStr' => '', 'pagetype' => 'index' ];
  my $res = $self->{ua}->request($req);

  ## Add some way to verify logon was successful
  ## Right now it looks like the cookie is getting the logged in status
  ## but the handler returns a 302 'Moved' - not a success
}


# scrapeAllPages($ua)
# $ua = User Agent
sub scrapeAllPages
{
  my $self = shift;
  my $page;
  for (1..87)
  {
    scrapePage($page);
  }
  my $nPages = numPages($page);
}


# scrapePage ( $ua , $page )
# $ua = User Agent object
# $page = Url of the page to scrape
sub scrapePage
{
  my $self = shift;

  my $status = loadPrevStatus($self->page());

  my $req = GET $self->baseURL() . '/' . $self->page();
  my $res = $self->{ua}->request($req);

  my $html = HTML::TreeBuilder->new();
  $html->utf_mode(1);
  $html->parse($res->content());

  my $trc = 1;
  my $trd;
  foreach my $tr ( $html->look_down( sub { $_[0]->attr('_tag') =~ /tr/i && defined $_[0]->attr('class') && $_[0]->attr('class') =~ /tbCel[12]/ } ) )
  {
    my $html = $tr->look_down( _tag => 'td')->right->look_down( _tag => 'span' )->as_HTML();
    my $date;
    if ( $html =~ m/(?:.*middot;\s+)(\d+)&nbsp;(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)&nbsp;(\d{4})/ )
    {
      $date = sprintf("%4d%02d%02d", $3, $self->mo2dec($2), $1);
    }
    else
    {
      croak "Couldn't split date string from the post, page layout may have changed\nHTML: $html\n";
    }

    foreach my $link ( @{ $tr->look_down( _tag => 'div', 'class' => 'postedText' )->extract_links( 'a'  ) } )
    {
      if ( exists( $trd->{$date} ) ) { $trd->{$date}++ } else { $trd->{$date} = 1 }
      my $fn = sprintf("%d-%d_%8d-%03d.JPG", $fID, $tID, $date, $trd->{$date});
#      getPicture($ua, $fn, $link->[0]);
    }

    $trc++;
  }

}


# getPicture($ua, $fn, $href)
# $ua = User Agent
# $fn = File Name
# $href = Url to grab
sub getPicture
{
  my ($self, $fn, $href) = @_;
  my $req = GET $href;
  my $fh = gensym();
  die unless ( open ( $fh, '>', $fn ) );
  my $res = $self->{ua}->request( $req, sub { print $fh $_[0] } );
  close $fh;
  return 1;
}


# saveStatus($status)
# $status = hash to write to disk
sub saveStatus
{
  my ($self, $status) = @_;
  my $fn = $0 . '.log';
  local $Data::Dumper::Terse = 1; 
  local $Data::Dumper::Indent = 0;
}


sub loadPrevStatus
{
  my ($self, $page) = @_;
  my ($fID, $tID, $pID) = split(/_|\./, $page);
  next if $pID eq "1";
}


sub baseURL
{
  my $self = shift;
  unless ( exists $self->{baseURL} )
  {
    my ($scheme,$auth,$path,$query,$frag) = uri_split($self->url());
    $self->{baseURL} = $auth;
    ($self->{initPage} = $path) =~ s/^\///;
  }
  return $self->{baseURL};
}  


sub lastPage
{
  my $self = shift;

  if (exists $self->{lastPage})
  {
    return $self->{lastPage};
  }

  ($self->{curPage}, $self->{lastPage}) = 0;
  my $req = GET $self->url();
  my $res = $self->{ua}->request($req);

  #my $html = HTML::TreeBuilder->new_from_content($res->content());
  my $html = HTML::TreeBuilder->new();
  $html->utf8_mode(1);
  $html->parse($res->content());
  my $pages = $html->look_down( 'class' => 'pageGif', 'title' => 'Page' )->right();

  if ( $pages =~ /.*\s+(\d+)\s+of\s+(\d+).*/ )
  {
    ($self->{curPage}, $self->{lastPage}) = ($1, $2);
  }
  else
  {
    croak "Could not identify page position, something on the page must have changed!\n";
  }
  return $self->{lastPage};
}


sub nextPage
{
  my $self = shift;
  return 0 if ($self->pID() == $self->lastPage());
  $self->pID($self->pID + 1);
  return $self->page();
}


sub page
{
  my $self = shift;
  my $page = sprintf("%d_%d_%d.html", $self->fID(), $self->tID(), $self->pID());
  return $page;
}

1;

package main;

use Getopt::Long;
use Pod::Usage;
use Term::ReadKey;

my %opts;
GetOptions
(
  \%opts,
  "help|h|?",
  "user|u=s",
  "pass|p=s",
  "url=s",
)
or pod2usage(2);
pod2usage(1) if defined ($opts{'help'});
pod2usage(2) if not defined ($opts{'user'});
if (!defined $opts{'pass'})
{
  print "Enter Password:";
  ReadMode("noecho");
  chomp($opts{'pass'} = <>);
  ReadMode("original");
  print "\n";
}
#pod2usage(2) if not defined ($opts{'pass'});
pod2usage(2) if not defined ($opts{'url'});
my $ripper = new rip(%opts); 
print "Last Page: " . $ripper->lastPage() . "\n";
print "Current page: " . $ripper->page() . "\n";
print "Next page: " . $ripper->nextPage() . "\n";

__END__

=head1 $0

=head1 SYNOPSIS

$0 [options] [URL]

  Options:
    -h | --help              Brief Help message
    -u | --user              Username to use
    -p | --pass              Use a password, optionally use password supplied on command line

=cut
