#
# RDF::Redland::Model::ExifTool
#
# Copyright 2008 Andrew Flint, all rights reserved.
#
# This program is free software; you can redistribute it and/or 
# modify it under the same terms as Perl itself.
#
package RDF::Redland::Model::ExifTool;

use strict;
use warnings;

use Carp;
use File::Spec;
use Image::ExifTool;
use RDF::Redland;
use Regexp::Common qw /URI/;
use URI::file;

use base qw(RDF::Redland::Model);

#----default configuration:begin----#
# Exif tags to parse for RDF statements
my @_Parse_Tag = ("Comment", "ImageDescription");

# RDF syntax to parse Exif tag value
# parameter to RDF::Redland::Parser
my @_Parse_Syntax = ("turtle", "rdfxml");

# Exif tag to RDF predicate translation
my $EXIF = "http://www.w3.org/2003/12/exif/ns#";
my %_Translate_Tag = (
    Aperture => new RDF::Redland::URINode($EXIF . "apertureValue"),
    Comment => new RDF::Redland::URINode($EXIF . "userComment"),
    DateTimeOriginal => new RDF::Redland::URINode(
                            $EXIF . "dateTimeOriginal"),
    FocalLength35efl => new RDF::Redland::URINode(
                            $EXIF . "focalLengthIn35mmFilm"),
    ImageDescription => new RDF::Redland::URINode(
                            $EXIF . "imageDescription"),
    ISO => new RDF::Redland::URINode($EXIF . "ISOSpeedRatings"),
    Make => new RDF::Redland::URINode($EXIF . "make"),
    Model => new RDF::Redland::URINode($EXIF . "model"),
    ShutterSpeed => new RDF::Redland::URINode(
                        $EXIF . "shutterSpeedValue"),
);
#----default configuration:end----#

