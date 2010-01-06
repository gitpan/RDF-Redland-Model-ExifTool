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

# Exif tag to number of times RDF has been parsed from its value,
# see L</_parse_tag>
my %_Parse_Tag = (
    Artist => 0,
    Comment => 0,
    ImageDescription => 0,);

# RDF syntax to number of successful parses, see L</_parse_tag>
my %_Parse_Syntax = (
    turtle => 0,
    rdfxml => 0,);

# Exif tag to RDF predicate, see L</_translate_tag>
my $EXIF = "http://www.w3.org/2003/12/exif/ns#";
my %_Translate_Tag = (
    Aperture => new RDF::Redland::URINode($EXIF . "apertureValue"),
    Artist => new RDF::Redland::URINode($EXIF . "artist"),
    Comment => new RDF::Redland::URINode($EXIF . "userComment"),
    DateTimeOriginal => new RDF::Redland::URINode($EXIF . 
                                "dateTimeOriginal"),
    FocalLength35efl => new RDF::Redland::URINode($EXIF . 
                                "focalLengthIn35mmFilm"),
    ImageDescription => new RDF::Redland::URINode($EXIF . 
                                "imageDescription"),
    ISO => new RDF::Redland::URINode($EXIF . "ISOSpeedRatings"),
    Make => new RDF::Redland::URINode($EXIF . "make"),
    Model => new RDF::Redland::URINode($EXIF . "model"),
    ShutterSpeed => new RDF::Redland::URINode($EXIF . 
                                "shutterSpeedValue"),
);
#----default configuration:end----#

# last RDF parse status, 
# see L</_parse_tag> and L</_remember_parser_error>
my $_Last_Parse_Status;

# processable tag list, see L</get_exif_tags>
my @_Tag = ();


#
# Creates file scheme URI node for file read by exiftool.
# Assumes exiftool is class Image::ExifTool.
# Returns URI as RDF::Redland::URINode or 
# undef if could not create node.
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
    } else {
        # ignores exiftool without Directory and/or FileName tags
    }
#print STDERR "_get_subject:end"; if ($subject) { print STDERR ":" . $subject->as_string }; print STDERR "\n";

    return $subject;
}

#
# Gets Exif tag and value pairs from exiftool ignoring
# duplicate tags and tags with undefined or empty values.
# Assumes exiftool is class Image::ExifTool.
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
            # removes trailing whitespace from value
            $value =~ s/[\s]*$//;
            $tag2value{$tag} = $value;
        } else {
            # ignores tag with undef or empty value
        }
    }
#print STDERR "_get_tags:end:" . scalar(keys %tag2value) . "\n";

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
    if (defined $_Parse_Tag{$tag}) {
        my $value = $tag2value->{$tag};

        PARSER: 
        foreach my $syntax (keys %_Parse_Syntax) {
            my $parser = new RDF::Redland::Parser($syntax);
            if (!$parser) {
                croak "_parse_tag: failed to create parser " .
                      "($syntax)";
            }

            $_Last_Parse_Status = 1;
            RDF::Redland::set_log_handler(
                \&_remember_parser_error);
            my $stream = $parser->parse_string_as_stream(
                             $value, $subject->uri);
            RDF::Redland::reset_log_handler();

            if ($stream && $_Last_Parse_Status) {
                $_Parse_Tag{$tag}++;
                $_Parse_Syntax{$syntax}++;
#print STDERR "_parse_tag:debug:$tag $_Parse_Tag{$tag} $syntax $_Parse_Syntax{$syntax}\n";
                while (!$stream->end) {
                    @statement = (@statement, $stream->current);
                    $stream->next;
                }
                last PARSER;
            }
        }
    } else {
        # ignores tag that is not on list to be parsed
    }
#print STDERR "_parse_tag:end:" . scalar(@statement) . "\n";

    return @statement;
}

#
# Remembers last attempt to parse RDF failed.
# RDF Redland Parser error handler used by _parse_tag().
#
sub _remember_parser_error { 
    $_Last_Parse_Status = 0;
    return 1; 
}

#
# Translates Exif tag and value into RDF statement about subject.
# Assumes tag is string, tag2value is hash and 
# subject is class RDF::Redland::URINode.
# Returns a one statement list or
# empty list if there was no RDF predicate translation for tag.
#
sub _translate_tag {
    my($tag, $tag2value, $subject) = @_;
    my @statement = ();

#print STDERR "_translate_tag:begin:$tag," . $subject->as_string . "\n";
    my $predicate = $_Translate_Tag{$tag};
    if ($predicate) {
        my $value = $tag2value->{$tag};

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
        # ignores tag without translation to predicate
    }
#print STDERR "_translate_tag:end:" . scalar(@statement) . "\n";

    return @statement;
}

