package Dating::misc;

################
#
# Dating - social profile database
#
# Anatoly Schrödinger
# weirdo2@opmbx.org
#
# Dating/misc.pm has auxiliary subroutines for Dating package 
# which are not methods.
#
################

use warnings;
no warnings 'experimental::smartmatch'; # for ~~
use strict;
use utf8;

use Carp;
use LWP::UserAgent;
use URI::Escape;
use HTML::TreeBuilder 5 -weak;
use Data::Dumper;

require Exporter;
our @ISA = qw(Exporter);
# TODO: don't export that much
our @EXPORT = qw(safety_delay netsearch parse_anketa_fields fc_ok fc_fail as_trimmed_text_br as_trimmed_text_notags serialize deserialize update_value $profile_fieldlist @profile_fields $profile_field_placeholders $profile_field_update_placeholders cut_sample trunc2 janis tid_is_runtime sql_statement_debug keybts city_coordinates secs2str);

our $VERSION = "1.00";
our $Debug;

$Debug = 1 unless defined $Debug;
# 1 - short overview of execution flow
# 2 - debug


our $NOT_SUPPLIED=-1;

# ctime must be first
# id is not here, it's a key
our @profile_fields = (qw( ctime               nick              realname          sex               birth             city              location          profession        relations         divorced          children          sexrate           nphoto            replyrate         specialeffort     seen              targetsex         targetagelow      targetagehigh     wantcommunicate   wantrelations     wantmeeting       wantsex           wantmarriage      wantmoney         smoking           height            weight            fat               incomehigh        optional          pages             distance          interests         manual           sexkeywords     education    languages   images      copypaste        location_lat        location_lon    icon_localpath    city_lat   city_lon));
our $profile_fieldlist = join ", ", @profile_fields;
our $profile_field_placeholders = join ", ", map {'?'} @profile_fields;
our $profile_field_update_placeholders = join ", ", map {$_.'=?'} @profile_fields;


=encoding UTF-8

=head1 NAME

Dating::misc - dating auxiliary functions

=head1 SYNOPSIS

  use Dating::misc;

=head1 About

Dating::misc represents auxiliary subroutines for Dating package 
which are not methods.

Almost all are exported by default.


=head2 safety_delay

Delay for limiting HTTP requests rate to make dating site happy (currently 2 sec for mamba).

=cut
sub safety_delay {
sleep (2);
}


=head2 fc_ok

=head2 fc_fail

Feature detection rate accounting.
Track the rate of attributes detection (signature appearance), 
fc_ok resets the counter,
fc_fail issues warning when it falls above threshold

fc_ok ($dsc, $maxmiss);
fc_fail ($dsc, $maxmiss);

$dsc - feature description
$maxmiss - maximum count of .... before issuing warning

=cut
our %feature_fail;

sub fc_ok {
my $dsc = shift;
my $maxmiss = shift;
$feature_fail{$dsc}=0;
} # fc_ok

sub fc_fail {
my $dsc = shift;
my $maxmiss = shift;
$feature_fail{$dsc}++;
if ( ($maxmiss==0) || (($feature_fail{$dsc} % $maxmiss)==0) ) {
	#my $a=$Carp::MaxArgLen; $Carp::MaxArgLen=14;
	#cluck ("feature \"".$dsc."\" fail count ".$feature_fail{$dsc}." is above ".$maxmiss." threshold");
	#$Carp::MaxArgLen=$a;
	carp ("feature \"".$dsc."\" fail count ".$feature_fail{$dsc}." is above ".$maxmiss." threshold");
}
} # fc_fail


=head2 as_trimmed_text_br

HTML::Element::as_trimmed_text() replacement
to handle mamba's <br /> in the middle of text correctly.

$result = as_trimmed_text_br ($element);

=cut
sub as_trimmed_text_br {
my $self=shift;
for ($self->look_down(_tag=>'br')) {
	$_->replace_with(" ");
}
return $self->as_trimmed_text;
}


=head2 as_trimmed_text_notags

HTML::Element::as_trimmed_text() replacement
which doesn't descend into inner tags.

$result = as_trimmed_text_notags ($element);