# remembers status of last RDF parse attempt
my $_Parse_Ok;


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
    my $predicate = $_Translate_Tag{"$tag"};
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
                if ($parser) {
                    $_Parse_Ok = 1;
                    RDF::Redland::set_log_handler(
                        \&_remember_parser_error);
                    my $stream = $parser->parse_string_as_stream(
                                     $value, $subject->uri);
                    RDF::Redland::reset_log_handler();
    
                    if ($stream && $_Parse_Ok) {
                        for ( ; !$stream->end; $stream->next) {
                            my $s = $stream->current;
                            $s->subject($subject);
                            @statement = (@statement, $s);
                        }

                        last PARSER;
                    }
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

        my $object = new RDF::Redland::LiteralNode("$value");
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

RDF::Redland::Model::ExifTool - extends Redland set of RDF statements 
                                (RDF::Redland::Model) to process
                                Exif meta data from 
                                ExifTool (Image::ExifTool)
                                into RDF statements

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

    use Image::ExifTool;
    use RDF::Redland::Storage;
    use RDF::Redland::Serializer;
    use RDF::Redland::URINode;
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

=head1 DESCRIPTION

Exif meta data is in tag and value pairs e.g. Aperture 5.0.
ExifTool reads, writes and updates Exif meta data stored in files.
See also ExifTool web site
L<http://www.sno.phy.queensu.ca/~phil/exiftool/>.

RDF meta data is in statements -
subject, predicate or verb and object triples.
Redland Libraries provide support for RDF.
See also Redland RDF Libraries web site L<http://librdf.org/>.

This class extends the Redland set of RDF statements 
C<RDF::Redland::Model> to process Exif meta data read from 
instances of ExifTool C<Image::ExifTool>.

=head2 Processing meta data

This class processes Exif meta data from a file read through an ExifTool
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

=back

=head2 Configuration

This class is configured by a hash of data structures as follows:

=over

=item ParseTag

list of ExifTool tags whose values are parsed for statements
e.g. Aperture, DateTimeOriginal and Comment.
Get ExifTool's list of tags with C<exiftool -list> .
Get a file's tags and values with
C<exiftool -s E<lt>fileE<gt>> .

=item ParseSyntax

list of Redland RDF syntax used in parsing tag values e.g. 
rdfxml, ntriples, turtle and guess.
See list of syntax in rdfproc man page, command parse.

=item TranslateTag

hash of ExifTool tag to the equivalent RDF predicate.
Predicates are absolute HTTP URIs.

=back

ParseTag or TranslateTag or both must be set.
If ParseTag is set then ParseSyntax must be too.

The default configuration gets meta data including:
user comment, image description, date/time of creation,
camera model and exposure.

Methods L</get_exif_config> and L</set_exif_config> 
return and update the configuration.
Here is an example configuration:

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

=head1 METHODS

=head2 add_exif_statements

Processes meta data from list of ExifTool instances
into RDF statements stored in this instance.
See also Exif meta data processing L</Configuration>.

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
                        $e = "param[$i] ExifTool " . 
                             $et->GetValue("Error") . " " .
                             $subject->as_string;
                    }
                } else {
                    $e = "param[$i] ExifTool failed to get subject";
                }
            } else {
                $e = "param[$i] must be ExifTool";
            } 
        } else {
            $e = "param[$i] must be defined";
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

Returns copy of this instance's L</Configuration>.

=cut

sub get_exif_config {
    my($self) = @_;
    my($config, %tt) = ();

#print STDERR "get_exif_config:begin\n";
    $config->{ParseTag} = [@_Parse_Tag];

    $config->{ParseSyntax} = [@_Parse_Syntax];

    foreach my $tag (keys(%_Translate_Tag)) {
        my $predicate = $_Translate_Tag{"$tag"};
        if (!$predicate) {
            croak "get_exif_config: no predicate for tag ($tag)";
        }

        my $predicate_uri = $predicate->uri;
        if (!$predicate_uri) {
            croak "get_exif_config: failed to get URI for predicate";
        }

        my $s = $predicate_uri->as_string;
        if (!$s) {
            croak "get_exif_config: failed to get predicate URI as string";
        }

        $tt{"$tag"} = $s;
    }
    $config->{TranslateTag} = \%tt;
#print STDERR "get_exif_config:end\n";

    return $config;
}


=head2 get_exif_tags

Returns list of Exif tags that can be processed by 
this instance's L</Configuration>.

By default ExifTool C<ImageInfo> gets all Exif tags. 
Use this method to get only those tags that can be processed 
by this instance:

    my $model = new RDF::Redland::Model::ExifTool(...);
    my $exiftool = new Image::ExifTool;
    
    $exiftool->ImageInfo("my.jpg", $model->get_exif_tags);

=cut

sub get_exif_tags {
    my @tag = ();

#print STDERR "get_exif_tags:begin\n";
    my @t = (sort(@_Parse_Tag, keys %_Translate_Tag), "");
    for (my $i = 0; $i < (scalar(@t) - 1); $i++) {
        if ($t[$i] ne $t[$i + 1]) {
            @tag = (@tag, $t[$i]);
        }
    }
#print STDERR "get_exif_tags:end:" . scalar(@tag) . "\n";

    return @tag;
}


=head2 set_exif_config

Updates this instance's L</Configuration>.

Returns empty list if successful 
otherwise returns list of error strings.

=cut

sub set_exif_config {
    my($self, $config) = @_;
    my @error = ();
    my(@pt, @ps, %tt) = ();

#print STDERR "set_exif_config:begin\n";
    if ($config) {
        @pt = _copy_to_list($config->{ParseTag});

        @ps = _copy_to_list($config->{ParseSyntax});

        if (ref($config->{TranslateTag}) eq "HASH") {
            foreach my $tag (keys(%{$config->{TranslateTag}})) {
                my $predicate_uri = $config->{TranslateTag}{"$tag"};
                if ($predicate_uri &&
                    ($predicate_uri =~ /$RE{URI}{HTTP}/)) {
                    my $predicate = new RDF::Redland::URINode($predicate_uri);
                    if ($predicate) {
                        $tt{"$tag"} = $predicate;
                    } else {
                        croak "set_exif_config: failed to " .
                              "create predicate ($predicate_uri)";
                    }
                } else {
                    @error = (@error, "TranslateTag must map tag $tag " .
                              "to absolute HTTP scheme predicate URI");
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
        @error = (@error, "config argument must be defined");
    }

    if (!@error) {
        @_Parse_Tag = @pt;
        @_Parse_Syntax = @ps;
        %_Translate_Tag = %tt;
    }
#print STDERR "set_exif_config:end:" . scalar(@error) . "\n";

    return @error;
}

=head1 AUTHOR

Andrew Flint, C<< <andrew at theflints.net.nz> >>

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

Copyright 2008 Andrew Flint, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of RDF::Redland::Model::ExifTool
