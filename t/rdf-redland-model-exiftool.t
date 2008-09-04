use strict;
use warnings;

use Test;

use RDF::Redland;
use Image::ExifTool;
use RDF::Redland::Model::ExifTool;

BEGIN { plan tests => 16, todo => [8, 9, 13, 14, 15, 16] }; 

my $storage = new RDF::Redland::Storage("hashes", "test",
                  "new='yes',hash-type='memory'");
my $model = new RDF::Redland::Model::ExifTool($storage, "");
my $exiftool = new Image::ExifTool;
my(@error, $c);


$exiftool->ImageInfo("t/data/tag_subset.jpg",
                     "Aperture", "Comment", "ISO", "ShutterSpeed");
@error = $model->add_exif_statements($exiftool);
ok(!@error);

foreach my $photo ("t/data/no_comment.jpg", 
                   "t/data/text_comment.jpg",
                   "t/data/ntriples_comment.jpg",
                   "t/data/turtle_comment.jpg",
                   "t/data/rdfxml_comment.jpg",
                   "t/data/artist_uri.jpg",
                   "t/data/not_a_jpg.txt",
                   "t/data/does_not_exist.jpg",) {
    $exiftool->ImageInfo($photo);
    @error = $model->add_exif_statements($exiftool);
    ok(!@error);
}

my $default = $model->get_exif_config();

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
my $empty = { };
my $bad_trans = {
    TranslateTag => {
        BadScheme => "ftp://www.theflints.net.nz/lump.tar",
        Undef => undef,
        Empty => "",
        Relative => "../fred/",
    },
};

foreach my $config ($min_parse, $min_trans, $default,
                    undef, $empty, $parse_no_syntax, $bad_trans) {
    @error = $model->set_exif_config($config);
    ok(!@error);

    $c = $model->get_exif_config();
}