=cut
sub as_trimmed_text_notags {
my $self=shift;
my $nt="";
foreach my $item_r ($self->content_refs_list) {
	next if ref $$item_r;
	$nt=$nt.$$item_r." ";
}
$nt =~ s/^\s+|\s+$//g ;
return $nt;
}


=head2 parse_anketa_fields

Mamba-specific. Obtains common Mamba "anketa" structure from HTML::TreeBuilder object 
passed as argument.
Probably you never need to call this manually. 

%fields = parse_anketa_fields ($parser);

=cut
sub parse_anketa_fields {

# parses common mamba structure:
# <div class="b-anketa_field">
#	<div class="b-anketa_field-title">Отношения:</div>
#	<div class="b-anketa_field-content">Нет</div>
# </div>

my $parser=shift;
my %fields;
#
my @fpaf01=("mamba parse_anketa_fields: div class b-anketa_field", 0); my $fcp=0;
my @fpaf02=("mamba parse_anketa_fields: div class b-anketa_field-title in b-anketa_field", 0);
my @fpaf03=("mamba parse_anketa_fields: div class b-anketa_field-content after b-anketa_field-title", 0); my $fcont;
my @fpaf04=("mamba parse_anketa_fields: content is li list", 50);
my @fpat05=("mamba parse_anketa_fields: content class var-other (entered manually)", 150);
#
for my $div ($parser->look_down( _tag => 'div', class => "b-anketa_field")) {
	fc_ok(@fpaf01); $fcp=1;
	my $field_title; my $field_content=""; my $is_entered_manually;
	if (my $d2 = $div->look_down( _tag => 'div', class => "b-anketa_field-title")) {
		fc_ok(@fpaf02);
		$field_title = $d2->as_trimmed_text;
		$fcont=0;
		for my $d3 ($div->look_down( _tag => 'div', class=>qr/b-anketa_field-content/ )) {
			fc_ok(@fpaf03); $fcont=1;
			if ($d3->{class} =~ /var-other/) {
				fc_ok(@fpat05);
				$is_entered_manually=1;
			} else {
				fc_fail(@fpat05);
				$is_entered_manually=0;
			}
			my $content_is_list;
			for my $d4 ($d3->look_down (_tag => 'li')) {
				$field_content .= as_trimmed_text_br($d4) . ";" ;
				$content_is_list=1;
			}
			if ($content_is_list) {
				fc_ok(@fpaf04);
			} else {
				fc_fail(@fpaf04);
				$field_content = as_trimmed_text_br($d3);
			}
			last;
		}
		unless ($fcont) { fc_fail(@fpaf03); }
	} else {
		fc_fail(@fpaf02);
	}
	print STDERR "title: \"$field_title\" content: \"$field_content\"\n" if $Debug>1;
	$fields{$field_title} = [ $field_content, $is_entered_manually ];
}
unless ($fcp) { fc_fail(@fpaf01); }
return %fields;
} # parse_anketa_fields



our $netsearch_results_cache = {};

=head2 netsearch

$proof = netsearch ($where, $ua);

Queries web search engine for exact (quoted) ten words of $where, starting from 2nd word,
using $ua LWP::UserAgent object, perhaps Dating::Me->{anon_ua}.
Returns copypaste proof URL, if found (links to dating service itself are ignored), 
else undef.

Responces are cached in package context.

=cut
sub netsearch {

my $where=shift;
my $ua=shift;
my $chunk;

unless ($where =~ /\w+\W+((\w+\W+){10})/) { return undef }  # too small to search

#print STDERR "chunk after word match: '$chunk'\n";
$chunk = $1;
$chunk =~ s/\"//g;

foreach ( keys %{$netsearch_results_cache} ) {
	if ($_ eq $chunk) {
		print STDERR "netsearch: found in internal cache\n" if $Debug>1;
		return $netsearch_results_cache->{$_};
	}
}

#return netsearch_google ($chunk, $ua);  # doesn't allow public proxies and doesn't respect privacy
return netsearch_duckduckgo ($chunk, $ua);

} # netsearch


=head2 netsearch_google

$proof = netsearch_google ($chunk, $ua);

