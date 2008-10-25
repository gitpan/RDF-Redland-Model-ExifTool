use Image::ExifTool;
use RDF::Redland;
use RDF::Redland::Model::ExifTool;

# creates an RDF model in memory
$storage = new RDF::Redland::Storage("hashes", "",
                       "new='yes',hash-type='memory'");
$model = new RDF::Redland::Model::ExifTool($storage, "");
$EMPTY_MODEL_N_STATEMENTS = $model->size;

# processes Exif meta data from each file into RDF statements
# in model and prints any errors
$exiftool = new Image::ExifTool;
foreach $file (@ARGV) {
    $exiftool->ImageInfo($file, $model->get_exif_tags);

    foreach $error ($model->add_exif_statements($exiftool)) {
        print STDERR $error . "\n";
    }
}
$model->sync;

# prints any RDF statements in model with Turtle syntax
if ($EMPTY_MODEL_N_STATEMENTS < $model->size) {
    $serializer = new RDF::Redland::Serializer("turtle");
    print $serializer->serialize_model_to_string(
          new RDF::Redland::URINode("http://www.theflints.net.nz/"), 
          $model);
    undef $serializer;  # prevents librdf_serializer null exception
}

