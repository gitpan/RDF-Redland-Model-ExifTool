#
# synopsis.pl - prints Exif meta data from file arguments as
#               RDF statements in Turtle syntax
#
# This is the example script from the Synopsis of
# Perl module RDF::Redland::Model::ExifTool.
#

use Image::ExifTool;
use RDF::Redland;
use RDF::Redland::Model::ExifTool;

my $storage = new RDF::Redland::Storage("hashes", "",
                         "new='yes',hash-type='memory'");
my $model = new RDF::Redland::Model::ExifTool($storage, "");

my $exiftool = new Image::ExifTool;

foreach my $file (@ARGV) {
    $exiftool->ImageInfo($file);

    foreach my $error ($model->add_exif_statements($exiftool)) {
        print STDERR $error . "\n";
    }
}

my $BASE = new RDF::Redland::URINode("http://www.theflints.net.nz/");
my $serializer = new RDF::Redland::Serializer("turtle");
print $serializer->serialize_model_to_string($BASE, $model);
