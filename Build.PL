#!/usr/bin/perl -w

use strict;
use Module::Build;

my $build = Module::Build->new
(
	module_name => 'Dating',
	license => 'perl',
	dist_author => 'Anatoly Schrödinger <weirdo@noipmail.com>',
	requires => {
		'perl'=> '5.5.0',
		'Carp' => 0,
		'Data::Dumper' => 0,
		'Exporter' => 0,
		'Math::Trig' => 0,
		'HTTP::Request' => 0,
		'HTTP::Cookies' => 0,
		'LWP::UserAgent' => 0,
		'JSON' => 0,
		'URI::Escape' => 0,
		'HTML::TreeBuilder' => 0,
		'DBI' => 0,
		'Encode' => 0,
		'File::Path' => 0
	},
	recommends => {
		'Image::Imlib2' => 0,
		'LWP::Protocol::socks' => 0,
	},
	scripts => {
		'script/dating-update-sql-schema.pl'
	},
);

$build->create_build_script;