=head1 NAME

RDF::Redland::Model::ExifTool - extends RDF model to process Exif meta data

Using ExifTool and Redland RDF Libraries.

=head1 VERSION

Version 0.13

=cut

our $VERSION = '0.13';

=head1 SYNOPSIS

    use Image::ExifTool;
    use RDF::Redland;
    use RDF::Redland::Model::ExifTool;

    # creates an empty RDF model in memory
    $storage = new RDF::Redland::Storage("hashes", "exif_meta_data",
                           "new='yes',hash-type='memory'");
    $model = new RDF::Redland::Model::ExifTool($storage, "");

    # processes Exif meta data from each file
    # into RDF statements in model,
    # using the default configuration, and prints any errors
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
        undef $serializer;
    }
    undef $model;
    undef $storage;

For a more complete example see script exif2rdf
and the TUTORIAL in its documentation.

=head1 DESCRIPTION

Exif meta data is in tag and value pairs.
The ExifTool Perl library reads Exif meta data stored in files.
RDF is in subject, predicate (verb) and object triples
called statements.
Redland Libraries have a Perl interface 
that parses and serializes RDF.
For more details on ExifTool and Redland see
L<Image::ExifTool> and L<http://librdf.org/docs/perl.html>.

This class extends the Redland model or set of RDF statements
(RDF::Redland::Model) to process Exif meta data from 
instances of ExifTool (Image::ExifTool).
The programmer can use all the features of ExifTool and
Redland including RDF databases, querying and reasoning.

This class depends on non-core Perl modules and classes.
CPAN has all of them except RDF::Redland, 
see this class' README for more details.

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
      ShutterSpeed => 
        "http://www.w3.org/2003/12/exif/ns#shutterSpeedValue",
    },
  };

that gets exposure data (Aperture and ShutterSpeed)
then tries to parse RDF statements from any Comment value as 
Turtle or RDF/XML or failing that translates to text.

To dump the default configuration
(with L</get_exif_config> and L</get_exif_config_to_string>)
run this class' example script:

    exif2rdf --dump

=over

=item B<ParseTag>

list of Exif tags whose values are parsed for RDF statements
for example Comment.

If ParseTag is set then ParseSyntax must be too.
TranslateTag must be set if ParseTag is not.

=item B<ParseSyntax>

list of Redland RDF syntax used in parsing tag values,
for example rdfxml, ntriples, turtle and guess.
For a list of possible values run the 
Redland parser utility C<rapper --help> and 
see the input FORMATs.

=item B<TranslateTag>

hash of Exif tag and equivalent RDF predicate.

For the list of tag value pairs in an image run:

    exiftool -s my.jpg

For the list of tags that ExifTool can process run: 

    exiftool -list

Predicates must be absolute HTTP URIs. 
See these schemas with predicates for:

=over

=item *

Exif meta data L<http://www.w3.org/2003/12/exif/> 

=item *

image file meta data
L<http://dublincore.org/documents/dcmi-terms/> 

=item *

human meta data
Friend of a Friend (FOAF) L<http://xmlns.com/foaf/0.1/>

=back

ParseTag and ParseSyntax must be set if TranslateTag is not.

