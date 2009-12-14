#
# RDF::Redland::Model::ExifTool
#
# Copyright 2008-2010 Andrew Flint, all rights reserved.
#
# This program is free software; you can redistribute it and/or 
# modify it under the same terms as Perl itself.
#
package RDF::Redland::Model::ExifTool;

use strict;
use warnings;

use Carp;
use Config::General;
use File::Spec;
use HTML::Entities;
use Image::ExifTool;
use RDF::Redland;
use Regexp::Common qw /URI/;
use URI::file;

use base qw(RDF::Redland::Model);

#----default configuration:begin: see L</Configuration>----#
my @_Parse_Tag = ("Comment", "ImageDescription");

my @_Parse_Syntax = ("turtle", "rdfxml");

my $EXIF = "http://www.w3.org/2003/12/exif/ns#";
my %_Translate_Tag = (
    Aperture => $EXIF . "apertureValue",
    Artist => $EXIF . "artist",
    Comment => $EXIF . "userComment",
    DateTimeOriginal => $EXIF . "dateTimeOriginal",
    FocalLength35efl => $EXIF . "focalLengthIn35mmFilm",
    ImageDescription => $EXIF . "imageDescription",
    ISO => $EXIF . "ISOSpeedRatings",
    Make => $EXIF . "make",
    Model => $EXIF . "model",
    ShutterSpeed => $EXIF . "shutterSpeedValue",
);
#----default configuration:end----#

# last RDF parse status
my $_Parse_Ok;

# processable tag list
my @_Tag = ();

# ExifTool tag to RDF predicate hash
my %_Predicate = ();


#
# Copies elements from input list reference or scalar 
# to output list.
# Returns output list or 
# empty list if input was not appropriate type.
#
sub _copy_to_list {
    my($input) = @_;
    my $o = [];
    my @output = ();

#print STDERR "_copy_to_list:begin\n";
    if ($input) {
        my $type = ref($input);
        if ($type eq "ARRAY") {
            $o = [@{$input}];
        } elsif ($type eq "") {  # input is scalar
            $o = [$input];
        } else {
            # input neither list nor scalar - ignore input
        }

        foreach my $e (@{$o}) {
            if ($e) {
                @output = (@output, $e);
            }
        }
    }
#print STDERR "_copy_to_list:end:" . scalar(@output) . "\n";

    return @output;
}

#
# Translates Exif tag into RDF predicate.
# Assumes tag is string.
# Returns predicate or undef if there is no translation for tag.
#
sub _get_predicate {
    my($tag) = @_;

#print STDERR "_get_predicate:begin:$tag\n";
    my $predicate = $_Predicate{"$tag"};
    if (!$predicate) {
        my $predicate_uri = $_Translate_Tag{"$tag"};
        if ($predicate_uri) {
            $predicate = new RDF::Redland::URINode("$predicate_uri");
            if (!$predicate) {
                 croak "_get_predicate: failed to " .
                       "create predicate ($predicate_uri)";
            }
        }
    }
#print STDERR "_get_predicate:end"; if ($predicate) { print STDERR ":" . $predicate->as_string }; print STDERR "\n";

    return $predicate;
}

#
# Creates file scheme URI for file that exiftool read from. 
# Assumes exiftool is class Image::Exiftool.
# Returns URI as RDF::Redland::URINode or 
# undef if failed to create node.
#
sub _get_subject {
    my($exiftool) = @_;
    my $subject = undef;

#print STDERR "_get_subject:begin\n";
    my $directory = $exiftool->GetValue("Directory");
    my $filename = $exiftool->GetValue("FileName");
    if ($directory && $filename) {
        my $path = File::Spec->catfile($directory, $filename);
        if (!$path) {
            croak "_get_subject: failed to create " .
                  "absolute file path ($directory, $filename)";
        }

        my $uri = URI::file->new_abs($path);
        if (!$uri) {
            croak "_get_subject: failed to create " .
                  "file scheme URI ($path)";
        }

        $subject = new RDF::Redland::URINode($uri);
        if (!$subject) {
            croak "_get_subject: failed to create subject ($path)";
        }
    }
#print STDERR "_get_subject:end"; if ($subject) { print STDERR ":" . $subject->as_string }; print STDERR "\n";

    return $subject;
}

