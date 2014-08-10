#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use Dating;
use Carp;
use Getopt::Std;
use DBI();

sub helpexit {
	my $m = shift; print STDERR $m."\n" if $m;
	print STDERR "usage: $0 -u login -p password [-c location] [-H sqlhost] \n\t-D sqldatabase -U sqluser -P sqlpassword\n";
	exit(0);
}

sub get_one {
	my $url=shift; my $me=shift; my $dbh=shift;
	my $image_path=".";
	my $she = Dating::She->new_from_url ($url, $me) || return undef;

	# if you have more than one account (read INSTALL), 
	# use them here:
	#$she->update_from_page ($me2, pagekey=>'main');
	#$she->update_from_page ($me3,...

	$she->sync_with_db ($dbh, $image_path, $me) || confess "can't sync with db";
	print STDERR "got ".$she->{nick}."\n";
} # get_one


# sub main

my %args; getopts('hu:p:c:H:D:U:P:', \%args);
if (defined $args{h}) { helpexit }

my $must = " must be specified";
my $login = $args{u} || helpexit "dating service account username".$must;
my $password = $args{p} || helpexit "dating service account password".$must;
my $location = $args{c};
my $sqlhost = $args{H} || "localhost";
my $sqldb = $args{D} || helpexit "database name".$must;
my $sqluser = $args{U} || helpexit "database username".$must;
my $sqlpass = $args{P} || helpexit "database password".$must;

my $dbh = DBI->connect("DBI:mysql:database=".$sqldb.";host=".$sqlhost,
    $sqluser, $sqlpass, {'RaiseError'=>1, AutoCommit=>0});
$dbh->do('SET NAMES utf8');
$dbh->{'mysql_enable_utf8'} = 1;

my $me = Dating::Me->new (login=>$login, password=>$password, location=>$location) || die;


# search for three new profiles
for ($me->search( mysex=>'M', sex=>'F', agelow=>25, agehigh=>30, 
  loc_code=>'0_0_0_0', db=>$dbh, maxresults=>3 )) {

	# download found profiles to database
	get_one($_, $me, $dbh) || die;

}


$dbh->disconnect;
1;