=back

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
                    $e = "exiftool[$i] ExifTool failed " .
                         "to get subject";
                }
            } else {
                $e = "exiftool[$i] must be Image::ExifTool";
            } 
        } else {
            $e = "exiftool[$i] must be defined";
        }

        if (!$e) {
            my %tag2value = _get_tags($et);
            foreach my $tag (keys %tag2value) {
                my @statement = _parse_tag($tag, \%tag2value, 
                                           $subject);
                if (!@statement) {
                    @statement = _translate_tag($tag, \%tag2value, 
                                                $subject);
                }
    
                foreach my $s (@statement) {
                    if ($self->add_statement($s)) { 
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
    my($config) = ();

#print STDERR "get_exif_config:begin\n";
    $config->{ParseTag} = [keys %_Parse_Tag];
    $config->{ParseSyntax} = [keys %_Parse_Syntax];

    foreach my $tag (keys %_Translate_Tag) {
        my $predicate = $_Translate_Tag{$tag};
        my $predicate_uri = ($predicate->uri)->as_string;
        $config->{TranslateTag}{$tag} = $predicate_uri;
    }
#print STDERR "get_exif_config:end\n";

    return $config;
}


=head2 get_exif_config_to_string

Returns copy of this RDF model's L</Configuration> as string.

=cut

sub get_exif_config_to_string {
    my($self) = @_;
    my $string = "";

#print STDERR "get_exif_config_to_string:begin\n";
    my $config = $self->get_exif_config;

    my $element = "TranslateTag";
    $string = $string . "<$element>\n";
    foreach my $tag (keys %{$config->{$element}}) {
        my $predicate_uri = ${$config->{$element}}{$tag};
        $string = $string . "  $tag $predicate_uri\n";
    }
    $string = $string . "</$element>\n";

    foreach $element ("ParseTag", "ParseSyntax") {
        $string = $string . "$element";
        foreach my $word (@{$config->{$element}}) {
            $string = $string . " $word";
        }
        $string = $string . "\n";
    }
#print STDERR "get_exif_config_to_string:end:$string\n";

    return $string;
}


=head2 get_exif_tags

Returns list of Exif tags that can be processed by this 
RDF model, the tags in L</Configuration>.

By default ExifTool's ImageInfo gets all tags from a file.
Getting only the subset of tags this model can process
speeds ExifTool up. For example:

    $exiftool->ImageInfo("my.jpg", $model->get_exif_tags)

asks ExifTool to get from my.jpg only those tag and value pairs 
this model can process.

=cut

sub get_exif_tags {
#print STDERR "get_exif_tags:begin\n";
    if (!@_Tag) {
        @_Tag = ();

        my @t = (sort(keys %_Parse_Tag, keys %_Translate_Tag), "");
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
    my %ELEMENT = ("ParseTag ARRAY" => 1, 
                   "ParseTag " => 1,
                   "ParseSyntax ARRAY" => 1, 
                   "ParseSyntax " => 1,
                   "TranslateTag HASH" => 1,);
    my($self, $config) = @_;
    my @error = ();
    my(%pt, %ps, %tt) = ();

#print STDERR "set_exif_config:begin\n";
    if ($config) {
        foreach my $element (keys %{$config}) {
            my $type = ref $config->{$element};
            if ($ELEMENT{"$element $type"}) {
                my(%h, @l);
                if ($type eq "ARRAY") {
                    @l = @{$config->{$element}};
                } elsif ($type eq "HASH") {
                    %h = %{$config->{$element}};
                } else {  # SCALAR
                    @l = ($config->{$element});
                }

                if ($element eq "ParseTag") {
                    foreach my $tag (@l) {
                        if ($tag) {
                            $pt{$tag} = 0;
                        } else {
                            @error = (@error, "bad ParseTag ($tag)");
                        }
                    }
                } elsif ($element eq "ParseSyntax") {
                    foreach my $syntax (@l) {
                        if ($syntax) {
                            my $parser = new 
                                   RDF::Redland::Parser($syntax);
                            if ($parser) {
                                $ps{$syntax} = 0;
                            } else {
                                @error = (@error, 
                                    "unknown ParseSyntax ($syntax)");
                            }
                        } else {
                            @error = (@error, 
                                      "bad ParseSyntax ($syntax)");
                        }
                    }
                } else {  # TranslateTag
                    foreach my $tag (keys %h) {
                        if ($tag) {
                            my $predicate_uri = $h{$tag};
                            if (($predicate_uri) && 
                                ($predicate_uri =~ /$RE{URI}{HTTP}/)) 
                            {
                                my $predicate = new 
                                       RDF::Redland::URINode(
                                           $predicate_uri);
                                if ($predicate) {
                                    $tt{$tag} = $predicate;
                                } else {
                                    @error = (@error, 
"failed to create predicate for TranslateTag ($tag, $predicate_uri)");
                                }
                            } else {
                                @error = (@error,
"TranslateTag must map tag to absolute HTTP URI predicate ($tag)");
                            }
                        } else {
                            @error = (@error, 
                                      "bad TranslateTag ($tag)");
                        }
                    }
                }
            } else {
                @error = (@error, "unknown config element or type " .
                          "($element, $type)");
            }
        }

        if ((!%pt) && (!%tt)) {
            @error = (@error, "either ParseTag or TranslateTag " .
                      "or both must be defined");
        }

        if (%pt && (!%ps)) {
            @error = (@error, "ParseTag is defined, " .
                              "ParseSyntax must be defined too");
        } 
    } else {
        @error = (@error, "config must be defined");
    }

    if (!@error) {
        %_Parse_Tag = %pt;
        %_Parse_Syntax = %ps;
        %_Translate_Tag = %tt;

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
    #       it is treated as a comment
    <TranslateTag>
      Aperture      http://www.w3.org/2003/12/exif/ns\#apertureValue
      Comment       http://www.w3.org/2003/12/exif/ns\#userComment
      ShutterSpeed  http://www.w3.org/2003/12/exif/ns\#shutterSpeedValue
    </TranslateTag>

    ParseTag Comment

    ParseSyntax turtle
    ParseSyntax rdfxml

This configuration is the same as the example L</Configuration>.

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
            @error = ("config file must exist and " .
                      "be readable ($file)");
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
