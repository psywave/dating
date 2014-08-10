package Dating::She;

################
#
# Dating - social profile database
#
# Anatoly Schrödinger
# weirdo@noipmail.com
#
# Dating/She.pm is dating questionnaire (profile) object 
#
################

use warnings;
no warnings 'experimental::smartmatch';
no warnings 'experimental::lexical_topic';
use strict;
use utf8;
use HTML::TreeBuilder 5 -weak;

use Data::Dumper; # no utf.
$Data::Dumper::Terse = 1;
# dirty magic for utf
# enhanced version of http://www.perlmonks.org/?node_id=759457
$Data::Dumper::Useqq = 1;
{ no warnings 'redefine';
    sub Data::Dumper::qquote {
        my $s = shift;
	#$s =~ s/\\/\\\\/g; $s =~ s/'/\\'/g;  # can't unquote this
	$s =~ s/\\/\//g; $s =~ s/'/’/g;
        return "'$s'";
    }
}
#use Data::Dump qw(dump); no utf
#use Data::TreeDumper; bad utf

use DBI();
use Dating::math;
use Dating::misc;
use JSON;
use Encode qw( encode_utf8 );
use File::Path qw( mkpath );
use Carp;
#use Carp qw(cluck);

our $VERSION = "1.00";
#our @ISA    = qw(HTML::TreeBuilder);   # not their child anymore
our $Debug;

$Debug = 1 unless defined $Debug;
# 1 - short overview of execution flow
# 2 - debug

BEGIN {
   binmode(STDOUT, ':encoding(UTF-8)');
   binmode(STDERR, ':encoding(UTF-8)');
}

=encoding UTF-8

=head1 NAME

Dating::She - dating questionnaire

=head1 SYNOPSIS

  use Dating::She;

  my $she = Dating::She->new();
  $she->{nick} = "Test User 1";
  $she->copy_to_db ($dbh);

  (see examples)

=head1 About

Dating::She represents unified dating profile attributes 
and API from user's perspective, 
abstracted from real dating service features and details.

Attributes like age, sex and marital status may be updated (many times in any order) from HTML files, from dating service web site (currently of Russian Mamba service), from SQL databases, and pushed back to SQL database:

  my $she = She->new;
  $she->parse_file( 'main.html', 
        (service => 'mamba', pagekey=>'main') );
  print $she->as_text;

For single object, many related pages may be parsed.
Dating::She spawns HTML::TreeBuilder (and hence, HTML::Parser and HTML::Element) objects to parse 
each HTML page, and you can also use any of their methods:

  $she->{parsers}->{main}->look_down(...)  (see HTML::Element(3pm))

Attributes can be extracted for external analysis 
by collective accessors: see distintions_ methods below.

=head1 Constructors

=head2 new

  my $she = Dating::She->new;

=over

=item This method takes no attributes.

=back

=head2 new_from_url

  my $she = Dating::She->new_from_url ($search_result_url, $me);

=over

=item This constructor creates a new object and gets profile recursively from the network using provided search result URI and 
Dating::Me object.

=item TODO: take 'service' argument? Currently assumes Mamba.

=back

=head2 new_from_db

  my $she = Dating::She->new_from_db ($id, $dbh);

This constructor creates a new object with provided id (i.e., "mamba/username") 
and tries to restore its state from SQL database.
Database handler $dbh must be open.

Returns restored object if success, undef if fail.

=head2 init

  $she->init;

=over

=item Flushes all attributes to their default. After init() object can be reused as being just created.

=back

=cut

our $NOT_SUPPLIED=-1;

