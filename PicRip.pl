#!/usr/bin/perl -w

use strict;

package rip;

use Carp qw(cluck croak confess);
use Data::Dumper qw(Dumper);
use HTTP::Cookies;
use HTTP::Request::Common qw(GET POST);
use HTML::TreeBuilder;
use JSON qw(decode_json encode_json);
use LWP::Simple;
use Storable qw(store retrieve);
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
  $self->{ua}->default_header('Referer' => 'http://' . $self->baseURL());
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

  if ($self->{pID} < $self->LPS())
  {
    $self->{pID} = $self->LPS() - 10;
    if ($self->{pID} < 1)
    {
      $self->{pID} = 1;
    }
  }
 
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


sub letItRip
{
  my $self = shift;
  $self->logon();
  do
  {
    $self->scrapePage();
  } while ( $self->nextPage() );
}


sub logon
{
  my $self = shift;
  ## Self explanitory, the username and password field names
  my $user_field = 'user_usr';
  my $pass_field = 'user_pwd';

  my $req = POST $self->index(), [ $user_field => $self->user(), $pass_field => $self->pass(), 'mode' => 'login', 'queryStr' => '', 'pagetype' => 'index' ];
  my $res = $self->{ua}->request($req);

  $req = GET $self->index();
  $res = $self->{ua}->request($req);

  my $html = HTML::TreeBuilder->new();
  $html->utf8_mode(1);
  $html->parse($res->content());

  unless ($html->as_HTML() =~ /.*Signed in as:/)
  {
    confess "Apprerently we're not logged in!", ref($self);
  }

}


