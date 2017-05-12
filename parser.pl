#!/usr/bin/env perl
use 5.020;
use common::sense;
use utf8::all;

# Use fast binary libraries
use EV;
use Web::Scraper::LibXML;
use YADA;
use Data::Printer;
use File::Monitor;
use File::Basename qw/basename/;
use File::Path 'make_path';

my $filename = $ARGV[0];

my $city;
open(my $fh, '<:encoding(UTF-8)', $filename)
    or die "Could not open file '$filename' $!";
my @files = <$fh>;
chomp @files;

my $yada = YADA->new(
    common_opts => {

        # Available opts @ http://curl.haxx.se/libcurl/c/curl_easy_setopt.html
        encoding       => '',
        followlocation => 1,
        maxredirs      => 5,
    },
    http_response => 1,
    max           => 5,
);

my $monitor = File::Monitor->new();
$monitor->watch({
        name     => './links/' . $_,
        callback => {
            created => sub {
                my ($name, $event, $change) = @_;

                open(my $fh, "<:encoding(UTF-8)", $name)
                    or die "Could not open $name: $!";
                my @links = <$fh>;
                close($fh);

                my $city = basename($name);
                make_path("./raw/$city") unless (-d "./raw/$city");

                $yada->append(
                    [@links] => sub {
                        my ($self) = @_;
                        return
                               if $self->has_error
                            or not $self->response->is_success
                            or not $self->response->content_is_html;

                        # Declare the scraper once and then reuse it
                        # state $scraper = scraper {
                        #     process 'html title', title     => 'text';
                        #     process 'a',          'links[]' => '@href';
                        # };

                        # Employ amazing Perl (en|de)coding powers to handle HTML charsets
                        # my $doc = $scraper->scrape($self->response->decoded_content,
                        #     $self->final_url,);

                        my ($license_id) = $self->final_url =~ /licenceid=([^&]+)&/;
                        p $license_id;
                        my $outfile = "./raw/$city/$license_id.html";
                        open(my $fh, ">", $outfile)
                            or die "Could not open $outfile: $!";
                        print $fh $self->response->decoded_content;
                        close($fh);

                        # printf qq(%-64s %s\n), $self->final_url, $doc->{title};
                    })->wait;
            },
        },
    }) for @files;
$monitor->scan;
p $monitor;

while (1) {
    sleep 1;
    $monitor->scan;
}