Netsearch google backend, cache not used.
Don't call it directly, only netsearch() should.

=cut
sub netsearch_google {

my $chunk=shift;
my $ua=shift;
my ($gres, $gcont, $rest, $gitem);

my $link = "http://www.google.com/search?hl=en&source=hp&biw=&bih=&q=".uri_escape_utf8 ("\"".$chunk."\"")."&btnG=Google+Search&gbv=1";
#my $link = "http://www.google.com/search?q=" . uri_escape_utf8 ("\"".$chunk."\"") ;

# Dating::Me should do this?
#$ua = LWP::UserAgent->new(parse_head => 0);
#$ua->agent("Mozilla/5.0 ........"); # google refuses default
safety_delay;
print STDERR "google: requesting \"".$chunk."\"\n" if $Debug>0;
print STDERR "google: link: ".$link."\n" if $Debug>0;
$gres = $ua->get($link);

$gcont = $gres->decoded_content;
if ($Debug>1) {
	open (l_5, ">:utf8", "google_result.html");
	print l_5 $gcont;
	close (l_5);
}

unless ($gres->is_success) {
	carp "google search returns ".$gres->code;
	return undef;
}

$netsearch_results_cache->{$chunk}=undef; # from now on, if not proven otherwise

my @gofc01=("google: \"no results\" response", 30);
my @gofc02=("google: proof (non-dating) url found in results", 200);

if ($gcont =~ /Your search.*did not match any documents|No results found for /) {
	fc_ok(@gofc01);
	return undef;
} else {
	fc_fail(@gofc01);
}

my $t=HTML::TreeBuilder->new();
#$t->utf8_mode(1); # don't?
unless ( $t->parse($gcont) ) {
	carp "google: can't parse\n";
	return undef;
}
$t->eof();

for my $gli ($t->look_down(_tag=>'li', class=>'g')) {
	if (my $ga=$gli->look_down(_tag=>'a')) {
		print STDERR "got link: ".$ga->{href}."\n" if $Debug>1;
		if ($ga->{href} =~ 
  /anketa\.phtml\?oid=|\/mb(\d+)\/|Знакомства Мамба|afolder=|RSS Знакомства|\/id(\/|\&)|\/ru\/diary\//) {
			fc_fail(@gofc02);
		} else {
			print STDERR "proof found!\n" if $Debug>1;
			fc_ok(@gofc02);
			$netsearch_results_cache->{$chunk}=$link;
			return $link;
		}
	}
}

return undef;
} # netsearch_google


=head2 netsearch_duckduckgo

$proof = netsearch_duckduckgo ($chunk, $ua);

Netsearch duckduckgo backend, cache not used.
Don't call it directly, only netsearch() should.

=cut
sub netsearch_duckduckgo {

my $chunk=shift;
my $ua=shift;
my ($greq, $gres, $gcont, $rest, $gitem);

#$ua = LWP::UserAgent->new(parse_head => 0);
#$ua->agent("Mozilla/5.0........");

#$greq = POST "https://duckduckgo.com/html/", [ "q" => "\"".$chunk."\"" ];   # need GET proof link anyway
my $link = "https://duckduckgo.com/html/&q=".uri_escape_utf8 ("\"".$chunk."\"");
$greq = HTTP::Request->new(GET => $link);
#$lreq->header("Referer" => "Referer: ....");

safety_delay;
print STDERR "duckduckgo: requesting \"".$chunk."\"\n" if $Debug>0;
$gres = $ua->request($greq);

$gcont = $gres->decoded_content;
if ($Debug>1) {
	open (l_5, ">:utf8", "duckduckgo_result.html");
	print l_5 $gcont;
	close (l_5);
}

unless ($gres->is_success) {
	carp "duckduckgo search returns ".$gres->code;
	return undef;
}

$netsearch_results_cache->{$chunk}=undef; # from now on, if not proven otherwise

my @dofc01=("duckduckgo: \"no results\" response", 30);
my @dofc02=("duckduckgo: proof (non-dating) url found in results", 200);

if ($gcont =~ /<span class="no-results">/) {
	fc_ok(@dofc01);
	return undef;
} else {
	fc_fail(@dofc01);
}

my $t=HTML::TreeBuilder->new();
#$t->utf8_mode(1); # don't?
unless ( $t->parse($gcont) ) {
	carp "duckduckgo: can't parse\n";
	return undef;
}
$t->eof();

# <div class="results_links results_links_deep web-result">
for my $dres ($t->look_down(_tag=>'div', class=>qr/results_links/)) {
	# <a rel="nofollow" class="large" href="http://www.i
	if (my $ra=$dres->look_down(_tag=>'a', class=>'large')) {
		print STDERR "got link: ".$ra->{href}."\n" if $Debug>1;
		if ($ra->{href} =~ 
  /anketa\.phtml\?oid=|\/mb(\d+)\/|Знакомства Мамба|afolder=|RSS Знакомства|\/id(\/|\&)|\/ru\/diary\//) {
			fc_fail(@dofc02);
		} else {
			print STDERR "proof found!\n" if $Debug>1;
			fc_ok(@dofc02);
			$netsearch_results_cache->{$chunk}=$link;
			return $link;
		}
	}
}

return undef;
} # netsearch_duckduckgo