sub scrapePage
{
  my $self = shift;

  my $status = $self->loadStatus();

  my $req = GET $self->pageURL();
  my $res = $self->{ua}->request($req);

  my $tree = HTML::TreeBuilder->new();
  $tree->utf8_mode(1);
  $tree->parse($res->content());

  #$status->{$self->tfID()}->{$self->page()}->{tr} = 0;
  foreach my $tr ( $tree->look_down( sub { $_[0]->attr('_tag') =~ /tr/i && defined $_[0]->attr('class') && $_[0]->attr('class') =~ /tbCel[12]/ } ) )
  {
    my $html = $tr->look_down( _tag => 'td', 'class' => 'caption1')->right->look_down( _tag => 'span' )->as_HTML();
    my ($date, $trID);
    if ( $html =~ m/.*#(\d+|\d+,\d+)<\/a>\s+\&middot;\s+(\d+)&nbsp;(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)&nbsp;(\d{4})/ )
    {
      $date = sprintf("%4d%02d%02d", $4, $self->mo2dec($3), $2);
      $trID = $1;
      if ( exists  $status->{$self->tfID()}->{trIDs}->{$trID}->{date} )
      {
        # We've already seen this row, but its possible it didn't download all images
        #next;
      }
      else
      {
        $status->{$self->tfID()}->{trIDs}->{$trID}->{date} = $date;
      }
    }
    else
    {
      cluck "Couldn't split date string from the post, page layout may have changed or the post may be too new.\nHTML: $html", ref($self);
      next;
    }

    my $tdID = 0;
    foreach my $link ( @{ $tr->look_down( _tag => 'div', 'class' => 'postedText' )->extract_links('a') } )
    {
      my $ext = "JPG";
      next unless ( $link->[0] =~ /action=downloadfile/ );
      $tdID++;
      if ( exists( $status->{$self->tfID()}->{trIDs}->{$trID}->{links}->{$tdID} ) && exists( $status->{$self->tfID()}->{trIDs}->{$trID}->{files}->{$tdID} ) )
      {
          print $status->{$self->tfID()}->{trIDs}->{$trID}->{files}->{$tdID} . " already downloaded, delete " . $self->statusFile() . " to force retry; skipping\n";
          next;
      }
      else
      {
#        if ( $link->[0] =~ /.*\.(arw|bmp|cr2|crw|dcp|dds|djvu|dng|fpx|gif|ico|ithmb|jp2|jpeg|jpg|nef|nrw|orf|pcd|pcx|pict|png|psd|sfw|tga|tif|tiff|webp|xcf)$/ )
#        {
#          $ext = uc($1);
#        }
#        else { next; }

        $status->{$self->tfID()}->{trIDs}->{$trID}->{links}->{$tdID} = $link->[0];

        if ( exists( $status->{$self->tfID()}->{index}->{$date} ) )
        {
          $status->{$self->tfID()}->{index}->{$date}++;
        }
        else
        {
          $status->{$self->tfID()}->{index}->{$date} = 1;
        }

        my $fn = sprintf("%d_%8d-%03d.%s", $self->tfID(), $date, $status->{$self->tfID()}->{index}->{$date}, $ext);

        #print "$fn\n" and die;
        print "getPicture($fn, $link->[0])\n";
        $self->getPicture($fn, $link->[0]);
        $status->{$self->tfID()}->{trIDs}->{$trID}->{files}->{$tdID} = $fn;
      }
    }

    #$status->{$self->tfID()}->{$self->page()}->{tr}++;
  }

  #print Dumper($status);
  $status->{$self->tfID()}->{LPS} = $self->curPage();
  $self->saveStatus($status);
}


sub getPicture
{
  my ($self, $fn, $href) = @_;
  my $req = GET $href;
  my $fh = gensym();
  unless ( open ( $fh, '>', $fn ) )
  {
    confess "I could not open $fn for writing to the file system", ref($self);
  }
  my $res = $self->{ua}->request( $req, sub { print $fh $_[0] } );
  close $fh;
  return 1;
}


sub saveStatus
{
  my ($self, $status) = @_;
  my $json = encode_json($status);
  my $fh = gensym();
  unless ( open ( $fh, '>', $self->statusFile() ) )
  {
    confess "Could not open " . $self->statusFile() . " for saving process status", ref($self);
  }
  print $fh $json;
  close $fh;
  return 1;
}


sub loadStatus
{
  my $self = shift;
  my $status;
  my $fh = gensym();
  if (-e $self->statusFile() )
  {
    unless ( open ( $fh, '<', $self->statusFile() ) )
    {
      confess "Could not open " . $self->statusFile() . " for reading process status", ref($self);
    }
    my $json = <$fh>;
    close $fh;
    $status = decode_json($json);
  }
  return $status;
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


sub index
{
  my $self = shift;
  unless ( defined $self->{index} )
  {
    $self->{index} = 'http://' . $self->baseURL() . '/index.php';
  }
  return $self->{index};
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
    confess "Could not identify page position, something on the page must have changed!\n";
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


sub pageURL
{
  my $self = shift;
  return 'http://' . $self->baseURL() . '/' . $self->page();
}


sub statusFile
{
  my $self = shift;
  unless ( exists $self->{statusFile} )
  {
    $self->{statusFile} = sprintf("%d_%d.bin", $self->fID(), $self->tID());
  }
  return $self->{statusFile};
}


sub tfID
{
  my $self = shift;
  unless ( exists $self->{tfID} )
  {
    $self->{tfID} = $self->tID() . $self->fID();
  }
  return $self->{tfID};
}


sub LPS
{
  my $self = shift;
  my $status = $self->loadStatus();
  if (exists $status->{$self->tfID()}->{LPS})
  {
    $self->{LPS} = $status->{$self->tfID()}->{LPS};
  }
  else
  {
    $self->{LPS} = 0;
  }
  return $self->{LPS};
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
$ripper->logon();
$ripper->letItRip();

__END__

=head1 $0

=head1 SYNOPSIS

$0 [options] [URL]

  Options:
    -h | --help              Brief Help message
    -u | --user              Username to use
    -p | --pass              Use a password, optionally use password supplied on command line
    -url                     The forum url to scrape

=cut
