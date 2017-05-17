package ScraperWorker;

use 5.020;
use common::sense;
use Mouse;

use WWW::Mechanize::PhantomJS;
use Data::Printer;
use HTML::Entities;
use Term::ANSIColor;

$Term::ANSIColor::AUTORESET = 1;

my %colour = (
    8910 => 'red',
    8911 => 'blue',
    8912 => 'green',
    8913 => 'yellow',
    8914 => 'magenta',
);

has 'port' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has 'city' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has 'rpp' => (
    is      => 'rw',
    isa     => 'Str',
    default => sub { 100 },
    lazy    => 1,
);

sub cprint {
    my ($self, $msg) = @_;
    say colored("\t[" . $self->port . "] " . $self->city . ": $msg",
        $colour{ $self->port });
}

sub dump_links {
    my ($self, @links) = @_;

    $self->cprint("sending links to parser");

    mkdir('./links') unless (-d './links');
    my $filename = './links/' . $self->city;
    open(my $fh, '>', $filename) or die "Could not open $filename: $!";
    print $fh $_ . $/ for @links;
    close($fh);
}

sub run {
    my ($self) = @_;
    eval {
        my $mech = WWW::Mechanize::PhantomJS->new(port => $self->port);

        $self->cprint("getting");
        $mech->get("https://portal.reaa.govt.nz/public/register-search/");
        $self->cprint("submit form");
        $mech->submit_form(
            with_fields => {
                'ctl00$ctl00$ContentContainer$MainContent$SearchLocationText'
                    => $self->city,
            });
        $mech->click_button(id => 'ContentContainer_MainContent_SearchButton');
        $self->cprint($self->rpp . " results per page");
        $mech->submit_form(
            with_fields => {
                'ctl00$ctl00$ContentContainer$MainContent$PerPageDropDownList'
                    => $self->rpp,
            });
        $mech->eval(
            '__doPostBack(\'ctl00$ctl00$ContentContainer$MainContent$PerPageDropDownList\',\'\')'
        );
        my ($total) = $mech->eval(
            'document.querySelector(\'#ContentContainer_MainContent_ResultsLabel\').innerText'
        ) =~ m/of (\d+)/;
        $self->cprint("results: $total");
        $self->cprint("gather links on first page");
        my $base = $mech->base;
        my @links =
            map { $base . decode_entities($_) }
            $mech->content =~
            m/ContentContainer_MainContent_ResultsGridView_\w+NameLabel_\d+"><a href="([^"]+)"/g;
        $self->cprint("link count: " . @links . "/$total");

        my $pages = int($total / $self->rpp) + 1;
        $self->cprint("$pages pages total");
        if ($pages >= 2) {
            my $remaining = $self->rpp;
            for (my $p = 2; $p <= $pages; $p++) {
                $self->cprint("getting page $p/$pages");
                $mech->eval(
                    "__doPostBack('ctl00\$ctl00\$ContentContainer\$MainContent\$ResultsGridView', 'Page\$$p')"
                );
                my $pageno = $p - 1;
                my $matches = () = $mech->content =~ /(pageno=$pageno)/g;
                $remaining =
                    ($p == $pages)
                    ? $total % $self->rpp
                    : $self->rpp;
                while ($matches != $remaining) {
                    sleep 2;
                    $self->cprint("$matches : $remaining");
                    $self->cprint("reload page $p");
                    $mech->eval(
                        "__doPostBack('ctl00\$ctl00\$ContentContainer\$MainContent\$ResultsGridView', 'Page\$$p')"
                    );
                    sleep 10;
                    $matches = () = $mech->content =~ /(pageno=$pageno)/g;
                }
                $self->cprint("gather links on page $p/$pages");
                push(@links,
                    map { $base . decode_entities($_) }
                        $mech->content =~
                        m/ContentContainer_MainContent_ResultsGridView_\w+NameLabel_\d+"><a href="([^"]+)"/g
                );
                $self->cprint("link count: " . @links . "/$total");
            }
        }
        $self->dump_links(@links);
    };
    my $error = $@;
    $self->cprint("ERROR : $error") if $error;
    $self->dump_links($error);
}

1;