#
# Gets Exif tag and value pairs from exiftool ignoring
# duplicate tags and tags without values.
# Assumes exiftool is class Image::Exiftool.
# Returns tag to value hash.
#
sub _get_tags {
    my($exiftool) = @_;
    my %tag2value = ();

#print STDERR "_get_tags:begin\n";
    $exiftool->Options(
        Duplicates => 0,          # ignores duplicate tags
        DateFormat => "%FT%T%z",  # sets ISO8601 date time format
    );

    foreach my $tag ($exiftool->GetTagList) {
        my $value = $exiftool->GetValue($tag);
        if ($value) {
            $value =~ s/[\s]*$//;
            $tag2value{"$tag"} = $value;
        } else {
            # tag value undef or "" - ignore tag
        }
    }
#print STDERR "_get_tags:end:" . scalar(keys(%tag2value)) . "\n";

    return %tag2value;
}

#
# Parses RDF statements about subject from 
# value of Exif tag using each RDF syntax in turn.
# Assumes tag is string, tag2value is hash and 
# subject is class RDF::Redland::URINode.
# Returns statements from first successful parse or empty list.
#
sub _parse_tag {
    my($tag, $tag2value, $subject) = @_;
    my @statement = ();

#print STDERR "_parse_tag:begin:$tag," . $subject->as_string . "\n";
    foreach my $t (@_Parse_Tag) {
        if ($tag eq $t) {
            my $value = $$tag2value{"$tag"};
    
            PARSER: foreach my $syntax (@_Parse_Syntax) {
                my $parser = new RDF::Redland::Parser($syntax);
                if (!$parser) {
                    next PARSER;  # ignore failure to create parser
                }

                $_Parse_Ok = 1;
                RDF::Redland::set_log_handler(
                    \&_remember_parser_error);
                my $stream = $parser->parse_string_as_stream(
                                 $value, $subject->uri);
                RDF::Redland::reset_log_handler();

                if ($stream && $_Parse_Ok) {
                    while (!$stream->end) {
                        @statement = (@statement, $stream->current);
                        $stream->next;
                    }
                    last PARSER;
                }
            }
        } else {
            # tag not parseable - ignore
        }
    }
#print STDERR "_parse_tag:end:" . scalar(@statement) . "\n";

    return @statement;
}

#
# Remembers last RDF parse attempt failed.
# RDF Redland Parser error handler used by _parse_tag().
#
sub _remember_parser_error { 
    $_Parse_Ok = 0;
    return 1; 
}

#
# Translates Exif tag and value into RDF statement about subject.
# Assumes tag is string, tag2value is hash and 
# subject is class RDF::Redland::URINode.
# Returns statement in list or 
# empty list if there was no RDF predicate translation for tag.
#
sub _translate_tag {
    my($tag, $tag2value, $subject) = @_;
    my @statement = ();

#print STDERR "_translate_tag:begin:$tag," . $subject->as_string . "\n";
    my $predicate = _get_predicate($tag);
    if ($predicate) {
        my $value = $$tag2value{"$tag"};

        # rewrite values
        if ($tag eq "FocalLength35efl") {
            $value =~ s/^.* ([0-9\.]+).*$/$1/;
        }

        my $object;
        if ($value =~ /$RE{URI}{HTTP}/) {
            $object = new RDF::Redland::URINode("$value");
        } else {
            $object = new RDF::Redland::LiteralNode(
                              encode_entities("$value"));
        }
        if (!$object) {
            croak "_translate_tag: failed to create object" .
                  "($tag, $value)";
        }

        my $s = new RDF::Redland::Statement($subject,
                                            $predicate, $object);
        if (!$s) {
            croak "_translate_tag: failed to create statement" .
                  "($tag, $value)";
        }

        @statement = ($s);
    } else {
        # no predicate for tag - cannot translate
    }
#print STDERR "_translate_tag:end:" . scalar(@statement) . "\n";

    return @statement;
}

