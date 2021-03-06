package Dating::Me;

################
#
# Dating - social profile database
#
# Anatoly Schrödinger
# weirdo2@opmbx.org
#
# Dating/Me.pm is the dating service user identity (login+password) 
# capable of browsing dating site.
#
################

use warnings;
no warnings 'experimental::smartmatch';
use strict;
use utf8;
use HTTP::Request::Common qw(GET);
use HTTP::Request::Common qw(POST);
use HTTP::Cookies;
use LWP::UserAgent;
use Dating::misc qw(safety_delay);
use JSON;
use Encode qw( encode_utf8 );
use Data::Dumper;
use Carp;

our $VERSION = "1.01";
our @ISA    = qw(LWP::UserAgent);
our $Debug;

$Debug = 1 unless defined $Debug;
# 1 - short overview of execution flow
# 2 - debug

my $valid_mamba_login_criterion=qr/auth:\s*1/;
my $tmp="/tmp";

BEGIN {
	binmode(STDOUT, ':encoding(UTF-8)');
	binmode(STDERR, ':encoding(UTF-8)');
	eval {  
		require LWP::Protocol::socks;
		LWP::Protocol::socks->import();
	};
	#if ($@) { ...}
}

=encoding UTF-8

=head1 NAME

Dating::Me - search, load questionnaire HTML pages

=head1 SYNOPSIS

  use Dating::Me;

  my $me = Dating::Me->new (service=>mamba, login=>$login, password=>$password);
  for ($me->search (mysex=>'M', sex=>'F', agelow=>25, agehigh=>30)) {
      print ("profile url: $_\n");
  }

  (see examples)

=head1 About

Me is the dating service user identity (login+password) 
capable of browsing dating site.

Me also is a subclass of LWP::UserAgent
and you can use any of its methods (get, post, request...) 
to request data from arbitrary sites as well.

=head1 Attributes

=head2 login

Mandatory

=head2 password

Mandatory

=head2 location

Own coordinates which were supplied during account registration, 
in the following format: "51.5672 26.5713" (see "user location" in INSTALL).

=head2 captcha_callback

Reference to subroutine which takes content of page with recaptcha
and returns raw POST data for dating site (/tips on mamba) or undef on error.
See examples/fetcher.pl.

Obsoleted: Reference to subroutine which takes image content as argument
and returns resolved captcha.

=head2 myid

Dynamically calculated for internal use.

=head2 anon_ua

Auxiliary LWP:UserAgent for bulk transfers without logging in.
Use it for search engines and mamba image downloads.
It always uses default useragent string.
No other attributes are shared with main LWP::UserAgent.
Cookies are not shared or saved. Beware IP and timing correlations.

=head1 Methods

=head2 new

  my $me = Dating::Me->new( %options );

=over

