#
# bfhm.pl
#

use Image::ExifTool;
use RDF::Redland;
use RDF::Redland::Model::ExifTool;

my $storage = new RDF::Redland::Storage("hashes", "",
                         "new='yes',hash-type='memory'");
my $model = new RDF::Redland::Model::ExifTool($storage, "");

my $config = $model->get_exif_config;
my $EXIF = 'http://www.w3.org/2003/12/exif/ns#';
$config->{TranslateTag} = {
    Make => $EXIF . 'make',
    Model => $EXIF . 'model',
    ShutterSpeed => $EXIF . 'shutterSpeedValue',
    Aperture => $EXIF . 'apertureValue',
    DateTimeOriginal => $EXIF . 'dateTimeOriginal',
    FocalLength35efl => $EXIF . 'focalLengthIn35mmFilm',
};
$config->{ParseTag} = [ 'Comment' ];
$model->set_exif_config($config);
my @tag = $model->get_exif_tags;

my @exiftool = ();
while (<>) {
    chomp;
    my $file = $_;

    my $et = new Image::ExifTool;
    $et->ImageInfo($file, @tag);

    @exiftool = (@exiftool, $et);
}

foreach my $error ($model->add_exif_statements(@exiftool)) {
    print STDERR $error . "\n";
}

my $BASE = new RDF::Redland::URINode("http://www.theflints.net.nz/");
my $serializer = new RDF::Redland::Serializer("ntriples");
print $serializer->serialize_model_to_string($BASE, $model);
