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
use Date::Parse;
use Store::CouchDB;

my $filename = $ARGV[0];
my $monitor  = File::Monitor->new();
my $yada     = YADA->new(
    common_opts => {

        # Available opts @ http://curl.haxx.se/libcurl/c/curl_easy_setopt.html
        encoding       => '',
        followlocation => 1,
        maxredirs      => 5,
    },
    http_response => 1,
    max           => 5,
);
my $sc = Store::CouchDB->new(
    db    => 'realestate_agents',
    debug => 1,
);

sub filter_date {
    return str2time(join('-', reverse split(m[/], shift)));
}

sub filter_date_period {
    my ($start, $end) = split(/ - /, shift);
    return { start => filter_date($start), end => filter_date($end) };
}

sub filter_address {
    my @lines = split(m[\s*<br/>\s*], shift);
    my ($city, $pcode) = $lines[-1] =~ m/^(.*)\s+(\d+)$/;

    # trim
    $city =~ s/^\s+|\s+$//g;
    $pcode =~ s/^\s+|\s+$//g;
    $lines[0] =~ s/^\s+|\s+$//g;

    my $address = {
        street => $lines[0],
        city   => $city,
        pcode  => $pcode,
    };
    if (scalar @lines > 2) {
        $lines[1] =~ s/^\s+|\s+$//g;
        $address->{suburb} = $lines[1];
    }
    return $address;
}

sub filter_licencees {
    my ($value) = @_;

    # remove empy lines
    $value =~ s/^\s*\n$//gs;

    # trim remaining
    $value =~ s/^\s+|\s+$//g;

    # split around newlines
    my @fields = split(/\s*\n\s*/, $value);
    my @licencees;
    push(
        @licencees, {
            name           => shift @fields,
            licence_number => shift @fields,
            branche        => shift @fields,
        }) for (1 .. int(scalar @fields / 3));
    return \@licencees;
}

my $city;
open(my $fh, '<:encoding(UTF-8)', $filename)
    or die "Could not open file '$filename' $!";
my @files = <$fh>;
chomp @files;

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

                        # save raw HTML as backup
                        my ($licence_id) =
                            $self->final_url =~ /licenceid=([^&]+)&/;
                        say "$city: $licence_id";
                        my $outfile = "./raw/$city/$licence_id.html";
                        open(my $fh, ">", $outfile)
                            or die "Could not open $outfile: $!";
                        print $fh $self->response->decoded_content;
                        close($fh);

                        # Declare the scraper once and then reuse it
                        state $scraper = scraper {

                            # individual agent fields
                            process
                                '#ContentContainer_MainContent_FirstNameLabel',
                                first_name => 'text';
                            process
                                '#ContentContainer_MainContent_MiddleNamesLabel',
                                middle_name => 'text';
                            process
                                '#ContentContainer_MainContent_SurnameLabel',
                                last_name => 'text';
                            process
                                '#ContentContainer_MainContent_FormernameLabel',
                                former_name => 'text';
                            process
                                '#ContentContainer_MainContent_AlsoKnownAsLabel',
                                preferred_name => 'text';
                            process '#ContentContainer_MainContent_PhoneLabel',
                                phone => 'text';
                            process '#ContentContainer_MainContent_EmailLabel',
                                email => [ 'text', sub { lc } ];
                            process
                                '#ContentContainer_MainContent_BusinessNameLabel',
                                company => 'text';
                            process
                                '#ContentContainer_MainContent_AddressLabel',
                                address => [ 'html', \&filter_address ];

                            # company fields
                            process '#ContentContainer_MainContent_NameLabel',
                                company => 'text';
                            process
                                '#ContentContainer_MainContent_TradingNameLabel',
                                trading_name => 'text';
                            process
                                '#ContentContainer_MainContent_FranchisegroupLabel',
                                franchise => 'text';
                            process
                                '#ContentContainer_MainContent_BusinessAddressLabel',
                                address => [ 'html', \&filter_address ];
                            process
                                '#ContentContainer_MainContent_RegisteredOfficeAddressLabel',
                                registered_office_address =>
                                [ 'html', \&filter_address ];
                            process '#', bla => 'text';
                            process '#', bla => 'text';
                            process '#', bla => 'text';
                            process '#', bla => 'text';

                            # licence fields
                            process
                                '#ContentContainer_MainContent_TypeOfRealEstateWorkLabel',
                                work_type => [ 'text', sub { lc } ];
                            process
                                '#ContentContainer_MainContent_ctl00_LicenceNumberLabel',
                                licence_number => 'text';
                            process
                                '#ContentContainer_MainContent_LicenceNumberLabel',
                                licence_number => 'text';
                            process
                                '#ContentContainer_MainContent_ctl00_LicenceTypeLabel',
                                licence_type => [ 'text', sub { lc } ];
                            process
                                '#ContentContainer_MainContent_LicenceTypeLabel',
                                licence_type => [ 'text', sub { lc } ];
                            process
                                '#ContentContainer_MainContent_ctl00_LicenceClassLabel',
                                licence_class => [ 'text', sub { lc } ];
                            process
                                '#ContentContainer_MainContent_LicenceClassLabel',
                                licence_class => [ 'text', sub { lc } ];
                            process
                                '#ContentContainer_MainContent_ctl00_CurrentStatusLabel',
                                licence_status => [ 'text', sub { lc } ];
                            process
                                '#ContentContainer_MainContent_CurrentStatusLabel',
                                licence_status => [ 'text', sub { lc } ];
                            process
                                '#ContentContainer_MainContent_ctl00_DateFirstEnteredLabel',
                                licence_created => [ 'text', \&filter_date ];
                            process
                                '#ContentContainer_MainContent_DateFirstEnteredLabel',
                                licence_created => [ 'text', \&filter_date ];
                            process
                                '#ContentContainer_MainContent_ctl00_CurrentPeriodLabel',
                                licence_period =>
                                [ 'text', \&filter_date_period ];
                            process
                                '#ContentContainer_MainContent_CurrentPeriodLabel',
                                licence_period =>
                                [ 'text', \&filter_date_period ];
                            process
                                '#ContentContainer_MainContent_ctl00_ExpiryDateLabel',
                                licence_expire => [ 'text', \&filter_date ];
                            process
                                '#ContentContainer_MainContent_ExpiryDateLabel',
                                licence_expire => [ 'text', \&filter_date ];
                            process
                                '#ContentContainer_MainContent_LicenceesGridView > tbody',
                                licencees => [ 'text', \&filter_licencees ];

                            # complaints history fields
                            process
                                '#ContentContainer_MainContent_NoDisciplinaryHistory',
                                disciplinary_history => ['text', sub { s/^\s+|\s+$//g } ];
                        };

                        # Employ amazing Perl (en|de)coding powers to handle HTML charsets
                        my $doc =
                            $scraper->scrape($self->response->decoded_content,
                            $self->final_url);

                        # store in couchdb
                        $doc->{_id}       = $doc->{licence_number};
                        $doc->{reaa_link} = $self->final_url->as_string;
                        # delete empty keys
                        map { delete $doc->{$_} unless $doc->{$_} } keys %$doc;
                        my @res = $sc->put_doc({ doc => $doc });
                        p @res;
                    })->wait;
            },
        },
    }) for @files;
$monitor->scan;

while (1) {
    sleep 1;
    $monitor->scan;
}