=head1 NAME

RDF::Redland::Model::ExifTool - extends RDF model to process Exif meta data

Using ExifTool and Redland RDF Libraries.

=head1 VERSION

Version 0.11

=cut

our $VERSION = '0.11';

=head1 SYNOPSIS

    use Image::ExifTool;
    use RDF::Redland;
    use RDF::Redland::Model::ExifTool;

    # creates an empty RDF model in memory
    $storage = new RDF::Redland::Storage("hashes", "exif_meta_data",
                           "new='yes',hash-type='memory'");
    $model = new RDF::Redland::Model::ExifTool($storage, "");

    # processes Exif meta data from each file
    # into RDF statements in model and prints any errors
    $exiftool = new Image::ExifTool;
    foreach $file (@ARGV) {
        $exiftool->ImageInfo($file, $model->get_exif_tags);
        foreach $error ($model->add_exif_statements($exiftool)) {
            print STDERR $error . "\n";
        }
    }
    $model->sync;

    # prints any RDF statements in model with Turtle syntax
    if (0 < $model->size) {
        $SYNTAX = "turtle";
        $serializer = new RDF::Redland::Serializer($SYNTAX);
        $BASE_URI = "http://www.theflints.net.nz/";
        print $serializer->serialize_model_to_string(
                  new RDF::Redland::URINode($BASE_URI), $model);
        undef $serializer;  # prevents librdf_serializer null exception
    }

For a more complete example see script F<exif2rdf> .

=head1 DESCRIPTION

Exif meta data is in tag and value pairs.
ExifTool has a Perl library that
reads Exif meta data stored in files.
RDF meta data is in statements -
subject, predicate (or verb) and object triples.
Redland Libraries have a Perl binding 
to parse and serialize RDF.
For more details see
L<http://www.sno.phy.queensu.ca/~phil/exiftool/> and
L<http://librdf.org/>.

This class extends the Redland set of RDF statements 
C<RDF::Redland::Model> to process Exif meta data read from 
instances of ExifTool C<Image::ExifTool>.

ExifTool is available as both packages and from CPAN.
However, Redland RDF Libraries are only available as
packages or source, the CPAN version
is out of date and fails C<make test>. 

=head2 Processing meta data

This RDF model processes Exif meta data from a file read through an ExifTool
as follows:

=over

=item *

create subject URI from file's absolute path C<file:///...>

=item *

for each Exif tag and value in the ExifTool:

=over

=item *

try parsing RDF statements from tag value,
setting subject on each one, otherwise...

=item *

try creating a statement from tag and value,
translating tag into predicate URI and copying value to object,
otherwise...

=item *

ignore tag and value

=back

=item *

add any RDF statements to this model

=back

=head2 Configuration

This class' configuration is a hash of data structures
that can be set from a file (with L</set_exif_config_from_file>) 
or variable (L</set_exif_config>).
For example a configuration in a variable:

    $config = {
        ParseTag => ["Comment"],
        ParseSyntax => ["turtle", "rdfxml"],
        TranslateTag => {
            Aperture => 
                "http://www.w3.org/2003/12/exif/ns#apertureValue",
            Comment => "http://www.w3.org/2003/12/exif/ns#userComment",
            ISO => "http://www.w3.org/2003/12/exif/ns#ISOSpeedRatings",
            ShutterSpeed => 
                "http://www.w3.org/2003/12/exif/ns#shutterSpeedValue",
        },
    };

that gets exposure data (Aperture, ISO and ShutterSpeed)
then tries to parse RDF statements from any Comment value as 
Turtle or RDF/XML or failing that text.

=over

=item ParseTag

list of ExifTool tags whose values are parsed for RDF statements
for example Comment.

If ParseTag is set then ParseSyntax must be too.
TranslateTag must be set if ParseTag is not.

=item ParseSyntax

list of Redland RDF syntax used in parsing tag values,
for example rdfxml, ntriples, turtle and guess.
For a list of possible values run the 
Redland parser utility C<rapper --help> and 
see the input FORMATs.