=head2 city_coordinates

Returns city coordinates as found in geonames sql tables (see docs),
undef if not found.

Currently searches for russian names only and ignores country.

($lat, $lon) = city_coordinates ($dbh, $country, $city);  # "Rossiya", "Defaultcity"

=cut
sub city_coordinates {

my $city_search_st="

SELECT geoname.latitude, geoname.longitude
FROM geoname INNER JOIN alternatename 
  ON geoname.geonameid=alternatename.geonameid 
WHERE alternatename.isoLanguage='ru' AND 
  ( alternatename.alternateName=? OR alternatename.alternateName=? )
ORDER BY geoname.population DESC 
LIMIT 1

";
my $dbh=shift;
my $country=shift; # TODO: use it
my $city_name=shift;

my $city_coord_lol = 
  $dbh->selectall_arrayref ($city_search_st, {}, 
  $city_name, "Город ".$city_name) or do {
	carp ("searching \"$city_name\" in geonames tables: ".DBI->errstr());
	return undef, undef;
};
my $la=$city_coord_lol->[0][0]; my $lo=$city_coord_lol->[0][1];
unless ($la && $lo) {
	carp ("\"$city_name\" coordinates not found in geonames tables") if $Debug>0;
	return undef, undef;
}
return $la, $lo;
} # city_coordinates


=head2 update_sql_version_stamp_and_commit

Internal sub, don't call it. Not exported.

=cut
sub update_sql_version_stamp_and_commit {
my $dbh=shift;
my $ver=shift;
$dbh->do ("
INSERT INTO versions (what, version)
	VALUES ('schema', ".$ver.")
	ON DUPLICATE KEY UPDATE version=".$ver."
") or do {
	carp ("ins curver: ".DBI->errstr());
	$dbh->rollback;
	return 0;
};
$dbh->commit;
carp ("schema updated to ".$ver) if $Debug>0;
return 1;
} #update_sql_version_stamp_and_commit


=head2 update_sql_schema

Updates SQL schema to current version. Run it after modules update.

Takes connected database handler (use AutoCommit=0) as argument.

my $rv = Dating::misc::update_sql_schema($dbh);

