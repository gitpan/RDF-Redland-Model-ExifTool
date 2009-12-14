use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'RDF::Redland::Model::ExifTool',
    AUTHOR              => 'Andrew Flint <andy@theflints.net.nz>',
    VERSION_FROM        => 'lib/RDF/Redland/Model/ExifTool.pm',
    ABSTRACT_FROM       => 'lib/RDF/Redland/Model/ExifTool.pm',
    EXE_FILES           => [ 'exif2rdf' ],
    PL_FILES            => {},
    PREREQ_PM => {
	'Config::General' =>   0,	# parses configuration files
	'Getopt::Long' =>      0,	# parses arguments for script exif2rdf
        'HTML::Entities' =>    0,	# encodes literal statement objects
					# with HTML entities
	'Image::ExifTool' =>   0,	# reads Exif meta data from files
	'RDF::Redland' => 1.0006,	# parses and serializes RDF,
					# don't use 1.00054 from CPAN
					# that fails "make test"
	'Regexp::Common' =>    0,	# validates predicate URIs
	'Test::More' =>        0,
	'Test::Simple' =>      0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'RDF-Redland-Model-ExifTool-*' },
);
