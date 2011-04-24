use strict;
use warnings;

my @GOOD_FILE = ("t/data/no_comment.jpg",
                 "t/data/text_comment.jpg",
                 "t/data/ntriples_comment.jpg",
                 "t/data/turtle_comment.jpg",
                 "t/data/bad_turtle_comment.jpg",
                 "t/data/rdfxml_comment.jpg",
                 "t/data/artist_uri.jpg",
                 "t/data/image+thumb.jpg");
my @BAD_FILE = ("t/data/not_a_jpg.txt",
                "t/data/does_not_exist.jpg");

use Test::Simple tests => 39;

use RDF::Redland;
use Image::ExifTool;
use RDF::Redland::Model::ExifTool;

my $exiftool = new Image::ExifTool;
ok($exiftool, "created ExifTool");

my $storage = new RDF::Redland::Storage("hashes", "exif_meta_data",
                  "new='yes',hash-type='memory'");
ok($storage, "created storage for RDF model");

my $model = new RDF::Redland::Model::ExifTool($storage, "");
ok($model, "created RDF model on storage");
ok($model->isa('RDF::Redland::Model::ExifTool'), 
   "model is right type (RDF::Redland::Model::ExifTool)");

my @error;
foreach my $f (@GOOD_FILE) {
    $exiftool->ImageInfo($f);
    @error = $model->add_exif_statements($exiftool);
    ok(!@error, "processed file with default config ($f)");
}

foreach my $f (@BAD_FILE) {
    $exiftool->ImageInfo($f);
    @error = $model->add_exif_statements($exiftool);
    ok(@error, "failed to process file with default config");
    foreach my $e (@error) {
        print "\t$e\n";
    }
}

foreach my $et ($model, undef) {
    @error = $model->add_exif_statements($et);
    ok(@error, "failed to process ExifTool with default config");
    foreach my $e (@error) {
        print "\t$e\n";
    }
}

my $default_config = $model->get_exif_config;
ok($default_config, "got default configuration from model");

my $default_config_string = $model->get_exif_config_to_string;
ok($default_config, "got default configuration from model to string");

my @default_tag = $model->get_exif_tags;
ok(@default_tag, "got default list of processable tags from model");

@error = $model->set_exif_config($default_config);
ok(!@error, "reset default config");
foreach my $e (@error) {
    print "\t$e\n";
}
my @tag = $model->get_exif_tags;
ok(scalar(@default_tag) == scalar(@tag),
   "number of processable tags unchanged after config replaced");

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
my $parse_no_tag =  {
    ParseSyntax => "turtle",
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

foreach my $c ($min_parse, $min_trans) {
    @error = $model->set_exif_config($c);
    ok(!@error, "set configuration");
}

foreach my $c ($parse_no_syntax, $parse_no_tag, $bad_trans, 
               $bad_variable, { }, undef) {
    @error = $model->set_exif_config($c);
    ok(@error, "failed to set bad configuration");
    foreach my $e (@error) {
        print "\t$e\n";
    }
}

foreach my $f ("t/config/min_parse", "t/config/min_trans",
               "t/config/wikipedia_basic+comment") {
    @error = $model->set_exif_config_from_file($f);
    ok(!@error, "set configuration ($f)");
}

$exiftool = new Image::ExifTool("lighthouse.jpg");
@error = $model->set_exif_config_from_file("t/config/bad_syntax");
ok(@error, "set configuration with bad syntax (t/config/bad_syntax)");
foreach my $e (@error) {
    print "\t$e\n";
}
@error = $model->add_exif_statements($exiftool);

# Ed: tricky to test unreadable config file
foreach my $f ("t/config/parse_no_syntax", "t/config/bad_trans", 
               "t/config/bad_variable", "", undef) {
    @error = $model->set_exif_config_from_file($f);
    ok(@error, "failed to set bad configuration");
    foreach my $e (@error) {
        print "\t$e\n";
    }
}

my @exiftool_list = ();
foreach my $f (@GOOD_FILE, @BAD_FILE) {
    my $e = new Image::ExifTool;
    $e->ImageInfo($f);
    @exiftool_list = (@exiftool_list, $e);
}
@error = $model->add_exif_statements(@exiftool_list);
ok(@error, "failed to process at least one file with other config");
foreach my $e (@error) {
    print "\t$e\n";
}