=item TranslateTag

hash of ExifTool tag and equivalent RDF predicate.

For the list of tag value pairs in C<myfile.jpg>
run C<exiftool -s my.jpg> .
For the list of tags that Exiftool can process
run C<exiftool -list> .

Predicates must be absolute HTTP URIs.
ParseTag and ParseSyntax must be set if TranslateTag is not.

=back

The default configuration gets meta data including:
user comment, image description, date/time of creation,
camera model and exposure.

=head1 METHODS

=head2 add_exif_statements

Processes Exif meta data from list of ExifTools
into RDF statements stored in this model using L</Configuration>.

Returns empty list if successful
otherwise returns list of error strings.

=cut

sub add_exif_statements {
    my($self, @exiftool) = @_;
    my(@error, @subject) = ();
    my($i) = 0;
    my($e, $subject);

#print STDERR "add_exif_statements:begin\n";
    foreach my $et (@exiftool) {
        if ($et) {
            if ((ref $et) && $et->isa("Image::ExifTool")) {
                $subject = _get_subject($et);
                if ($subject) {
                    if ($et->GetValue("Error")) {
                        $e = "exiftool[$i] ExifTool " . 
                             $et->GetValue("Error") . " " .
                             $subject->as_string;
                    }
                } else {
                    $e = "exiftool[$i] ExifTool failed to get subject";
                }
            } else {
                $e = "exiftool[$i] must be ExifTool";
            } 
        } else {
            $e = "exiftool[$i] must be defined";
        }

        if (!$e) {
            my %tag2value = _get_tags($et);
            foreach my $tag (keys(%tag2value)) {
                my @statement = _parse_tag($tag, \%tag2value, $subject);
                if (!@statement) {
                    @statement = _translate_tag($tag, \%tag2value, 
                                                $subject);
                }
    
                foreach my $st (@statement) {
                    if ($self->add_statement($st)) { 
                        croak "add_exif_statements:" .
                              "failed to add statement to model";
                    }
                }
            }
        } else {
            @error = (@error, $e);
            $e = undef;
        }

        $i++;
    }
#print STDERR "add_exif_statements:end:" . scalar(@error) . "\n";

    return @error;
}


=head2 get_exif_config

Returns copy of this RDF model's L</Configuration>.

=cut

sub get_exif_config {
    my($self) = @_;
    my($config, %tt) = ();

#print STDERR "get_exif_config:begin\n";
    $config->{ParseTag} = [@_Parse_Tag];

    $config->{ParseSyntax} = [@_Parse_Syntax];

    foreach my $tag (keys(%_Translate_Tag)) {
        my $predicate_uri = $_Translate_Tag{"$tag"};
        if (!$predicate_uri) {
            croak "get_exif_config: no predicate for tag ($tag)";
        }

        $tt{"$tag"} = $predicate_uri;
    }
    $config->{TranslateTag} = \%tt;
#print STDERR "get_exif_config:end\n";

    return $config;
}


=head2 get_exif_tags

Returns list of ExifTool tags that can be processed by this 
RDF model, the tags in L</Configuration>.

By default ExifTool's C<ImageInfo> gets all tags from a file.
Getting the subset of tags that this model can process
reduces the work ExifTool has to do. For example:

    $exiftool->ImageInfo("my.jpg", $model->get_exif_tags)

asks ExifTool to get from F<my.jpg> only those tag and value pairs 
that C<model> can process.

=cut

sub get_exif_tags {
#print STDERR "get_exif_tags:begin\n";
    if (!@_Tag) {
        @_Tag = ();

        my @t = (sort(@_Parse_Tag, keys %_Translate_Tag), "");
        for (my $i = 0; $i < (scalar(@t) - 1); $i++) {
            if ($t[$i] ne $t[$i + 1]) {
                @_Tag = (@_Tag, $t[$i]);
            }
        }
    }

    my @tag = @_Tag;
#print STDERR "get_exif_tags:end:" . scalar(@tag) . "\n";

    return @tag;
}


=head2 set_exif_config

