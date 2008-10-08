use Image::ExifTool;
use RDF::Redland;
use RDF::Redland::Model::ExifTool;

# creates an RDF model in memory
my $storage = new RDF::Redland::Storage("hashes", "",
                         "new='yes',hash-type='memory'");
my $model = new RDF::Redland::Model::ExifTool($storage, "");
my $EMPTY_MODEL_N_STATEMENTS = $model->size;

# processes Exif meta data from each file into RDF statements
# in model and prints any errors
my $exiftool = new Image::ExifTool;
foreach my $file (@ARGV) {
    $exiftool->ImageInfo($file);

    foreach my $error ($model->add_exif_statements($exiftool)) {
        print STDERR $error . "\n";
    }
}

# prints any RDF statements in model with Turtle syntax
if ($EMPTY_MODEL_N_STATEMENTS < $model->size) {
    my $serializer = new RDF::Redland::Serializer("turtle");
    print $serializer->serialize_model_to_string(
          new RDF::Redland::URINode("http://www.theflints.net.nz/"), 
          $model);
}