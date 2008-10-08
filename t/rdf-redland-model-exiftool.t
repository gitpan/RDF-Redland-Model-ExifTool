use strict;
use warnings;

my @GOOD_FILE = ("t/data/no_comment.jpg",
                 "t/data/text_comment.jpg",
                 "t/data/ntriples_comment.jpg",
                 "t/data/turtle_comment.jpg",
                 "t/data/rdfxml_comment.jpg",
                 "t/data/artist_uri.jpg");
my @BAD_FILE = ("t/data/not_a_jpg.txt",
                "t/data/does_not_exist.jpg");

use Test::Simple tests => 24;

use RDF::Redland;
use Image::ExifTool;
use RDF::Redland::Model::ExifTool;

my $exiftool = new Image::ExifTool;
ok(defined $exiftool, "created ExifTool");

my $storage = new RDF::Redland::Storage("hashes", "test",
                  "new='yes',hash-type='memory'");
ok(defined $storage, "created storage for RDF model");

my $model = new RDF::Redland::Model::ExifTool($storage, "");
ok(defined $model, "created RDF model on storage");
ok($model->isa('RDF::Redland::Model::ExifTool'), "model is right type");

my $config = $model->get_exif_config;
ok(defined $config, "got default configuration from model");

my @tag = $model->get_exif_tags;
ok(@tag, "got default list of processable tags from model");

my @error;
foreach my $f (@GOOD_FILE) {
    $exiftool->ImageInfo($f);
    @error = $model->add_exif_statements($exiftool);
    ok(!@error, "processed file $f");
}

foreach my $f (@BAD_FILE) {
    $exiftool->ImageInfo($f);
    @error = $model->add_exif_statements($exiftool);
    ok(@error, "failed to process file $f");
    foreach my $e (@error) {
        print "\t$e\n";
    }
}

foreach my $et ($model, undef) {
    @error = $model->add_exif_statements($et);
    ok(@error, "failed to process ExifTool");
    foreach my $e (@error) {
        print "\t$e\n";
    }
}

my $min_parse = {
    ParseTag => "Comment",
    ParseSyntax => "turtle",
};
my $min_trans  = {
    TranslateTag => {
        Comment => "http://www.w3.org/2003/12/exif/ns#userComment",
    },
};
my $parse_no_syntax =  {
    ParseTag => "Comment",
};
my $bad_trans = {
    ParseTag => "Comment",
    ParseSyntax => "turtle",
    TranslateTag => {
        BadScheme => "ftp://www.theflints.net.nz/lump.tar",
        Undef => undef,
        Empty => "",
        Relative => "../fred/",
    },
};
my $bad_variable = {
    TranslateTag => {
        Comment => "http://www.w3.org/2003/12/exif/ns#userComment",
    },
    BadVariable => 12,
};

foreach my $c ($min_parse, $min_trans, $config) {
    @error = $model->set_exif_config($c);
    ok(!@error, "set configuration");
}

foreach my $c ($parse_no_syntax, $bad_trans, 
               $bad_variable, { }, undef) {
    @error = $model->set_exif_config($c);
    ok(@error, "failed to set bad configuration");
    foreach my $e (@error) {
        print "\t$e\n";
    }
}