Replaces this RDF model's L</Configuration>.

Returns empty list if configuration replaced
otherwise returns list of error strings.

=cut

sub set_exif_config {
    my($self, $config) = @_;
    my %VARIABLE = ( 
        ParseTag => 1,
        ParseSyntax => 1,
        TranslateTag => 1 );
    my @error = ();
    my(@pt, @ps, %tt) = ();

#print STDERR "set_exif_config:begin\n";
    if ($config) {
        foreach my $v (keys %{$config}) {
            if (!$VARIABLE{$v}) {
                @error = (@error, "unknown config variable ($v)");
            }
        }

        @pt = _copy_to_list($config->{ParseTag});

        @ps = _copy_to_list($config->{ParseSyntax});

        if (ref($config->{TranslateTag}) eq "HASH") {
            foreach my $tag (keys(%{$config->{TranslateTag}})) {
                my $predicate_uri = $config->{TranslateTag}{"$tag"};
                if ($predicate_uri &&
                    ($predicate_uri =~ /$RE{URI}{HTTP}/)) {
                    $tt{"$tag"} = $predicate_uri;
                } else {
                    @error = (@error, "TranslateTag must map tag " .
                              "to absolute HTTP URI predicate ($tag)");
                }
            }
        }

        if ((!@pt) && (!%tt)) {
            @error = (@error, "either ParseTag or TranslateTag " .
                      "or both must be defined");
        }

        if (@pt && (!@ps)) {
            @error = (@error, "ParseTag is defined, " .
                              "ParseSyntax must be defined too");
        } 
    } else {
        @error = (@error, "config must be defined");
    }

    if (!@error) {
        @_Parse_Tag = @pt;
        @_Parse_Syntax = @ps;
        %_Translate_Tag = %tt;

        # discard last configuration's list of processable tags,
        # get_exif_tags() will update on demand
        @_Tag = ();
    }
#print STDERR "set_exif_config:end:" . scalar(@error) . "\n";

    return @error;
}

=head2 set_exif_config_from_file

Replaces this RDF model's L</Configuration> from configuration file. 

Returns empty list if configuration replaced
otherwise returns list of error strings.

For example a configuration in a file:

    # Note: URI anchor char '#' must be escaped '\#' or 
    #       it is treated as comment
    <TranslateTag>
      Aperture      http://www.w3.org/2003/12/exif/ns\#apertureValue
      Comment       http://www.w3.org/2003/12/exif/ns\#userComment
      ISO           http://www.w3.org/2003/12/exif/ns\#ISOSpeedRatings
      ShutterSpeed  http://www.w3.org/2003/12/exif/ns\#shutterSpeedValue
    </TranslateTag>
    
    ParseTag Comment
    
    ParseSyntax turtle
    ParseSyntax rdfxml

This configuration is the same as the example L<Configuration>.

=cut

sub set_exif_config_from_file {
    my($self, $file) = @_;
    my @error = ();

#print STDERR "set_exif_config_from_file:begin\n";
    if ($file) {
        if (-r $file) {
            my $config = new Config::General($file);
            if ($config) {
                my %c = $config->getall;
                @error = set_exif_config($self, \%c);
            } else {
                @error = ("failed to get config from file ($file)");
            }
        } else {
            @error = ("config file must exist and be readable ($file)");
        }
    } else {
        @error = ("config file must be defined");
    }
#print STDERR "set_exif_config_from_file:end:" . scalar(@error) . "\n";

    return @error;
}

=head1 AUTHOR

Andrew Flint, C<< <arnhemcr at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-rdf-redland-model-exiftool at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=RDF-Redland-Model-ExifTool>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this class with the perldoc command.

    perldoc RDF::Redland::Model::ExifTool

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=RDF-Redland-Model-ExifTool>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/RDF-Redland-Model-ExifTool>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/RDF-Redland-Model-ExifTool>

=item * Search CPAN

L<http://search.cpan.org/dist/RDF-Redland-Model-ExifTool>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008-2010 Andrew Flint, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of RDF::Redland::Model::ExifTool
