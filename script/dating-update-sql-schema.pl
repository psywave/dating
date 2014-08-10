#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use Dating::misc;
use Getopt::Std;
use DBI();

sub helpexit {
	my $m = shift; print STDERR $m."\n" if $m;
	print STDERR "usage: $0 [-H sqlhost] -D sqldatabase -U sqluser -P sqlpassword\n";
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


print STDERR Dating::misc::update_sql_schema($dbh) ? "success\n" : "failed\n";


$dbh->disconnect;
1;