sub init {

my $self = shift;

=head1 Attributes

Attributes are actual profile content.
Default values should be undef scalar or empty hash/array for correct updating from database.
These are attributes still not found by parsers or about which 
parsers weren't sure.

-1 or $NOT_SUPPLIED means "value is definitely not supplied in dating profile".
Note that it evaluates to true in boolean context.

0 usually means 0 or false.

Positive number usually means that number or true.

Attributes are additive, i.e. whenever you parse() or merge_from_db() 
anything for the same Dating::She object, you can expect its attributes 
will be updated to keep as much information as possible (see update_value() below for details).

=head2 pages

A hash of html pages related to this profile:

=over

=item main => http://url#1 (this is special page - search result)

=item diary => ...

=back

Default is empty hash.

=cut
	$self->{pages} = {};
=head2 parsers

Hash of HTML::TreeBuilder objects for parsing pages (see above), created by parse() and parse_file() methods
(see below). Althought it shares the same keys as pages, it's not in the same hash deliberately for 
usage simplicity.
These objects are kept until next parse() method call on this page.
This attribute is not stored in database.

=over

=item main => {HTML::TreeBuilder #1}

=item diary => ...

=item ...

=back

Default is empty hash.

=cut
	$self->{parsers} = {};
=head2 images

Hash of hashes:
  image_unique_id => { 
     url =>
     caption =>
     explicit => (image marked as explicit - called "intim" in mamba)
     localpath => (undef if still not downloaded)
  }
  ...

Default is empty hash.
=cut
	$self->{images} = {};
=head2 icon_localpath

Relative filesystem path to profile icon/avatar (currently simply 
a thumbnail of first image).
=cut
	$self->{icon_localpath} = undef;
=head2 ctime

When object was last updated from web, UTC timestamp.
Default is 0.
=cut
	#$self->{ctime} = time();
	$self->{ctime} = 0;
=head2 id

Profile unique ID in the form "service/id_in_service", i.e. "mamba/mb1234567".
This must be unique, as it will be directly used as primary key in SQL tables.
=cut
	$self->{id} = undef;
=head2 nick

Nickname
=cut
	$self->{nick} = undef;
=head2 realname

Real name (not in Mamba)
=cut
	$self->{realname} = undef;
=head2 sex

Sex: 'M', 'F'
=cut
	$self->{sex} = undef;
=head2 birth

Birth year estimation (current year minus age)
=cut
	$self->{birth} = undef;
=head2 city

=head2 city_lat

=head2 city_lon

Current country, [region,] city [,station] and coordinates, if found in geonames.
lat/lon calculation requires `geoname` and `alternatename` tables in database.
=cut
	$self->{city} = undef;
	$self->{city_lat} = undef;
	$self->{city_lon} = undef;
=head2 distance

Hash of distances (km) from reference points, as returned by dating service:
  refpoint1 => distance1
  ...

refpoint is UTM/WGS84 coordinates of the place which was supplied during registration of account for Dating::Me and later passed to parse() or parse_file().

Default is empty hash.
=cut
	$self->{distance} = {};
=head2 location

=head2 location_lat

=head2 location_lon

When parser collects three or more distance records (see above)
giving total not more than reference triangle perimeter, 
it tries to trilaterate them to calculate user location,
using all possible triples.
If the result is consistent and doesn't reside withing 2 km of city_lat,city_lon (i.e. non-trivial),
it's put in the location CHAR attribute (obsoleted, but supported)
and location_lat, location_lon FLOAT attributes.
=cut
	$self->{location} = undef;
	$self->{location_lat} = undef;
	$self->{location_lon} = undef;
=head2 profession

Main business. undef in Mamba.
=cut
	$self->{profession} = undef;
=head2 education

  0: lower than university
  1: university
  2: better than university
=cut
	$self->{education} = undef;
=head2 languages

Languages: concatenated string.
=cut
	$self->{languages} = undef;
=head2 relations

Current relations
  0: no
  1: yes (any)
  2: yes, but not married
  3: married, including civil marriage
=cut
	$self->{relations} = undef;
=head2 divorced

  0: no
  1: yes
undef in Mamba.
=cut
	$self->{divorced} = undef;
=head2 children

  0: no
  127: yes, number not specified
  other positive number: number of children
=cut
	$self->{children} = undef;
=head2 sexrate

Desired sex rate
  0: "sex is not important" or any other answer which means user doesn't need sex
  1: yes (rate unspecified)
  2: more seldom than daily
  9: daily
=cut
	$self->{sexrate} = undef;
=head2 nphoto

  0: no photo
  positive number: number of images
=cut
	$self->{nphoto} = undef;
=head2 replyrate

Reply probability as estimated by dating service, percent
=cut
	$self->{replyrate} = undef;
=head2 specialeffort

Efforts for distinction (for ex. "VIP" on Mamba)
  0: no
  1: priceless enhancements
  2: paid by herself
  3: paid by another user
=cut
	$self->{specialeffort} = undef;
=head2 seen

Profile viewing counter, per month
=cut
	$self->{seen} = undef;
=head2 targetsex

Sex of desired partner: 'M', 'F', 'MF'
=cut
	$self->{targetsex} = undef;
=head2 targetagelow

Lowest age of desired partner
=cut
	$self->{targetagelow} = undef;
=head2 targetagehigh

Highest age of desired partner
=cut
	$self->{targetagehigh} = undef;
=head2 wantcommunicate

=head2 wantrelations

=head2 wantmeeting

=head2 wantsex

=head2 wantmarriage

=head2 wantmoney

User "dating goals", generally checkboxes, if available. 
undef = not found, 1 = yes.

wantcommunicate = friendship or communication or correspondence, 
wantrelations = relations or flirt or similar

Beware: mamba doesn't return all these checkboxes in any single fetch (see docs). 
=cut
	$self->{wantcommunicate} = undef;
	$self->{wantrelations} = undef;
	$self->{wantmeeting} = undef;
	$self->{wantsex} = undef;
	$self->{wantmarriage} = undef;
	$self->{wantmoney} = undef;
=head2 smoking

  0: no
  1: yes
=cut
	$self->{smoking} = undef;
=head2 height

In cm
=cut
	$self->{height} = undef;
=head2 weight

In kg
=cut
	$self->{weight} = undef;
=head2 fat

User specified her build as thick or obese
  0: specified not thick or obese
  1: yes
=cut
	$self->{fat} = undef;
=head2 incomehigh

User described her income as better than average
  0: no
  1: yes
=cut
	$self->{incomehigh} = undef;
=head2 optional

User posted anything not mandatory or default (except of non-mandatory photos)
  undef: nothing found
  1: yes
=cut
	$self->{optional} = undef;
=head2 interests

Array of keywords related to user interests. Default is empty array.
=cut
	$self->{interests} = [];
=head2 manual

Hash of input fields entered manually by user. Specific keys depend on dating service. For Mamba they are:

=over

=item greeting

=item want_to_find

=item sex_related (hash of title=>content)

=item selfportrait (hash of question=>answer)

=item diary (hash of title=>content)

=back

Default is empty hash.
=cut
	$self->{manual} = {};
=head2 copypaste

Hash of input fields copypasted from internet. The keys are the same as for manual (see above).
Default is empty hash.
=cut
	$self->{copypaste} = {};
=head2 sexkeywords

String of keywords and phrases related to user interests in sex. Default is undef.

{sexkeywords} and {manual}->{sex_related} are not subset of each other.
=cut
	$self->{sexkeywords} = undef;

} # init()


sub new {
#	#shift->SUPER::new(@_, weight => 0.05, name => 'candle')
	#my $self = shift->SUPER::new(@_);
	my $class = shift;
	#$class = ref($class) || $class;
	my $self = {};
	bless($self, $class);
	$self->init;
	return $self;
} # new


sub new_from_url {

my $class = shift;
my $url = shift;
my $me = shift;

my $self = $class->new;
#$self->parse( $me->get_dating_url($url), (pagekey=>'main', me=>$me, recursive=>1) );
$self->{'pages'}->{'main'} = $url;
if ($self->update_from_page( (pagekey=>'main', me=>$me, recursive=>1) )) {
	return $self;
} else {
	return undef; # f.e., "anketa nedostupna"
}
} # new_from_url


sub new_from_db {

my $class = shift;
my $id = shift;
my $dbh = shift;

my $self = $class->new;
$self->{'id'} = $id;

if ($self->merge_from_db($dbh)) {
	return $self;
} else {
	return undef;
}

} # new_from_db


=head1 Methods

=head2 as_text

Returns current attributes. Suitable for learning what's actually in the profile.
  print $she->as_text;

=cut

sub as_text {
my $self = shift;
my $out;

# scalars
do {
$out .= $_.": ";
if (defined($self->{$_})) { $out .= $self->{$_} } else { $out .= "undef" };
$out.="\n";
}
 foreach qw( ctime id 
nick realname sex birth city city_lat city_lon location location_lat location_lon profession education languages 
relations divorced children sexrate nphoto replyrate specialeffort 
seen targetsex targetagelow targetagehigh
wantcommunicate wantrelations wantmeeting wantsex wantmarriage wantmoney
smoking height weight fat incomehigh optional sexkeywords );

$out .= "$_: ".Dumper($self->{$_}) foreach qw( pages images distance interests manual copypaste );

# arrays with utf-8
#foreach my $arr ( "interests" ) {
# $out .= $arr.": [ ".join(", ", @{$self->{$arr}})." ]\n";
#}

return $out;
} # as_text



# sub with global var example
#sub text	{ $text_elements++  }



=head2 update_from_page

Updates attributes from profile web page, fetching and parsing it.
Value for pages->pagekey attribute must be already initialized.

  my $result = $she->update_from_page (%flags);
  my $result = $she->update_from_page ( (me=>$some, pagekey=>'main') );

=head3 %flags

Recognized flags are same as for parse() (below), but 'me' and 'pagekey' are mandatory.

=cut

sub update_from_page {

my $self = shift;
my %flags = @_;

for ("pagekey", "me") {
	if (!defined ($flags{$_})) { 
		carp ("update_from_page: '$_' flag required");
		return 0;
}}
if (!defined ($self->{'pages'}->{$flags{'pagekey'}})) {
	carp ("update_from_page: '$flags{'pagekey'}' page url isn't initialized");
	return 0;
}

return $self->parse( $flags{'me'}->get_dating_url($self->{'pages'}->{$flags{'pagekey'}}), %flags );

} # update_from_page



=head2 location_guess

Calculates, if possible:

city_lat, city_lon - from city,

location_lat, location_lon, location - from reference distances.

Argument: $dbh.

Perhaps you don't need to call it explicitly.
It can't be called from parse, because it requires $dbh for working with geonames tables, 
hence we call it from push_to_db.

=cut

sub location_guess {

my $self = shift;
my $dbh = shift;

unless ( defined ($self->{city}) ) { return 0 }  # because for filtering location we need city coords
unless ($self->{city} =~ /^(.*?),\s*(.*)$/) {
	carp ("can't parse city: $self->{city}") if $Debug>0;
	return 0;
}
my $country=$1; my $city_name=$2;
my ($la, $lo) = city_coordinates ($dbh, $country, $city_name); # from misc
until ($la && $lo) {
	carp ("$city_name coordinates not found") if $Debug>0;
	return 0;
}
$self->{city_lat}=$la; $self->{city_lon}=$lo;
carp ("added city_lat=".$la." lon=".$lo." for id=".$self->{id}) if $Debug>1;

after_city:

unless ( (keys($self->{distance}) >= 3) and 
  (!defined($self->{location}) || !defined($self->{location_lat}) || 
  !defined($self->{location_lon})) and 
  ((defined $self->{city_lat}) and (defined $self->{city_lon}))
  ) {
	carp ("insufficient refpoints or location is already present or city coordinates are not present") if $Debug>1;
	return 0;
}

# TODO: limit number of triples

my @dk = map { @$_} [ keys $self->{distance} ];

my ($la1, $lo1, $di1, $la2, $lo2, $di2, $la3, $lo3, $di3);

I: for (my $i=0; $i<=($#dk); $i++) {
	$di1=$self->{distance}->{$dk[$i]};
	if ($dk[$i] =~ /(-?\d+\.\d+)\D+(-?\d+\.\d+)/) { $la1=$1; $lo1=$2 } else { next I }
J: 	for (my $j=$i+1; $j<=($#dk); $j++) {
		$di2=$self->{distance}->{$dk[$j]};
		if ($dk[$j] =~ /(-?\d+\.\d+)\D+(-?\d+\.\d+)/) { $la2=$1; $lo2=$2 } else { next J }
K: 		for (my $k=$j+1; $k<=($#dk); $k++) {
			$di3=$self->{distance}->{$dk[$k]};
			if ($dk[$k] =~ /(-?\d+\.\d+)\D+(-?\d+\.\d+)/) { $la3=$1; $lo3=$2 } else { next K }
			print "testing if refpoints $i $j $k are suitable for trilateration\n" if $Debug>0;
			my $refpt_sum = distance($la3, $lo3, $la2, $lo2) +
				distance($la2, $lo2, $la1, $lo1) +
				distance($la1, $lo1, $la3, $lo3); # perimeter of reference triangle
			my $dist_sum = $di1+$di2+$di3; # sum of reference distances
			if (($dist_sum > $refpt_sum) || ($Debug>1)) {
				print "reference triangle perimeter = ".$refpt_sum.", reference distances sum = ".$di1."+".$di2."+".$di3."=".$dist_sum." km\n";
			}
			if ($dist_sum > $refpt_sum) {
				print "skipping triple\n" if $Debug>0;
				next K;
			} else {
				print "refpoints triple is suitable for trilateration\n" if $Debug>0;
			}
			($self->{location_lat}, $self->{location_lon}) = trilaterate (
				$la1,$lo1,$di1, 
				$la2,$lo2,$di2, 
				$la3,$lo3,$di3);
			# result is the same for any combination of given three point,
			# no need to check all combinations.
			if ($self->{location_lat} && $self->{location_lon}) {
				$self->{location} = $self->{location_lat}." ".
				  $self->{location_lon};
				print "successfully trilaterated\n" if $Debug>0;
				my $city_location_distance = distance ($self->{city_lat}, $self->{city_lon}, 
				  $self->{location_lat}, $self->{location_lon});
				if ((defined $city_location_distance) && ($city_location_distance < 2.0)) {
					print "but city_location_distance=".$city_location_distance." < 2.0 - deleting location\n" if $Debug>0;
					$self->{location_lat}=undef; $self->{location_lon}=undef;
				} else {
					return 1;
				}
			} else {
				print "trilaterate failed\n" if $Debug>0;
			}
		} # K
	} # J
} # I

return 0;
} # location_guess



=head2 parse

Parses dating pages.
Spawns HTML::TreeBuilder objects for HTML parsing of each page,
attaching parsers to $self->{parsers} and page URI to $self->{pages} (see attributes description above),
then obtains dating attributes from them.
Parser for specific page is kept intact until next call to parse() for the same page.

  my $result = $she->parse ($content, %flags);

=head3 $content

Scalar content of HTML page, mandatory.

=head3 %flags

Optional. Recognized flags:

=over

=item service: dating service, default=mamba.

=item pagekey: dating service page type. For mamba: main, albums, album_NUMBER, self-portrait, diary. Default is "main" page (link from search result), which should be defined for each service.

=item me: reference to Dating::Me object to get refpoint coordinates and perform recursive HTTP requests.

=item recursive: parse all profile pages recursively. 'me' flag must be set. Default=0.

=back

=cut

sub parse {
my $self = shift;
# mandatory
my $content = shift;
unless ($content) { carp "nothing to parse"; return undef; }
my %flags = @_;
my $caller; # ref to Dating::Me
my $refpoint;
my $page = $flags{'pagekey'} || "main";
my $service = $flags{'service'} || "mamba";
my $recursive;
if ($flags{'me'}) { 
	$caller=$flags{'me'};
	$refpoint=$caller->{'location'};
	$recursive = $flags{'recursive'};
}

my $parser_ret;
print "parsing ".$page."\n" if $Debug>0;

$self->{ctime} = time();

my $parser = $self->{parsers}->{$page};
if (ref ($parser) =~ "HTML::TreeBuilder") {
	$parser->delete; # because this parser can be reused by multiple Me objects
}
$parser=HTML::TreeBuilder->new();
#$parser->utf8_mode(1); # don't!
$parser->ignore_unknown(0); # recognize <article>
$parser_ret = $parser->parse($content);
$parser->eof();

if ($service =~ "mamba") {


########### common data for any mamba profile page ##############

my @fu01=("mamba profile unavailable", 300);
#
for ($parser->look_down(_tag=>'h1')) {
	if ($_->as_text =~ qr/Анкета недоступна/) {
		fc_ok(@fu01);
		carp "\"profile unavailable\"";
		return undef;
	}
}
fc_fail(@fu01);

# need ID before recursive parsing of pages, at least for construction of images->localpath
#<a href="https://www.mamba.ru/umyshlenno/dating" onclick="return false;" class="sel-anketa-nav-anketa">
my @fi01=("mamba ID in /dating href", 0);
#
if (my $a = $parser->look_down( _tag => 'a', class=>"sel-anketa-nav-anketa")) {
	if ($a->{href} =~ /\S+:\/\/\S+\/(\S+)\/dating/ ) {
		$self->{id} = $service."/".$1;
		fc_ok(@fi01);
	}
}
unless (defined ($self->{id})) {
	fc_fail(@fi01);
	carp ("can't find ID, aborting parse\n");
	return undef;
}

# pages
my @fp01=("mamba pages: ul class nav", 0);
my @fp02=("mamba pages: a class sel-anketa-nav-*", 10);
my @fp10=("mamba link to main page", 50);
my @fp11=("mamba link to diary page", 50);
my @fp12=("mamba link to albums-related page", 50);
my @fp13=("mamba link to self-portrait page", 50);
my @fp40=("mamba link to known page", 0);
#
if (my $ul = $parser->look_down( _tag => 'ul', class=>'nav' )) {
	fc_ok(@fp01);
	for my $a ($ul->look_down( _tag=>'a' )) {
		if ($a->{class} =~ /sel-anketa-nav-(\S*)($|\s)/) {
			fc_ok(@fp02);
			my $pname=$1;
			if ($pname =~ "anketa") { $pname="main"; fc_ok(@fp10); } else { fc_fail(@fp10); }
			if ($pname =~ "dair") {	$pname="diary"; fc_ok(@fp11); } else {fc_fail(@fp11); }
			if ($pname =~ /album/) {fc_ok(@fp12);} else {fc_fail(@fp12);}
			if ($pname =~ "self-portrait") {fc_ok(@fp13); } else { fc_fail(@fp13); }
			if ($pname !~ qr/main|album|self-portrait|diary|apps|travel/) {
				print "unknown page: $pname\n" if $Debug>0;
				fc_fail(@fp40);
			}
			$self->{pages}->{$pname} = $a->{href};
			# recursive call
			# from main page we fetch next level pages that we know how to parse
			if ($recursive and ($page=~"main") and ($pname =~ qr/albums|self-portrait|diary/) ) {
				#$parser->detach();
				$self->parse( $caller->get_dating_url($a->{href}), 
				   ( pagekey=>$pname, me=>$caller, recursive=>1) );
			}
		} else {
			fc_fail(@fp02);
		}
	}
} else {
	fc_fail(@fp01);
}

# "avatar" photo (may be alone without "albums" link)
# may be contained in div class=photoOne, but may be in 'photoMore'.
# perhaps in latter case we don't need to fetch avatar here, 
# as it will be in 'album' page?
my @fa01=("mamba avatar photo: a class photoUser", 0);
my @fa02=("mamba avatar photo: album_id in a class photoUser", 0);
#
if (my $aa=$parser->look_down(_tag=>'a', class=>qr/photoUser/)) {
	# href="https://www.mamba.ru/mb902253712/album_photos?album_id=902254372#photo_id=902296182"
	fc_ok(@fa01);
	my $aref=$aa->{href};
	if ($aref =~ /.*album_id=(\d+)($|\&|\/|#)/) {
		fc_ok(@fa02);
		my $album_id=$1;
		if (!defined($self->{pages}->{'album_'.$album_id})) {
			$self->{pages}->{'album_'.$album_id} = $aref;
			# immediate recursion if needed
			$self->parse( $caller->get_dating_url($aref), 
			   ( pagekey=>'album_'.$album_id, me=>$caller) ) if $recursive;
		} # need to fetch avatar album
	} else {
		fc_fail(@fa02);
	}
} else {
	fc_fail(@fa01);
}
# no photo?
my @fnf01=("mamba div class noPhoto", 300);
#
if( ($parser->look_down(_tag=>'div', class=>qr/noPhoto/)) and (!defined($self->{nphoto})) ) {
	$self->{nphoto}=0;
	fc_ok(@fnf01);
} else {
	fc_fail(@fnf01);
}

# nick
my @fni01=("mamba nick: h1 class infoname", 0);
#
if (my $h1=$parser->look_down(_tag=>'h1', class=>qr/infoname/i)) {
	$self->{nick} = $h1->as_trimmed_text;
	fc_ok(@fni01);
} else {
	fc_fail(@fni01);
}

# sex
#<div id="FirstGiftsBlockB" class="boxGiftsFirst boxGiftsFemale">
# no other ways?
my @fs01=("mamba sex: div id FirstGiftsBlockB class Female", 25); # not anymore?
my @fs02=("mamba sex: \"you winked at she\" in entire page", 5);
my @fs03=("mamba sex: \"she has webcamera\" in entire page", 250);
#
if ($parser->look_down(_tag=>'div', id=>"FirstGiftsBlockB", class=>qr/Female/)) {
	fc_ok(@fs01);
	$self->{sex}="F";
} else {
	fc_fail(@fs01);
}

if ($parser->as_text =~ /Вы подмигнули ей/i) {
	$self->{sex} = "F";
	fc_ok(@fs02);
} else {
	fc_fail(@fs02);
}

# seems like feture removed, fc 50->250, remove if not found
if ($parser->as_text =~ /У нее есть веб-камера/i) {
	$self->{sex} = "F";
	fc_ok(@fs03);
} else {
	fc_fail(@fs03);
}

if ($parser->look_down(_tag=>'div', id=>"FirstGiftsBlockB", class=>qr/Male/) || 
     ($parser->as_text =~ /Вы подмигнули ему|У него есть веб-камера/i) ) {
	$self->{sex} = "M";
}

#        <span id="self-age">
#            23 года,
#        </span>
my @fag01=("mamba age: span id self-age parseable", 5);
#
if ( my $span = ($parser->look_down( _tag => 'span', id => "self-age"))) {
	if ($span->as_trimmed_text =~ /(\d*)\s.*/) { 
		fc_ok(@fag01);
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		$self->{birth} = $year + 1900 - $1;
	} else {
		fc_fail(@fag01);
	}
} else {
	fc_fail(@fag01);
}

# distance, city, location
#    <div class="infoMisc">
#        <span....
#        Козерог.
#        Беларусь, Минск
#        <span class="info"><i class="icon16 location middle"></i>~10220 км</span>
my @fcl01=("mamba city&location: div class infoMisc", 0); my $fcldet=0;
my @fcl02=("mamba city&location: span class info", 5);
my @fcl03=("mamba city&location: distance is parseable", 0);
my @fcl04=("mamba city&location: city is parseable", 0);
#
for my $div ($parser->look_down(_tag=>'div', class=>"infoMisc")) {
	$fcldet=1;
	# first, search for distance (only if refpoint supplied)
	if ($refpoint) {
	if (my $spi = $div->look_down(_tag=>'span', class=>"info")) {
		fc_ok(@fcl02);
		if ($spi->as_trimmed_text =~ /(~)?(\d*)\s*(к|k)?(м|m)/) {
			fc_ok(@fcl03);
			my $n = $2;
			if ($3 =~ 'к') { $self->{distance}->{$refpoint} = $n } else { $self->{distance}->{$refpoint} = $n/1000 }
		} else {
			fc_fail(@fcl03); # distance not parseable
		}
	} else {
		fc_fail(@fcl02);
	}
	} # refpoint supplied
	# parse city
	my $zod_n_city;
	for my $item_r ($div->content_refs_list) {
		next if ref $$item_r;
		$zod_n_city .= $$item_r;
	}
	if ($zod_n_city) {
		if ($zod_n_city =~ /^(\s|(.*?\.))*(.*?)(\s*)$/) {
			fc_ok(@fcl04);
			$self->{city} = $3;
		} else {
			fc_fail(@fcl04);
		}
		last;
	}
}
$fcldet ? fc_ok(@fcl01) : fc_fail(@fcl01);

#<span class="reply_rate_progress rr_yellow">
#	<i style="width:53%;"></i>
#	<b></b>
my @fcrr01=("mamba span class reply_rate_progress", 0);
my @fcrr02=("mamba reply_rate_progress is parseable", 0);
#
if (my $span=$parser->look_down(_tag=>'span', class=>qr/reply_rate_progress/)) {
	fc_ok(@fcrr01);
	my $i; if ( ($i=$span->look_down(_tag=>'i')) and $i->{style}) {
	if ($i->{style} =~ /width:(\d+)%/) {
		fc_ok(@fcrr02);
		$self->{replyrate}=$1;
	} else {
		fc_fail(@fcrr02);
	}} else {
		fc_fail(@fcrr02);
	}
} else {
	fc_fail(@fcrr01);
}

#<body class="UT-12 U-Vip
#<div class="tooltip-content vip-about-from
#2 раза = подарил vip кто-то кроме меня
my @fcv1=("mamba vip: body class U-Vip", 30);
#my @fcv2=("mamba vip: div class vip-about-from in vip anketa", 0);  # not anymore?
my @fcv2=("mamba vip: _podaril vip na_ in vip anketa", 10);
#
my $body;
if ( $body = $parser->look_down(_tag=>'body', class=>qr/U-Vip/)) {
	fc_ok(@fcv1);
#	$self->{specialeffort}=2;
# no such feature anymore?
#	my $from_count=0;
#	for ($parser->look_down(_tag=>'div', class=>qr/vip-about-from/)) { $from_count++ };
#	if ($from_count>1) { $self->{specialeffort}=3 };
#	if ($from_count==0) { fc_fail(@fcv2); } else { fc_ok(@fcv2); }
# 	( check: select id, specialeffort from profiles where specialeffort=3 ; )
	if ($parser->as_text =~ /подарил VIP на/i) {
		$self->{specialeffort}=3;
		fc_ok(@fcv2);
	} else {
		$self->{specialeffort}=2;
		fc_fail(@fcv2);
	}
} else {
	fc_fail(@fcv1);
}

#<div class="anketa_bottom">
#...
# <div class="mb5 fl-l">ID: 481917581, просмотров за месяц: 662</div>
my @fcs01=("mamba seen counter: div class anketa_bottom", 0);
my @fcs02=("mamba seen counter is parseable", 0);
#
if ( my $div = $parser->look_down( _tag => 'div', class => "anketa_bottom")) { 
	fc_ok(@fcs01);
	if ($div->as_trimmed_text =~ /просмотров за месяц: (\d+)/) {
		fc_ok(@fcs02);
		$self->{seen}=$1;
	} else {
		fc_fail(@fcs02);
	}
} else {
	fc_fail(@fcs01);
}



########## specific mamba pages #################

if ($page !~ /^(main$|album)/) { $self->{optional}=1; }

if ($page =~ "main") {


########## mamba main "anketa"

#<div class="b-anketa_field">
#	<div class="b-anketa_field-title">Отношения:</div>
#	<div class="b-anketa_field-content">Нет</div>
#</div>

my $skw1=undef; my $skw2=undef; my $skw3=undef; # sexkeywords

my %fields = parse_anketa_fields($parser);
#
my @fcaf01=("mamba form field is known", 0);
my @fcaf02=("mamba form field is _relations_", 100);
my @fcaf03=("mamba form field is _children_", 100);
my @fcaf04=("mamba form field is _sex frequency_", 300);
my @fcaf05=("mamba form field is _date with_", 100);
my @fcaf06=("mamba form field is _goals_", 100);
my @fcaf07=("mamba form field is _smoking_", 100);
my @fcaf08=("mamba form field is _constitution_", 100);
my @fcaf09=("mamba form field is _earning_", 100);
my @fcaf10=("mamba form field is _money support_", 100);
my @fcaf11=("mamba form field is _who i want to meet_", 100);
my @fcaf12=("mamba form field is _also exciting_", 200);
my @fcaf13=("mamba form field is _in sex i like_", 200);
my @fcaf14=("mamba form field is _excitations_", 200);
my @fcaf15=("mamba form field is _breast size_", 200);
my @fcaf16=("mamba form field is _education_", 100);
my @fcaf17=("mamba form field is _languages_", 100);
#

foreach ( keys %fields ) {
	my ($c, $is_entered_manually) = ( $fields{$_}[0], $fields{$_}[1] );
	# here we have:
	print "title: \"$_\" content: \"$c\" is_entered_manually: ".$is_entered_manually."\n" if $Debug>1;

	TITLE: {  # portable

	unless (/Познакомлюсь:|Знание языков/) { $self->{optional} = 1 };

	if (/Отношения:/) {
		fc_ok(@fcaf01); fc_ok(@fcaf02);
		my @fcrel01=("mamba _relations_ form field: value is known", 0);
		if ($c =~ "Нет") { $self->{relations}=0; fc_ok(@fcrel01) } else {
		if ($c =~ /Ничего серьёзного|Есть отношения/) { $self->{relations}=2; fc_ok(@fcrel01) } else {
		if ($c =~ "В браке") { $self->{relations}=3; fc_ok(@fcrel01) } else {
		fc_fail(@fcrel01) }}}
		last TITLE;
	} else {
		fc_fail(@fcaf02);

	if (/Дети/) {
		fc_ok(@fcaf01); fc_ok(@fcaf03);
		my @fcchi=("mamba _children_ form field: value is known", 0);
		if ($c =~ /Нет/) { $self->{children}=0; fc_ok(@fcchi) } else {
		if ($c =~ /Есть/) { $self->{children}=127; fc_ok(@fcchi) } else {
		fc_fail(@fcchi) }}
		last TITLE;
	} else {
		fc_fail(@fcaf03);

	if (/Как часто хотела? бы заниматься сексом/) {
		fc_ok(@fcaf01); fc_ok(@fcaf04);
		if ($c =~ /в день/) { $self->{sexrate}=9 } else {
		if ($c =~ /неделю|месяц/) { $self->{sexrate}=2 } else {
		if ($c =~ /не очень важен/) { $self->{sexrate}=0 }}}
		last TITLE;
	} else {
		# select sexrate from profiles where sexrate<>-1 ;
		fc_fail(@fcaf04);

	if (/Познакомлюсь:/) {
		fc_ok(@fcaf01); fc_ok(@fcaf05);
		$self->{targetsex}="";
		if ($c =~ /парнем/) { $self->{targetsex}="M" }
		if ($c =~ /девушкой/) { $self->{targetsex} .= "F" }
		if ($c =~ /в возрасте (\d+)(.*)-(\d+)/) {
			$self->{targetagelow}=$1; $self->{targetagehigh}=$3;
		}
		last TITLE;
	} else {
		fc_fail(@fcaf05);

	if (/Цель знакомства:/) {
		fc_ok(@fcaf01); fc_ok(@fcaf06);
		GOAL: {
		 my $_ = $c;
		 if (/Дружба|общение/)	{ $self->{wantcommunicate}=1 }
		 if (/Переписка/)	{ $self->{wantcommunicate}=1 }
		 if (/Отношения/)	{ $self->{wantrelations}=1 }
		 if (/Флирт/)		{ $self->{wantrelations}=1 }
		 if (/Брак/)		{ $self->{wantmarriage}=1 }
		 if (/спортом/)		{ }
		 if (/Путешествия/)	{ }
		 if (/Секс/)		{ $self->{wantsex}=1 }
		 if (/Встреча|Свидание/){$self->{wantmeeting}=1 }
		 }
		last TITLE;
	} else {
		fc_fail(@fcaf06);

	if (/Отношение к курению/) {
		fc_ok(@fcaf01); fc_ok(@fcaf07);
		if ($c =~ /Не курю/) { $self->{smoking}=0 } else {
		if ($c =~ /Курю/) { $self->{smoking}=1 }}
		last TITLE;
	} else {
		fc_fail(@fcaf07);

	if (/Телосложение:/) {
		fc_ok(@fcaf01); fc_ok(@fcaf08);
		if ($c =~ /Плотное|Полное/) { $self->{fat}=1 } else { $self->{fat}=0 }
		last TITLE;
	} else {
		fc_fail(@fcaf08);

	if (/Материальное положение/) {
		fc_ok(@fcaf01); fc_ok(@fcaf09);
		if ($c =~ /Хорошо зарабатываю|обеспечен/) { $self->{incomehigh}=1 }
		  else { $self->{incomehigh}=0 }
		last TITLE;
	} else {
		fc_fail(@fcaf09);

	if (/Материальная поддержка/) {
		fc_ok(@fcaf01); fc_ok(@fcaf10);
		if ($c =~ /Ищу спонсора/) { $self->{wantmoney}=1 } else {
		if ($c =~ /Не нуждаюсь/) { $self->{wantmoney}=0 }}
		last TITLE;
	} else {
		fc_fail(@fcaf10);

	if (/Кого я хочу найти/) {
		fc_ok(@fcaf01); fc_ok(@fcaf11);
		if ($c !~ "") { 
			if (netsearch($c, $caller->{anon_ua})) {
				$self->{copypaste}->{want_to_find} = $c;
			} else {
				$self->{manual}->{want_to_find} = $c; 
			}
		}
		last TITLE;
	} else {
		fc_fail(@fcaf11);

	if (/Что ещё меня возбуждает/) {
		# assuming this is always entered manually
		fc_ok(@fcaf01); fc_ok(@fcaf12);
		if ($c !~ "") { 
			if (netsearch($c, $caller->{anon_ua})) {
				$self->{copypaste}->{sex_related}->{$_} = $c;
			} else {
				$self->{manual}->{sex_related}->{$_} = $c; 
			}
		}
		last TITLE;
	} else {
		fc_fail(@fcaf12);

	if (/В сексе .* интересует|В сексе я люблю/) {
		fc_ok(@fcaf01); fc_ok(@fcaf13);
		$skw1=$c;
		last TITLE;
	} else {
		fc_fail(@fcaf13);

	if (/(Меня|Его|Ее|Её) возбуждает/) {
		# rare case: seems like this may be entered manually OR choosen
		fc_ok(@fcaf01); fc_ok(@fcaf14);
		if ($is_entered_manually && ($c !~ "")) { # manually -> goes to manual->sto
			if (netsearch($c, $caller->{anon_ua})) {
				$self->{copypaste}->{sex_related}->{$_} = $c;
			} else {
				$self->{manual}->{sex_related}->{$_} = $c; 
			}
		} else { # choosen -> goes to sexkeywords
			$skw2=$c;
		}
		last TITLE;
	} else {
		fc_fail(@fcaf14);

	if (/Размер груди/) {
		fc_ok(@fcaf01); fc_ok(@fcaf15);
		$skw3=$_.$c;
		last TITLE;
	} else {
		fc_fail(@fcaf15);

	if (/Образование/) {
		fc_ok(@fcaf01); fc_ok(@fcaf16);
		if ($c =~ /среднее|неполное/i) { $self->{education}=0 } 
		elsif ($c =~ /высшее/i) { $self->{education}=1 }
		elsif ($c =~ /два или более высших|ученая степень/i) { $self->{education}=2 }
		last TITLE;
	} else {
		fc_fail(@fcaf16);

	if (/Знание языков/) {
		fc_ok(@fcaf01); fc_ok(@fcaf17);
		if ($c !~ "") {	$self->{languages}=$c; }
		last TITLE;
	} else {
		fc_fail(@fcaf17);

	if (/^(Отношение к алкоголю|Внешность|Ориентация|Проживание):$/) { # known but useless
		fc_ok(@fcaf01);
		last TITLE;
	} else {

		fc_fail(@fcaf01); # unknown field
		print "Unknown form field: ".$_."\n" if $Debug>0;
	}

	}}}}}}}}}}}}}}}}
	} # TITLE block

} # b-anketa_field cycle

if (defined($skw1) or defined($skw2) or defined($skw3)) { $self->{sexkeywords}=""; }
for ( $skw1, $skw2, $skw3 ) { if (defined($_)) { $self->{sexkeywords}.=$_; } }

# <div class="b-anketa_field-title">
#     Рост:
#     <span>173 см</span>
my @fcwh01=("mamba weight/height: height found in any div class b-anketa_field-title", 100);
my @fcwh02=("mamba weight/height: weight found in any div class b-anketa_field-title", 100);
#
for my $div ($parser->look_down( _tag=>'div', class=>"b-anketa_field-title")) {
	my $ft = $div->as_trimmed_text;
	if ($ft =~ /Рост:\s*(\d+)\s*см/) { $self->{height}=$1; fc_ok(@fcwh01) } else {fc_fail(@fcwh01)}
	if ($ft =~ /Вес:\s*(\d+)\s*кг/) { $self->{weight}=$1; fc_ok(@fcwh02) } else {fc_fail(@fcwh02)}
}

# <div class="bx-anketa-content interests_block">
my @fcin01=("mamba interests: div class interests_block", 30);
my @fcin02=("mamba interests: span class name in div class interests_block", 0); my $ind=0;
#
if (my $d1=$parser->look_down(_tag=>'div', class=>qr/(^|\s)interests_block($|\s)/)) {
	fc_ok(@fcin01);
	# <span class="name">православие</span>
	for my $s1 ($d1->look_down(_tag=>'span', class=>qr/(^|\s)name($|\s)/)) {
		fc_ok(@fcin02); $ind=1;
		if ( !($s1->as_trimmed_text ~~ $self->{interests}) ) {
			push $self->{interests}, $s1->as_trimmed_text;
		}
	}
	unless ($ind) {fc_fail(@fcin02)}
} else {
	fc_fail(@fcin01);
}

# greeting
my @fcgr01=("mamba: greeting found", 10);
my @fcgr02=("mamba: greeting is non-empty", 80);
#
if (my $d=$parser->look_down(_tag=>'div', class=>qr/(^|\s)fMessage($|\s)/)) {
	fc_ok(@fcgr01);
	if ((as_trimmed_text_br($d)) !~ /^\s*$/) {
		fc_ok(@fcgr02);
		my $gr=as_trimmed_text_br($d);
		if (netsearch($gr, $caller->{anon_ua})) {
			$self->{copypaste}->{greeting} = $gr;
		} else {
			$self->{manual}->{greeting} = $gr;
		}
	} else {
		fc_fail(@fcgr02);
	}
} else {
	fc_fail(@fcgr01);
}

# the following data should be seen to every registered fetcher.
# if we didn't see it, then assume user didn't provide it
foreach ( 'education', 'languages', 'relations', 'children', 'sexrate', 'targetsex', 
'targetagelow', 'targetagehigh', 
'smoking', 'height', 'weight', 'incomehigh' ) {
	unless (defined $self->{$_}) { $self->{$_}=$NOT_SUPPLIED };
}

} # mamba, page=main


##############  mamba "albums" page

elsif ($page =~ "albums") {

my @fcal00=("mamba albums: div id Albums", 0);
my @fcal01=("mamba albums: div class AlbumTitle", 0); my $altf=0;
my @fcal02=("mamba albums: a class name in div class albumtitle", 0);
my @fcal03=("mamba albums: a class name href is parseable for album_ids", 0);
#
if (my $da=$parser->look_down(_tag=>'div', id=>"Albums")) {
	fc_ok(@fcal00);
	for my $div ($da->look_down(_tag=>'div', class=>"AlbumTitle")) {
		fc_ok(@fcal01); $altf=1;
		# <a class="name" href="https://www.mamba.ru/ru/umyshlenno/album_photos?album_id=481917582">Это я</a>
		if (my $a = $div->look_down( _tag=>'a', class=>'name')) {
			fc_ok(@fcal02);
			my $album_ref=$a->{href};
			if ($album_ref =~ /.*album_id=(\d+)($|\?|\/|#)/) {
				my $album_id=$1;
				fc_ok(@fcal03);
				if (!defined($self->{pages}->{'album_'.$album_id})) {
					# still not parsed earlier as single avatar
					$self->{pages}->{'album_'.$album_id} = $album_ref;
					# recursive call
					#$self->detach(); # of HTML::Element
					$self->parse( $caller->get_dating_url($album_ref), 
					   ( pagekey=>'album_'.$album_id, me=>$caller) ) if $recursive;
				} # parse album_id pages
			} else {
				fc_fail(@fcal03);
			}
		} else {
			fc_fail(@fcal02);
		}
	}
	unless ($altf) {fc_fail(@fcal01)};
} else {
	fc_fail(@fcal00);
}

} # mamba, page=albums


##############  mamba single album page

elsif ($page =~ /album_(\d*)/) {

# now Dating::Me is needed only in db_dump
#unless (defined($caller)) { return undef }

# mambo.project.FotoViewer('#FotoLayer', { ...
#		,photos: [].concat([{"id":"1180269334",...],[...],[...
# using regex instead of fuss with HTML::Element
my @fca_01=("mamba single album: FotoViewer js block found", 0);
my @fca_02=("mamba single album: json decoded", 0);
#
unless ($content =~ qr/\.FotoViewer\s*\(.*photos\s*:\s*\[\s*\]\s*\.\s*concat\s*\((\[.*?\])\)/s) {
	fc_fail(@fca_01);
	return undef;
}
fc_ok(@fca_01);
my $pic_json=$1; $pic_json =~ s/\],\[/,/g; # js concat() surrogate
if ($Debug>1) {
	#print "found pictures list: $1\n";
	my $ac; my $pl;
	open ($ac, ">:utf8", "albcontent.html");
	print $ac $content;
	close ($ac);
	print "album content dumped to albcontent.html\n";
	open ($pl, ">:utf8", "piclist.json");
	print $pl $pic_json;
	close ($pl);
	print "pictures list dumped to piclist.json\n";
}
my $imj  = decode_json (encode_utf8($pic_json));
unless ($imj) {
	fc_fail(@fca_02);
	return undef;
}
fc_ok(@fca_02);
print Dumper ($imj) if $Debug>1;
IMAGE: foreach (@$imj) {
	# seems like "large">"huge" in mamba, but "large" is absent sometimes
	my $imgurl = defined $_->{large} ? $_->{large} : $_->{huge};
	unless (defined($imgurl)) { carp "can't find \"large\" or \"huge\" image, skipping"; next IMAGE };
	print "picture: ".$imgurl."\n" if $Debug>1;
	unless (defined($_->{id})) { carp "can't find image ID: ".Dumper($imj); next IMAGE };
	my $imgid="mamba/".($_->{id});
	unless (defined $self->{images}->{$imgid}->{url}) { $self->{nphoto}++ } # consider this image new
	$self->{images}->{$imgid}->{url}=$imgurl;
	if (defined($_->{name})) { $self->{images}->{$imgid}->{caption}=$_->{name} };
	if (defined($_->{intim})) { $self->{images}->{$imgid}->{explicit}=$_->{intim} };
}

} # mamba, page=single album


##############  mamba self-portrait page

elsif ($page =~ "self-portrait") {

my @fcsp=("mamba self-portrait: non-empty set", 0);
#
my %fields = parse_anketa_fields($parser);
if ( defined (keys %fields) and (keys %fields) >0 ) {
	fc_ok(@fcsp);
	foreach ( keys %fields ) {
		my ($c, $is_entered_manually) = ( $fields{$_}[0], $fields{$_}[1] );
		$self->{manual}->{selfportrait}->{$_} = $c;
	}
} else {
	fc_fail(@fcsp);
}


} # mamba, page=self-portrait


##############  mamba diary page

elsif ($page =~ "diary") {

my @fcdi00=("mamba diary: section class contentList", 0);
my @fcdi01=("mamba diary: article found", 0); my $af=0;
my @fcdi02=("mamba diary: article is parseable", 0);
#
if (my $cl=$parser->look_down (_tag=>'section', class=>qr/contentList/)) {
	fc_ok(@fcdi00);
	for my $a ($cl->look_down (_tag=>'article')) {
		fc_ok(@fcdi01); $af=1;
		if (my $h=$a->look_down (_tag=>'h2') and 
		  my $c=$a->look_down (_tag=>'div', class=>qr/(^|\s)extended($|\s)/)) {
			fc_ok(@fcdi02);
			my $dcon=as_trimmed_text_br($c);
			if (netsearch($dcon, $caller->{anon_ua})) {
				$self->{copypaste}->{diary}->{as_trimmed_text_br($h)} = $dcon;
			} else {
				$self->{manual}->{diary}->{as_trimmed_text_br($h)} = $dcon;
			}
		} else {
			fc_fail(@fcdi02);
		}
	}
	unless ($af) {fc_fail(@fcdi01)}
} else {
	fc_fail(@fcdi00);
}


} # mamba pages (elsif-elsif-...)

} else {
	carp "unknown service (not mamba)";
}

$parser->eof();
return $parser_ret;
} # parse



=head2 parse_file

Parses file using parse(). ctime attribute is set to file's ctime.

  my $result = $she->parse_file ($filename, %flags);

=over

=item %flags are the same as for parse().

=back

=cut

sub parse_file {
my $self = shift;
my $file = shift; if (! $file) { carp "no file to parse"; return undef; }
my %flags = @_;
my $content = do {
    local $/ = undef;
    open my $fh, "<:utf8", $file
        or do { carp "can't open file ".$file.": $!"; return undef };
    <$fh>;
};
my $ret = $self->parse($content, %flags);
$self->{ctime} = (stat($file))[10];
return $ret;
} # parse_file



=head1 Database related methods


=head2 merge_from_db

Restores She attributes (aka actual profile content) from SQL,
de-serializing them if necessary and merging with current attributes.
Database schema is described in docs and can be recreated with update_sql_schema().

Takes connected database handler as argument.

my $rv = $she->merge_from_db ($dbh);

Returns 1 if sucess, 0 if failed.

=cut

sub merge_from_db {

my $self=shift;
my $dbh=shift or do { carp "merge_from_db: \$dbh argument required"; return 0 };

my $selrow = "
SELECT $profile_fieldlist FROM profiles WHERE id=?
";
my $sth= $dbh->prepare($selrow);
$sth->execute($self->{id});
if (my @row = $sth->fetchrow_array) {
	$dbh->commit; # to finish transaction. perhaps not needed?
	print Dumper(@row) if $Debug>1;
	my $own_ctime=$self->{ctime}; my $db_ctime;
	for (@profile_fields) {
		my $v = shift @row;
		print "deserializing: ".$_ . "---->" . $v ."\n" if $Debug>1;
		if ($_=~"ctime") {
			# must be first value parsed
			$db_ctime=$v; 
			print "db_ctime=".$db_ctime." own_ctime=".$own_ctime." -> ".(($own_ctime<$db_ctime)?"db":"mine")." are newer\n" if $Debug>1;
		}
		if ($_=~"images") {
			# special case: merge each image to preserve {localpath}
			my %im = %{deserialize ($v)};
			for (keys %im) {
				print "image localpath in db: ".$im{$_}->{localpath}."\n" if $Debug>1;
				$self->{images}->{$_} = update_value ($im{$_}, 
				  $self->{images}->{$_},
				  ((!defined $own_ctime) or ($own_ctime<$db_ctime))
				);
			}
		} else {
			# usual update
			$self->{$_} = update_value (
			  deserialize ($v), $self->{$_},
			  ((!defined $own_ctime) or ($own_ctime<$db_ctime)) 
			);
		}
	}
	return 1;
} else {
	return 0;
}

} # merge_from_db



=head2 copy_to_db

my $rv = $she->copy_to_db ($dbh[, $path, $me]);

Unconditionally pushes ::She attributes (aka actual profile content) 
into SQL record, serializing them if necessary.
Database schema is described in docs.
If database can already contain this record, then you should 
perform merge_from_db immediately prior to copy_to_db 
or use sync_with_db.

Takes connected database handler as mandatory argument. It must be opened with AutoCommit=>0.

If $path and $me are supplied, then prior to SQL push, 
fetches new images using $me of class Dating::Me and stores them in filesystem "database" under $path.

Also, prior to SQL push, 
calls location_guess($dbh), 
which tries to calculate various coordinates attributes from {city} and {distance}.

Returns 1 if success, 0 if failed.

=cut

sub copy_to_db {

my $self=shift;
my $dbh=shift or do { carp "copy_to_db: \$dbh argument required"; return 0 };
my $path=shift;
my $me=shift;

if (defined ($me) and defined ($path)) {
	$self->copy_images ($path, $me);
}

$self->location_guess ($dbh);

eval {
	#my $values = join ", ", map { $dbh->quote(serialize($self->{$_})) } @profile_fields;
	my @values = map { serialize($self->{$_}) } @profile_fields;
	my $id_val = serialize($self->{id});
	#print "inserting values: ".$values."\n" if $Debug>1;
	my $repl = qq{

	INSERT INTO profiles ( id, $profile_fieldlist ) VALUES ( ?, $profile_field_placeholders )
	ON DUPLICATE KEY UPDATE $profile_field_update_placeholders
	};

	print "replace query: ".$repl."\n" if $Debug>1;
	my $sth=$dbh->prepare($repl);
	$sth->execute ($id_val, @values, @values);
};
if($@){
	carp "can't copy_to_db: $@";
	$dbh->rollback();
	return 0;
} else {
	$dbh->commit;
	return 1;
}

} # copy_to_db



=head2 copy_images

my $rv = $she->copy_to_db ($path, $me);

Fetches $self-{images} having empty 'localpath' property 
using $me of class Dating::Me and stores them under $path.
Note that it changes {images} attribute and hence should be called _before_ copy_to_db.

Returns 1 if success, 0 if failed.

=cut

sub copy_images {

my $self=shift;
my $prefix=shift or do { carp "copy_images: \$path argument required"; return 0 };
my $me=shift or do { carp "copy_images: \$me argument required"; return 0 };

IMG: for my $ikey (keys ($self->{images})) {
   unless (defined($self->{images}->{$ikey}->{localpath})) {
	my $url=$self->{images}->{$ikey}->{url};
	my $image = $me->get_anon_url ($url); # for mamba. for other services use get_dating_url
	if (!$image) { carp "Can't get_anon_url for image: ".$url; next IMG };

	# emulate mamba path, though we don't care if they abandon it
	# http://193.0.171.30/62/49/54/1050839426/1206926829_huge.jpg?updated=20132223032451
	unless ($url =~ /^https?:\/\/(\S*?)\/(\S*)\/(\S*?)(\?|$)/) { carp "can't parse image path: $url"; next IMG };
	my $dir=$2; my $fname=$3;
	if ($dir=~/(\.|^\/|\x00)/ ) { carp "dir is not sane, skipping: ".$dir; next IMG };	
	if ($fname=~/(\/|\.\.|\x00)/) { carp "fname is not sane, skipping: ".$fname; next IMG };
	mkpath ($prefix."/mamba/".$dir);
	my $localpath="mamba/".$dir."/".$fname; # for self and sql
	my $localfile=$prefix."/".$localpath;

	unless (open (IMGF, ">", $localfile)) { carp ("can't open $localfile: $!"); next IMG };
	if (syswrite IMGF, $image) { print "dumped ".$localpath."\n" if $Debug>0; };
	close (IMGF);

	$self->{images}->{$ikey}->{localpath} = $localpath; # done, don't fetch next time

	my $e=$self->{images}->{$ikey}->{explicit};
	if ((defined($e)) and ($e!=0)) {
		# post cdn url to gallery or irc?
		print "fap!\n" if $Debug>0;
	}

	if ($self->{icon_localpath}) { goto nothumb; }
	# make a thumbnail of arbitrary (first) image,
	# if not done previously
	eval {
		require Image::Imlib2;
		Image::Imlib2->import();
	};
	if ($@) {
		carp ("can't use Image::Imlib2 (libimage-imlib2-perl) - can't create thumbnail");
		goto nothumb;
	}
	print ("creating thumbnail\n") if $Debug>0;
	my $orig = Image::Imlib2->load($localfile);
	#my $height = $tn->height;
	# you can set $x or $y to zero and it will maintain aspect ratio
	my $tn = $orig->create_scaled_image(0,120);
	my $tn_localpath="mamba/".$dir."/tn_".$fname;
	my $tn_localfile=$prefix."/".$tn_localpath;
	$tn->save($tn_localfile);
	print ("dumped ".$tn_localpath."\n") if $Debug>0;
	$self->{icon_localpath} = $tn_localpath;
nothumb:

   } # new image
} # images

return 1;
} # copy_images()



=head2 sync_with_db

my $rv = $she->sync_with_db ($dbh[, $path, $me]);

Performs merge_from_db() (may return false, if record is missing), then copy_to_db().
Takes connected database handler as mandatory argument. It must be opened with AutoCommit=>0.

If $path and $me are supplied, then prior to SQL push, 
fetches new images using $me of class Dating::Me and stores them in filesystem "database" under $path.

Returns result of copy_to_db().

=cut

sub sync_with_db {

my $self=shift;
my $dbh=shift or do { carp "sync_with_db: \$dbh argument required"; return 0 };
my $path=shift;
my $me=shift;

$self->merge_from_db($dbh);
return $self->copy_to_db($dbh, $path, $me);

} # sync_with_db



=head1 Analysis methods

For content analysis, use the aggregating functions below, 
or any attribute.
Avoid using {manual}/{copypaste} attributes directly for anything other than determining if 
user entered something, because structure of these attributes are service-specific.

=head2 distinctions

=head2 distinctions_available

=head2 distinctions_wanted

Returns any information which can distinct the profile from another.

This includes any manually entered strings: textareas, diaries, chats/dialogs (if available), nickname, photo captions etc, 
as well as items choosen from large enough lists, for example, "interests" in mamba.
Strings found by web search (copypaste attribute) are not included.

No arguments.
Return value is concatenated scalar, suitable for regex match.
Always returns at least an empty string.

distinctions_available returns all strings which MAY contain information about what user currently has: characted, interests, business etc.

distinction_wanted returns all strings which MAY contain information about what user wants: future, partner, dating goals etc.

For Mamba, all three methods currently return the same.

=cut

sub distinctions {

my $self=shift;
my $r;
my $image_captions; for (keys ($self->{images})) {
	my $c=$self->{images}->{$_}->{caption};
	if (defined($c) and ($c !~ qr/^$/)) {
		$image_captions .= $c.";";
	}
}
my $spcont; 
if (defined($self->{manual}->{selfportrait})) {
	for (keys ($self->{manual}->{selfportrait})) {
		my $c=$self->{manual}->{selfportrait}->{$_};
		if (defined($c) and ($c !~ qr/^$/)) {
			$spcont .= $c.";";
		}
	}
}
# greeting
# want_to_find
# sex_related
# selfportrait (hash of question=>answer)
# diary (hash of title=>content)

my $d = Data::Dumper->new( [
  $self->{manual}->{greeting}, 
  $self->{manual}->{want_to_find},
  $self->{manual}->{sex_related},
  $spcont,
  $self->{manual}->{diary},
  $self->{interests}, 
  $image_captions
] );

$d->Indent(0);
my $dist=$d->Dump;
$dist =~ s/(\[\]|undef)//g;
return $dist;
} # distinctions


sub distinctions_available {
my $self=shift;
return $self->distinctions;
} # distinctions_available


sub distinctions_wanted {
my $self=shift;
return $self->distinctions;
} # distinctions_wanted



=head2 copypasted

Returns any information which can be suspected as copypasted, 
i.e., "copypaste" attribute formatted as single scalar string.

No arguments.
Always returns at least an empty string.
=cut

sub copypasted {

my $self=shift;

# not the same set as distinctions! but smaller
my $d = Data::Dumper->new( [
  $self->{copypaste}->{greeting}, 
  $self->{copypaste}->{want_to_find},
  $self->{copypaste}->{sex_related},
  $self->{copypaste}->{diary}
 ]);

$d->Indent(0);
my $cp=$d->Dump;
$cp =~ s/(\[\]|\{\}|undef)//g;
return $cp;
} # copypasted



=head2 sex_related

Returns any scalars, arrays or hashes related to sex 
as single string, concatenated with colons and semicolons.

No arguments.
Always returns at least an empty string.
Don't confuse this function with {manual}->{sex_related} attribute.
=cut

sub sex_related {

my $self=shift;

my $d = Data::Dumper->new( [
  $self->{manual}->{sex_related}, 
  $self->{sexkeywords}
 ]);

$d->Indent(0);
my $ret=$d->Dump;
$ret =~ s/(\[\]|\{\}|undef)//g;
unless (defined $ret) {$ret=""};
return $ret;
} # sex_related



=head1 Misc functions

=head2 bmi

Returns Body Mass Index, if it can be calculated. "In the 1990s the World Health Organization (WHO) decided that a BMI of 25 to 30 should be considered overweight and a BMI over 30 is obese".

=cut

sub bmi {

my $self=shift;

if (defined($self->{height}) and defined($self->{weight}) 
 and $self->{height}>0 and $self->{weight}>0) {
	return $self->{weight} / (($self->{height}/100) * ($self->{height}/100));
} else {return undef};

} # bmi


=head1 LICENSE

Copyright 2012-2014, Anatoly Schrödinger <weirdo@noipmail.com>

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
See L<http://dev.perl.org/licenses/artistic.html>

=head1 SEE ALSO

L<Dating::Me>

Repository: L<https://github.com/psywave/dating>

=cut


1;