=item %options are LWP::UserAgent::new options 
(agent, local_address, env_proxy etc, default should be fine)
and the following additional options related to dating service 
(for details see description of the same attributes above):

  login
  password
  location
  captcha_callback
  cookies_dir
  proxy (proxy URI: http://host:port/ or socks://host:port if LWP::Protocol::socks found)
  proxy_anon (for anon_ua, see above)
  phone (for login phone confirmations. country code is a separate option - below)
  phone_code

Session is persistent due to cookies file (one per login), 
placed in cookies_dir (default is current directory).

=back

=cut

sub new {

my($class, %options) = @_;

croak("Options to Dating::Me should be key/value pairs, not hash reference") 
	if ref($_[1]) eq 'HASH';

my $def_agent="Mozilla/5.0 (Windows NT 6.1; rv:24.0) Gecko/20100101 Firefox/24.0"; # mimic tb

my $l = delete $options{login};
my $p = delete $options{password};
my $r = delete $options{location};
my $cc = delete $options{captcha_callback};
my $cdir = delete $options{cookies_dir}; $cdir="." unless defined $cdir;
my $pro = delete $options{proxy};
my $proa = delete $options{proxy_anon};
my $ph = delete $options{phone};
my $phc = delete $options{phone_code};

unless ($options{'agent'}) { $options{'agent'}=$def_agent };
unless ($options{'parse_head'}) { $options{'parse_head'}=0 };

my $self = LWP::UserAgent::new($class, %options);
#bless $self, $class;
$self->proxy([qw(http https ftp)] => $pro) if $pro;

$self->{anon_ua} = LWP::UserAgent->new( agent => $def_agent );
$self->{anon_ua}->proxy([qw(http https ftp)] => $proa) if $proa;

$self->{login}=$l;
$self->{password}=$p;
$self->{location}=$r;
$self->{captcha_callback}=$cc;
$self->{phone}=$ph;
$self->{phone_code}=$phc;

if ($self->{login}) { 
	$self->{myid} = $self->{login};
	$self->{myid} =~ s/@.*//;
} else { $self->{myid}="ANON" };

my $cookiefile = $cdir."/.cookies-".$self->{myid};
$self->cookie_jar(HTTP::Cookies->new(file => $cookiefile, 
	autosave => 1, ignore_discard => 1));

# globally handle 301,302 POST result automatically
# for recaptcha, 
# or if host=mamba.ru, not www.mamba.ru
push @{ $self->requests_redirectable }, 'POST';

return $self;
} # new


=head2 request_retry

LWP->request with delay and retries, to work around unstable proxies.
Default number or retries is 5.

  my $lwp_result = $me->request_retry ($lwp_request[, $number_of_retries]);

=cut

sub request_retry {
my $self = shift;
my $req = shift; my $retr = shift || 5;

my $res;
for (my $r=0; $r<$retr; $r++) {
	safety_delay;
	$res = $self->request($req);
	if ($res->is_success) { return $res; }
	carp "request_retry ".$res->code if $Debug>1;
}

print STDERR "request_retry failed ".$retr." times\n";
if ($res->code == 500) {
	print STDERR "500 content follows: -----\n".$res->decoded_content."-----\n";
}

return $res;

} # request_retry


=head2 login

Logs in to dating service, using login and password object attributes.

  my $success = $me->login;

=cut

sub login {
my $self = shift;
# remember, we are LWP::UserAgent child

my $lreq; my $lres; my $mainpage_content;
my $cap=""; my $phone_confirmation_requested=0;

####### GET /

Getroot:

print STDERR "getting /\n" if $Debug>0;

$lreq = GET 'http://www.mamba.ru/';
$lres = $self->request_retry($lreq);
$lres->is_success or confess "login ".$lres->code;
if ($Debug>1) {
  open (l_0, ">:utf8", "l_0.html");
  print l_0 $lres->decoded_content;
  close (l_0);
}
#my $captcha_uri;
#if ($lres->decoded_content =~ /"(\/captcha\.php\?.*)"/ ) { $captcha_uri = $1; }
#  else { $captcha_uri=""; }
#print STDERR "captcha_uri=".$captcha_uri . "\n" if $Debug>1;

# save for captcha search
$mainpage_content = $lres->decoded_content;

# get new feature: s_post=[32 chars] from mambo js structure on main page
my $s_post;
if ($lres->decoded_content =~ /'&s_post=(\w*)'/ ) { $s_post = $1; }
  else { $s_post=""; }
print STDERR "s_post=".$s_post . "\n" if $Debug>1;

if (($Debug>0) and ($lres->decoded_content =~ /$valid_mamba_login_criterion/)) {
	print STDERR "already authenticated\n";
} else {
	print STDERR "not authenticated\n";

####### POST login

Plogin:

printf STDERR "POST login (cap=$cap, phone=$phone_confirmation_requested)\n" if $Debug>0;

my $o = [ 
	"s_post" => $s_post, 
	"login" => $self->{login}, 
	"password" => $self->{password},
];
if ($cap) {
	$o->{clickUrl} = "";
	$o->{target} = "";
	$o->{"phone-code"} = "7";
	$o->{phone} = "";
	$o->{"login_captcha"} = $cap;
	$o->{VAnketaID} = "0";
	$o->{RedirectBack} = "http://www.mamba.ru/?";
}
if ($phone_confirmation_requested) {
	unless ((defined $self->{phone}) && (defined $self->{phone_code})) {
		confess "phone number confirmation requested but no phone defined";
	}
	$o->{"phone-code"} = $self->{phone_code};
	$o->{phone} = $self->{phone};
}
print STDERR "login options: \n".Dumper $o if $Debug>1;
 
$lreq = POST 'http://www.mamba.ru/ajax/login.phtml?XForm=Login', $o;
$lreq->header("Accept" => "application/json, text/javascript, */*; q=0.01");
$lreq->header("X-Requested-With" => "XMLHttpRequest");
#$lreq->header("Referer" => "Referer: http://www.mamba.ru/");

$lres = $self->request_retry($lreq);
unless ($lres->is_success) {
	if ($lres->code == 302) {
		# no x-req-with header:
		# HTTP/1.1 302 Moved Temporarily
		# Location: http://www.mamba.ru/tips/?tip=Login
		carp "ajax login returns redirection instead of json, probably bad request headers or host name";
	}
	confess "login ".$lres->code;
}

#$lua->cookie_jar->save();

if ($Debug>1) {
	open (l_1, ">:utf8", "l_1.json");
	print l_1 $lres->decoded_content;
	close (l_1);
}
my $t_1  = decode_json (encode_utf8 ($lres->decoded_content));
unless ($t_1) {
	confess "ajax login returns something not parseable as json";
}
print STDERR Dumper ($t_1) if $Debug>1;

# success:
# {"t":"1342491046994","a":474170573,"s":1,"e":0,"d":[],"r":"","XForms":0}

# incorrect password:
# {"t":"1342470916960","a":0,"s":1,"e":0,"d":[],"r":0,"XForms":{"Login":{"found":"Incorrect e-mail address or password entered"}}}

if ( !($t_1->{"captcha"}) ) {
	print STDERR "no captcha after POST login\n" if $Debug>0;
} else {
	#### Captcha
	print STDERR "captcha ($t_1->{'captcha'}) is requested after POST login\n" if $Debug>0;
	print STDERR "captcha_title: $t_1->{'d'}->{'captcha_title'}\n" if $Debug>1;
	if (defined ($self->{captcha_callback}) && ref($self->{captcha_callback})) {
		my $cap_raw_post = &{ $self->{captcha_callback} } ($mainpage_content);
		unless (defined $cap_raw_post) { confess ("can't resolve captcha"); }
		my $recreq = POST 'http://www.mamba.ru/tips';
		$recreq->content( $cap_raw_post );
		my $recres = $self->request_retry($recreq);
		# returns 301 if success, redirect handled automatically (see new()), then must return 200
		$recres->is_success or confess "recaptcha isn't accepted or bad redirect? code=".$recres->code;
		#$content = $recres->decoded_content;
		#goto Plogin;
		goto Getroot;
	} else {
		confess ("captcha resolver isn't provided");
	}
	#confess ("captcha is not handled in POST login");

} # POST login returns captcha

unless ($t_1->{a} > 0) {
	if ((defined $t_1->{phone}) && ($t_1->{phone} > 0)) {
		carp "phone confirmation requested" if $Debug>0;
		$phone_confirmation_requested=1;
		goto Plogin;
	}
	confess "ajax login doesn't return positive id, perhaps wrong credentials?\n".Dumper ($t_1);
}

goto Getroot;

} # GET / requires login

print STDERR "assuming logged in\n" if $Debug>0;

return (1==1);
} # login


=head2 get_dating_url

Fetches URL from dating site. Unlike LWP::UserAgent::get, 
logs in to dating service if necessary.

  my $content = $me->get_dating_url ($url);

=cut

sub get_dating_url {

my $self = shift;
my $url = shift;

my $freq; my $fres; my $content; my $recreq; my $recres;

$url or do { carp "get_dating_url requires url"; return undef };

do {
print STDERR "fetching ".$url."\n" if $Debug>1;
$freq = GET $url;

$fres = $self->request_retry($freq);
$fres->is_success or do { carp "get_dating_url failed: ".$fres->code; return undef };

$content = $fres->decoded_content;

if ($Debug>1) {
  open (l_gf, ">:utf8", "get_dating_url.bin");
  print l_gf $content;
  close (l_gf);
}

if ($fres->content_type =~ /^image|json/) {
	# return images without login tests
	return $content;
}

if ($content !~ /$valid_mamba_login_criterion/ ) { 
	print STDERR "need login\n" if $Debug>0;
	$self->login(); 
	$self->cookie_jar->load();
	}

CheckEntercode:
if ($content =~ /Введите код|пройдите проверку/ && $` !~ /visible:.*isCaptcha/) {
	# 2014: recaptcha.
	# callback accepts $content,
	# returns raw POST data for /tips or undef on timeout
	# TODO: error handling instead of confess()
	if (defined ($self->{captcha_callback}) && ref($self->{captcha_callback})) {
		my $cap_raw_post = &{ $self->{captcha_callback} } ($content);
		unless (defined $cap_raw_post) { confess ("can't resolve captcha"); }
		my $recreq = POST 'http://www.mamba.ru/tips';
		$recreq->content( $cap_raw_post );
		$recres = $self->request_retry($recreq);
		# returns 301 if success, redirect handled automatically (see new()), then must return 200
		$recres->is_success or confess "recaptcha isn't accepted or bad redirect? code=".$recres->code;
		$content = $recres->decoded_content;
		goto CheckEntercode;
	} else {
		confess ("captcha resolver isn't provided");
	}
}

} until ($content =~ /$valid_mamba_login_criterion/);

return $content;
} # get_dating_url


=head2 get_anon_url

Like get_dating_url, but uses auxiliary anon_ua LWP::UserAgent (see above).
For bulk transfers like web search or image downloads.

  my $content = $me->get_anon_url ($url);

=cut

sub get_anon_url {

my $self = shift;
my $url = shift;

my $freq; my $fres; my $content;

$url or do { carp "get_anon_url requires url"; return undef };

print STDERR "fetching anon ".$url."\n" if $Debug>1;
$freq = GET $url;

safety_delay;
$fres = $self->{anon_ua}->request($freq);
$fres->is_success or do { carp "get_anon_url failed: ".$fres->code; return undef };

$content = $fres->decoded_content;

if ($Debug>1) {
  open (l_gf, ">:utf8", "get_anon_url.bin");
  print l_gf $content;
  close (l_gf);
}

return $content;
} # get_anon_url


=head2 search

Searches 3rd party dating site for profiles.

  my @search_result = $me->search (sex => F, mysex => M, db => $dbh, ...

Takes the list of options:

=over

=item sex (M,F,N, default F)

=item mysex (default M)

=item agelow (default is empty = all ages)

=item agehigh

=item loc_code (location code in the form a_b_c_d (see example), default is 0_0_0_0 = everywhere)

=item db (database handler for searching only profiles which are not yet in 'profiles' table)

=item maxresults

=item deep (0/1. If 1, then search until exactly maxresults obtained (or forever, if maxresults is not supplied). Otherwise, search until no new profile appears on search result page (default)

=item additional_profile_table (if ID found in this sql table, then don't return this ID in search results, as if it were found in profiles)

=back

Returns an array of profile URLs.

=cut

sub search {

my $self = shift;
# flags passed in as arguments
my %f;
if (@_) {
    %f = @_;
}

# http://www.mamba.ru/search.phtml?t=a&sz=b&ia=M&lf=F&af=22&at=33&s_c=248_190_0_0&target=&offset=40
# 2015:
# http://www.mamba.ru/search.phtml?ia=M&lf=F&af=18&at=80&t=a&s_c=248_0_0_0&form=1
# but former query still works

my $search_query_nooffset = "http://www.mamba.ru/search.phtml?t=a&sz=b"
  ."&ia=". (defined $f{'mysex'} ? $f{'mysex'} : 'M')
  ."&lf=". (defined $f{'sex'} ? $f{'sex'} : 'F')
  ."&af=". (defined $f{'agelow'} ? $f{'agelow'} : '')
  ."&at=". (defined $f{'agehigh'} ? $f{'agehigh'} : '')
  ."&s_c=".(defined $f{'loc_code'} ? $f{'loc_code'} : '0_0_0_0')
  ."&target=";

my $still_anything_new=1;
my $initial_offset = 30;
my @profile_links;

# fetch search pages while at least one new profile found
for (my $offset = $initial_offset; $still_anything_new; $offset=$offset+10) {

	$still_anything_new=0;
	print STDERR "search results offset: $offset\n" if $Debug>0;

	print STDERR "search request: GET ".$search_query_nooffset."&offset=".$offset."\n" if $Debug>1;
	my $req = GET $search_query_nooffset."&offset=".$offset ;

	my $res = $self->request_retry($req);

	my $srch_cnt = $res->decoded_content;

	if ($Debug>1) {
	  open (l_s, ">:utf8", "l_s.html");
	  print l_s $srch_cnt;
	  close (l_s);
	}

	$res->is_success or confess "search ".$res->code;

	if ($srch_cnt !~ /$valid_mamba_login_criterion/ ) { 
		print STDERR "need login\n" if $Debug>0;
		$self->login(); 
		$self->cookie_jar->load();
	}

	# <a class="u-name" href="http://www.mamba.ru/mb450410392?hit=10&fromsearch&sp=3" >Галя</a>, <b>33</b>
	while ($srch_cnt =~ /<a class="u-name(.*?) href="(https?:\/\/(www\.)?mamba\.ru\/(..\/)?(\S*?))(\?|\")/ ) {
		$srch_cnt = $';
		my $prolink = $2;
		my $id = $5;

		my $record_is_needed=1;
		if (defined ($f{'db'})) {
			my $sth = $f{'db'}->prepare( "
			SELECT id, nick FROM profiles WHERE id LIKE '%/".$id."' OR pages LIKE '%".$prolink."%'
			".(defined($f{'additional_profile_table'}) ? " UNION SELECT id, nick FROM ".$f{'additional_profile_table'}." WHERE id LIKE '%/".$id."' OR pages LIKE '%".$prolink."%'" : ""));
			$sth->execute;
			if ($sth->rows > 0) {
				$record_is_needed=0;
			}
		}
		if (defined ($f{'maxresults'})) {
			if (@profile_links >= $f{'maxresults'}) {
				$record_is_needed=0;
				$still_anything_new=0;
			}
		}
		if ($prolink ~~ @profile_links) {
			$record_is_needed=0;
		}

		if ($record_is_needed) {
			print STDERR "new profile: $id \n" if $Debug>0;
			$still_anything_new=1;
			push @profile_links, $prolink;
		} # profile is not seen or count<maxresults

		if ( (defined($f{'deep'})) && $f{'deep'}==1 ) {
			# get maxresults unconditionally
			if (defined ($f{'maxresults'})) {
				if (@profile_links < $f{'maxresults'}) {
					$still_anything_new=1;
				}
			} else {
				$still_anything_new=1;  # forever
			}
		} # deep search?

	} # links to profiles

} # search pages

return @profile_links;

} # search


=head1 LICENSE

Copyright 2012-2014, Anatoly Schrödinger <weirdo2@opmbx.org>

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
See L<http://dev.perl.org/licenses/artistic.html>

=head1 SEE ALSO

L<Dating::She>

Repository: L<https://github.com/psywave/dating>

=cut
1;

