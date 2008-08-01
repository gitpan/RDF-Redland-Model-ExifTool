#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'RDF::Redland::Model::ExifTool' );
}

diag( "Testing RDF::Redland::Model::ExifTool $RDF::Redland::Model::ExifTool::VERSION, Perl $], $^X" );
