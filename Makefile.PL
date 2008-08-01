use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'RDF::Redland::Model::ExifTool',
    AUTHOR              => 'Andrew Flint <andrew@theflints.net.nz>',
    VERSION_FROM        => 'lib/RDF/Redland/Model/ExifTool.pm',
    ABSTRACT_FROM       => 'lib/RDF/Redland/Model/ExifTool.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'RDF-Redland-Model-ExifTool-*' },
);
