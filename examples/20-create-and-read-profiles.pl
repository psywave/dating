#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use Dating::She;
use Carp;
use Getopt::Std;
use DBI();

sub helpexit {
	my $m = shift; print STDERR $m."\n" if $m;
	print STDERR "usage: $0 [-H sqlhost] \n\t-D sqldatabase -U sqluser -P sqlpassword\n";
	exit(0);
}


# sub main

my %args; getopts('hH:D:U:P:', \%args);
if (defined $args{h}) { helpexit }

my $must = " must be specified";
my $sqlhost = $args{H} || "localhost";
my $sqldb = $args{D} || helpexit "database name".$must;
my $sqluser = $args{U} || helpexit "database username".$must;
my $sqlpass = $args{P} || helpexit "database password".$must;

my $dbh = DBI->connect("DBI:mysql:database=".$sqldb.";host=".$sqlhost,
    $sqluser, $sqlpass, {'RaiseError'=>1, AutoCommit=>0});
$dbh->do('SET NAMES utf8');
$dbh->{'mysql_enable_utf8'} = 1;


######## create profile

my $she1 = Dating::She->new();
$she1->{ctime} = time();
$she1->{id} = "test/1";
$she1->{nick} = "Test User 1";
$she1->{birth} = 1983;
#...
$she1->copy_to_db ($dbh);


######## read profile

my $she2 = Dating::She->new_from_db ("test/1", $dbh);
print "got ".$she2->{nick}.", ".((localtime)[5] + 1900 - $she2->{birth})." years old\n";


$dbh->disconnect;
1;