=cut
sub update_sql_schema {

my $dbh=shift; 
until ((defined $dbh) and (ref $dbh)) { carp "update_sql_schema: \$dbh argument required"; return 0 };

$dbh->do ("

CREATE TABLE IF NOT EXISTS versions (
  what              CHAR(64),
  version           INT,
  PRIMARY KEY (what)

)") or do {
	carp ("cr tab versions: ".DBI->errstr());
	$dbh->rollback;
	return 0;
};

my $ver_lol=$dbh->selectall_arrayref (" 

SELECT version FROM versions
WHERE what='schema'

");
my $ver=$ver_lol->[0][0];
until (defined $ver) { $ver=0 }
carp ("schema initial version: ".$ver) if $Debug>0;

if ($ver < 2011050400) {

	$dbh->do ("

CREATE TABLE IF NOT EXISTS profiles (
  ctime             INT,
  id                CHAR(64) NOT NULL,
  nick              CHAR(128),
  realname          CHAR(128),
  sex               CHAR(1),
  birth             SMALLINT,
  city              CHAR(128),
  location          CHAR(64),
  profession        CHAR(128),
  education         CHAR(128),
  relations         TINYINT,
  divorced          TINYINT,
  children          TINYINT,
  sexrate           TINYINT,
  nphoto            SMALLINT,
  replyrate         TINYINT,
  specialeffort     TINYINT,
  seen              SMALLINT,
  targetsex         CHAR(2),
  targetagelow      TINYINT,
  targetagehigh     TINYINT,
  wantcommunicate   TINYINT,
  wantrelations     TINYINT,
  wantmeeting       TINYINT,
  wantsex           TINYINT,
  wantmarriage      TINYINT,
  wantmoney         TINYINT,
  smoking           TINYINT,
  height            SMALLINT,
  weight            SMALLINT,
  fat               TINYINT,
  incomehigh        TINYINT,
  optional          TINYINT,
  -- serialized hash
  pages             VARCHAR(4096),
  -- serialized hash
  distance          VARCHAR(4096),
  -- serialized hash
  interests         VARCHAR(4096),
  -- serialized hash
  manual            VARCHAR(65535),
  -- serialized hash
  copypaste         VARCHAR(65535),
  sexkeywords       VARCHAR(1024),
  languages         VARCHAR(1024),
  -- serialized hash
  images            VARCHAR(32767),
  icon_localpath    VARCHAR(1024),
  PRIMARY KEY (id)

)" ) or do {
		carp ("cr tab profiles: ".DBI->errstr());
		$dbh->rollback;
		return 0;
	};
	$ver=2011050400;
	unless (update_sql_version_stamp_and_commit ($dbh, $ver)) { return 0 }
} # $ver < 2011050400


if ($ver < 2014041600) {

	eval {
		$dbh->do ("

		ALTER TABLE profiles 
		ADD location_lat FLOAT, ADD location_lon FLOAT

		");
		my $id_loc_lol=$dbh->selectall_arrayref ( "

		SELECT id, location FROM profiles 
		WHERE location IS NOT NULL AND location<>''

		" );
		my $loc_ins_st=$dbh->prepare ("

		UPDATE profiles 
		SET location_lat=?, location_lon=?
		WHERE id=?

		");
		for (@{$id_loc_lol}) {
			my $id=$_->[0]; my $loc=$_->[1];
			if ($loc =~ /^([\d\.]+)\s+([\d\.]+)$/) {
				my $lat=$1; my $lon=$2;
				$loc_ins_st->execute ($lat, $lon, $id) or do {
					carp ("ins lat,lon: ".DBI->errstr());
					$dbh->rollback;
					return 0;
				};
				print STDERR "added lat=".$lat." lon=".$lon." for id=".$id."\n" if $Debug>1;
			} else {
				carp ("can't parse location for id=".$id);
				$dbh->rollback;
				return 0;
			}
		} # for id_loc_lol
	}; # eval

	if ($@) {
		carp ("adding lat,lon eval block: ".$@);
		$dbh->rollback;
		return 0;
	}

	$ver=2014041600;
	unless (update_sql_version_stamp_and_commit ($dbh, $ver)) { return 0 }
} # $ver < 2014041600


if ($ver < 2014042500) {

	eval {
		$dbh->do ("

		ALTER TABLE profiles 
		ADD city_lat FLOAT, ADD city_lon FLOAT

		");
		my $id_city_lol=$dbh->selectall_arrayref ( "

		SELECT id, city FROM profiles 
		WHERE city IS NOT NULL AND city<>''

		" );
		my $ins_st=$dbh->prepare ("

		UPDATE profiles 
		SET city_lat=?, city_lon=?
		WHERE id=?

		");
		id_city: for (@{$id_city_lol}) {
			my $id=$_->[0]; my $city=$_->[1];
			if ($city =~ /^(.*?),\s*(.*)$/) {
				my $country=$1; my $city_name=$2;
				my ($la, $lo) = city_coordinates ($dbh, $country, $city_name);
				until ($la && $lo) {
	 				carp ("city coordinates not found, skipping") if $Debug>0;
					next id_city;
				}
				$ins_st->execute ($la, $lo, $id) or do {
					carp ("ins city la/lo: ".DBI->errstr());
					next id_city;
				};
				print STDERR "added city_lat=".$la." lon=".$lo." for id=".$id."\n" if $Debug>1;
			} else {
				carp ("can't parse city for id=".$id);
				next id_city;
			}
		} # for city_loc_lol
	}; # eval

	if ($@) {
		carp ("adding city_lat,lon eval block: ".$@);
		$dbh->rollback;
		return 0;
	}

	$ver=2014042500;
	unless (update_sql_version_stamp_and_commit ($dbh, $ver)) { return 0 }
} # $ver < 2014042500


return 1;
} # update_sql_schema



=head2 serialize

Serializes dating attribute producing scalar suitable as SQL value.

Convention is: scalar passes as is, reference is encoded using Data::Dumper and prepended by 'EVAL' mark.
Single quotes and backslashes are irreversibly replaced with similar unicode characters.
undef is correctly preserved.

my $serialized = serialize ($raw);

=cut

sub serialize {

my $what=shift;

if (ref $what) {
	my $d = Data::Dumper->new( [$what] );
	$d->Indent(0);
	return 'EVAL'.$d->Dump;
} else {
	return $what;
}

} # serialize



=head2 deserialize

Reverse procedure for serialize().

my $raw = deserialize ($serialized);

Returns deserialized structure (it may be undef) if success, 
undef if failed.
TODO: raise $@ is failed.

=cut

sub deserialize {

my $s=shift;

if (!defined ($s)) {
	return undef;
} elsif ($s !~ /^EVAL/) {
	# scalar is decoded as is
	return $s;
} elsif ($s =~ /^EVAL(\{|\[)/) {
	# hash or array are decoded as eval after Dumper,
	my $p = substr ($s,4);
	my $r = eval ($p);
	if ($@) { carp "deserialize eval error: ".$@; }
	return $r;
} else {
	carp "deserialize: serialized data has unknown type, header follows: '".substr($s, 0, 5)."'";
	return undef;
}

} # deserialize



=head2 update_value

Conditionally merges $src into $dst and returns result.

my $new_dst_value = update_value ($src, $dst, $src_is_newer)

If $dst is undef, then return $src.
If $dst is a reference to hash, then update this hash with members of $src whose keys are not in $dst, or all members, if $src_is_newer (i.e., ctime(src)>ctime(dst)).
If $dst is an array, it's expanded with $src members which are not in $dst.
For other $dst type, $src is simply copied to $dst, if $src is newer.

This is a common approach of updating dating profile attributes around the Dating package.

=cut

sub update_value {

my $src=shift;
my $dst=shift;
my $src_is_newer=shift;

if (!defined($dst)) { return $src }

if (ref($dst)=~"HASH") {
	foreach (keys %{$src}) {
		if ((!defined(${$dst}{$_})) or $src_is_newer) {
			${$dst}{$_}=${$src}{$_};
		}
	}
}
elsif (ref($dst)=~"ARRAY") {
	foreach (@{$src}) {
		if (!($_ ~~ @{$dst})) {
			push @{$dst}, $_;
		}
	}
}
elsif ($src_is_newer) {
	$dst=$src;
}

return $dst;

} # update_value



=head2 cut_sample

$sample = cut_sample ($where, $needle);

=cut
sub cut_sample {
my $where=shift;
my $needle=shift;

#print STDERR "\nwhere=".$where."\nneedle=".$needle."\n";
if (ref ($where)) {
	confess ("cut_sample called on reference: ".Dumper($where));
}

if ($where =~ /(.{0,17})\Q$needle\E(.{0,17})/i) {
	my $f = $&; $f =~ s/\Q$needle\E/\[\[$needle\]\]/;
	return $f;
} else { return undef };

} # cut_sample



=head2 trunc2

$ready_for_html = trunc2 (3.140000000000364663);

=cut
sub trunc2 {
my $what=shift;
return sprintf ("%.2f", $what);
} # trunc2



=head2 janis

Calculates a coefficient of imbalance ("Janis coefficient" in USSR literature):

use Dating::misc;
$C = janus ($f,$n,$r,$t);  # statements: positive, negative, related, total

http://brainmod.ru/business/content-analysis/

Irving L. Janis, Raymond H. Fadner. A coefficient of imbalance for content analysis // Psychometrika, June 1943, Volume 8, Issue 2, pp 105-119.

They are additive and normalized to -1..1,
but not normalized or scaled to unit variance relative to entire dataset.

See usage example in examples/analysis.pl under $tests->'Introversion'.

=cut

sub janis {

my ($f,$n,$r,$t)=@_;

print STDERR "janis: f=".$f." n=".$n." r=".$r." t=".$t."\n" if $Debug>1;

if ($r*$t==0) {
	return undef
}

if ($f>$n) {
	return (($f*$f - $f*$n) / ($r*$t))
} else {
	return (($f*$n - $n*$n) / ($r*$t))
}
} # janis



=head2 tid_is_runtime

if (tid_is_runtime (60120)) {

=cut
sub tid_is_runtime {
my $tid=shift;
if ($tid =~ /^(5|6)/) {return 1} else {return 0}
}



=head2 sql_statement_debug

print STDERR sql_statement_debug ($statement_with_placeholders, @values);

=cut
sub sql_statement_debug {
my ($st, @val)=@_;

for (@val) { $st =~ s/\?/\'$_\'/ }   # warning: it doesn't quote properly
return $st;

} # sql_statement_debug



=head2 keybts

Russian qwerty->ycuken transliteration.

my $russian = keybts("fcgbhfynrf");

=cut
sub keybts {
 my %hs=('q'=>'й' , 'w'=>'ц'  , 'e'=>'у'  , 'r'=>'к', 't'=>'е' ,
         'y'=>'н' , 'u'=>'г' , 'i'=>'ш' , 'o'=>'щ', 'p'=>'з' ,
         "\[" =>'х',"\{"=>'х' , "\]"=>'ъ',"\}"=>'ъ', 'a'=>'ф' , 's'=>'ы', 'd'=>'в',
         'f'=>'а' , 'g'=>'п'  , 'h'=>'р'  , 'j'=>'о', 'k'=>'л' ,
         'l'=>'д' , "\;"=>'ж',"\:"=>'ж' , "\'"=>'э',"\""=>'э' , 'z'=>'я', 'x'=>'ч',
         'c'=>'с', 'v'=>'м', 'b'=>'и'  , 'n'=>'т', 'm'=>'ь'  ,
         "\,"=>'б',"\<"=>'б', "\."=>'ю',"\>"=>'ю');
my $z=shift;
for (keys %hs) {
	$z =~ s/\Q$_\E/$hs{$_}/gi;
}
return $z;
} # keybts



=head2 secs2str

Returns time delta in human-reabable format, not using any special module.
Localized time names are provided as arguments.

	my $str = secs2str ($seconds,   $year_str,$month_str,$day_str,$hour_str,$min_str,$sec_str);
	my $str = secs2str (12367,  "year","month","days","hours","minutes","seconds");

=cut
sub secs2str {

my ($ts, $year_str,$month_str,$day_str,$hour_str,$min_str,$sec_str) = @_;

my $y = int ($ts/31557600);
my $mo = int ($ts/2629800);
my $d = int ($ts/86400);
my $h = int ($ts/3600);
my $mi = int ($ts/60);

if ($y > 1) { return $y." ".$year_str }
if ($mo > 1) { return $mo." ".$month_str }
if ($d > 1) { return $d." ".$day_str }
if ($h > 1) { return $h." ".$hour_str }
if ($mi > 1) { return $mi." ".$min_str }
return $ts." ".$sec_str;

} # secs2str



=head1 LICENSE

Copyright 2012-2014, Anatoly Schrödinger <weirdo2@opmbx.org>

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
See L<http://dev.perl.org/licenses/artistic.html>

=head1 SEE ALSO

L<Dating::She>, L<Dating::Me>

Repository: L<https://github.com/psywave/dating>

=cut

1;

