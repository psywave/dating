package Dating::math;

################
#
# Dating - social profile database
#
# Anatoly Schrödinger
# weirdo2@opmbx.org
#
# Dating/math.pm is for custom math mini-lib and geo functions
# Warning: this file lacks POD
#
################

use warnings;
use strict;
use Math::Trig;
use Carp;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(trilaterate distance); 

our $VERSION = "1.00";
our $Debug;

$Debug = 1 unless defined $Debug;
# 1 - short overview of execution flow
# 2 - debug

######### my vector algebra mini-lib
sub norm {
my $aref=shift; my @a=@$aref;
my $z=0.0;
foreach (@a) { $z+=($_*$_); }
return sqrt($z);
}
sub subst {
my $aref=shift; my @a=@$aref;
my $bref=shift; my @b=@$bref;
my @res;
for (my $i=0; $i<=$#a; $i++) { $res[$i] = $a[$i]-$b[$i]; }
return @res;
}
sub ad {
my $aref=shift; my @a=@$aref;
my $bref=shift; my @b=@$bref;
my @res;
for (my $i=0; $i<=$#a; $i++) { $res[$i]=$a[$i]+$b[$i]; }
return @res;
}
sub dot {
my $aref=shift; my @a=@$aref;
my $bref=shift; my @b=@$bref;
my $d;
for (my $i=0; $i<=$#a; $i++) { $d+=$a[$i]*$b[$i]; }
return $d;
}
sub ar_div_scal {
my $aref=shift; my @a=@$aref;
my $d=shift;
my @res;
foreach (@a) { push @res, ($_/$d); }
return @res;
}
sub ar_mul_scal {
my $aref=shift; my @a=@$aref;
my $d=shift;
my @res;
foreach (@a) { push @res, ($_*$d); }
return @res;
}
sub cross3 {
my $uref=shift; my @u=@$uref;
my $vref=shift; my @v=@$vref;
my @s;
$s[0]=$u[1]*$v[2]-$u[2]*$v[1];
$s[1]=$u[2]*$v[0]-$u[0]*$v[2];
$s[2]=$u[0]*$v[1]-$u[1]*$v[0];
return @s;
}
sub elem {
my $aref=shift; my @a=@$aref;
my $ndx=shift;
return $a[$ndx];
}
######## end of array algebra

######## my geo helpers
#assuming elevation = 0
my $earthR = 6371;

sub geo2xyz {
#Convert geodetic Lat/Long to ECEF xyz
#using authalic sphere
#if using an ellipsoid this step is slightly different
my $LatA = deg2rad(shift);
my $LonA = deg2rad(shift);
my @xyz;
$xyz[0] = $earthR *(cos($LatA) * cos($LonA));
$xyz[1] = $earthR *(cos($LatA) * sin($LonA));
$xyz[2] = $earthR *(sin($LatA));
return @xyz;
}

=head2 distance

Takes 4 arguments: lat,lon (degrees) of point A, lat,lon of point B.
Returns distance betweeb A and B in km.

=cut

sub distance {

my $LatA = shift; my $LonA = shift;
my $LatB = shift; my $LonB = shift;

my @P1 = [ geo2xyz($LatA, $LonA) ];
my @P2 = [ geo2xyz($LatB, $LonB) ];

my @s = [ subst(@P2, @P1) ];
return norm (@s);

} # distance

=head2 trilaterate

Takes 9 arguments: lat, lon in degrees, distance in km, ... (for 3 points).
Returns two-member list of trilaterated point coordinates, if result is self-consistent.

=cut

sub trilaterate {

# per https://gis.stackexchange.com/questions/66/trilateration-using-3-latitude-and-longitude-points-and-3-distances/415#415

my $LatA = shift; my $LonA = shift; my $DistA = shift;
my $LatB = shift; my $LonB = shift; my $DistB = shift;
my $LatC = shift; my $LonC = shift; my $DistC = shift;

carp ("trilaterate( $LatA $LonA $DistA  $LatB $LonB $DistB  $LatC $LonC $DistC )") if $Debug>1;

#Convert geodetic Lat/Long to ECEF xyz
my @P1 = [ geo2xyz($LatA, $LonA) ];
my @P2 = [ geo2xyz($LatB, $LonB) ];
my @P3 = [ geo2xyz($LatC, $LonC) ];

#from wikipedia
#transform to get circle 1 at origin
#transform to get circle 2 on x axis
my @sp2p1= [ subst(@P2, @P1) ];
my @sp3p1= [ subst(@P3, @P1) ];
my @ex = [ ar_div_scal ( @sp2p1, norm (@sp2p1)) ];
my $i = dot(@ex, @sp3p1);
my @iex = [ ar_mul_scal (@ex, $i) ];
my @t = [ subst(@sp3p1, @iex) ];
my @ey = [ ar_div_scal (@t, norm(@t)) ];
my @ez = [ cross3 (@ex, @ey) ];
my $d = norm(@sp2p1);
my $j = dot(@ey, @sp3p1);

#from wikipedia
#plug and chug using above values
my $x = (($DistA*$DistA) - ($DistB*$DistB) + ($d*$d)) / (2*$d);
my $y = (($DistA*$DistA) - ($DistC*$DistC) + ($i*$i) + ($j*$j) ) / (2*$j) - (($i/$j)*$x);

my $z2 = ($DistA*$DistA) - ($x*$x) - ($y*$y);
# https://en.wikipedia.org/wiki/Trilateration
# z = +/- sqrt(z2)
# zero, one or two solutions possible.
my $z; if ($z2<0) {
	carp ("trilaterate: no exact solution possible. assuming z=0.") if $Debug>0;
	$z=0;
	#return undef;
} else {
	# we take only one solution
	$z = sqrt($z2);
}

#triPt is an array with ECEF x,y,z of trilateration point
my @mex = [ ar_mul_scal (@ex, $x) ];
my @mey = [ ar_mul_scal (@ey, $y) ];
my @mez = [ ar_mul_scal (@ez, $z) ];
my @aa1 = [ ad (@P1, @mex) ];
my @aa2 = [ ad (@aa1, @mey) ];
my @triPt = [ ad (@aa2, @mez) ];

#convert back to lat/long from ECEF
#convert to degrees
my $lat = rad2deg (asin (elem(@triPt,2) / $earthR));
my $lon = rad2deg (atan2 (elem(@triPt,1), elem(@triPt,0)));

# check
my $rdA = distance ($LatA, $LonA, $lat, $lon);
my $rdB = distance ($LatB, $LonB, $lat, $lon);
my $rdC = distance ($LatC, $LonC, $lat, $lon);
my $ems = "trilateration: inconsistent distance to ";
# if error is more than 25% at more than 3 km
if ((abs($rdA/$DistA-1)>0.25) and ($DistA>3)) {
	carp ($ems."A (".$LatA.",".$LonA."): ".$rdA.", should be ~".$DistA."\n"); return undef;
}
if ((abs($rdB/$DistB-1)>0.25) and ($DistB>3)) {
	carp ($ems."B (".$LatB.",".$LonB."): ".$rdB.", should be ~".$DistB."\n"); return undef;
}
if ((abs($rdC/$DistC-1)>0.25) and ($DistC>3)) {
	carp ($ems."C (".$LatC.",".$LonC."): ".$rdC.", should be ~".$DistC."\n"); return undef;
}

#carp ("trilaterate: ret $lat $lon");
return ($lat, $lon);

} # trilaterate

###### end of geohelpers

1;

