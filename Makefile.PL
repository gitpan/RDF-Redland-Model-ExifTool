use 5.006;
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
      'Config::General' =>   0,  # parses configuration files
      'HTML::Entities' =>    0,  # encodes literal statement objects
      'Image::ExifTool' =>   0,  # reads Exif meta data from files
      'RDF::Redland' => 1.0006,  # parses and serializes RDF,
                                 # avoid version 1.00054 from CPAN
                                 # that fails "make test"
      'Regexp::Common' =>    0,  # validates predicate URIs
      'URI' =>               0,  # constructs file URIs from path names
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'RDF-Redland-Model-ExifTool-*' },
);
