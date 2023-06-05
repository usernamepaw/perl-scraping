#!/usr/bin/perl

# typical cmd line:  perl bloomberg_scraper_v6d.pl --output_file /media/john/DATA/a-News/news_Bloomberg/Current/test_6d_15minute.csv
# note: all of the comments were made by me and not by the programmer

use strict;
use warnings;
use WWW::Mechanize;
use JSON::XS;
use Text::CSV_XS;
use HTML::TreeBuilder::LibXML;
use DateTime;
use DateTime::Format::Strptime;
use feature qw(say);
use IO::Handle;
use Getopt::Long;
use HTML::FormatText;
use HTML::TreeBuilder;


my $config = {



    'update_delay' => 900, # in seconds
    'max_images'   => 20,
    
    
    'output_file' => 'Result.csv',
    #'number_of_pages' => 2,
    'timezone'         => 'America/Chicago', # change to your target timezone
    'min_delay'        => 35,
    'max_delay'        => 90,
    'max_retries'      =>  9, # if error the max number of retries per page
    'retry_delay'      => 100, # delay in seconds before each retry
    'update_min_delay' => 900, # in seconds - default is 900 = 15 min - 1500 = 25
    'update_max_delay' => 1500, # in seconds default 1500
    'max_images'       => 20,
    'user_agents_file' => 'UserAgents.txt',
    'input_urls_file'  => 'links.txt',
};

my $result = GetOptions(
    'output_file=s'      => \$config->{'output_file'},
    'update_min_delay=s' => \$config->{'update_min_delay'},
    'update_max_delay=s' => \$config->{'update_max_delay'},
    'input_urls_file=s'  => \$config->{'input_urls_file'},   # will read in lost of url's download article then exit
);

if ( !defined($config->{'output_file'}) ) {
    die "Please provide output file name using --output_file option!\n";
}

# print strftime "%Y-%m-%d %H:%M:%S", localtime time;  # print current date and time

my $data = [];
my $retry = 0;

my $mech = WWW::Mechanize->new(autocheck => 0);
$mech->agent(
    get_random_user_agent()
);
$mech->stack_depth(0);

my $processed_articles = {};

    # Are we downloading links in the links,txt file ?
if ($config->{'input_urls_file'}) {
    my @articles_urls = read_articles_urls($config->{'input_urls_file'});
    foreach my $article_url (@articles_urls) {
        eval {
            unless ( exists($processed_articles->{$article_url}) ) {
                my $saved_articles = read_saved_articles($config->{'output_file'});
                unless ( exists($saved_articles->{$article_url})) {
                    print $article_url . "\n";
                    my $article = process_article($article_url);
                    $article->{'URL'} = $article_url;
                    #push @{$main_data}, $article;
                    
                    $processed_articles->{$article_url} = 1;
                    save_article( $article, $config->{'output_file'} );
                    random_delay();
                }
            }
        };
        if ($@) {
            if ( $retry > $config->{'max_retries'} ) {
                print "[" . $@ . "]\n";
                print "Error processing page! Writng output...\n";
                last;
            }
            else {
                $mech = WWW::Mechanize->new(autocheck => 0);
                $mech->agent(
                    get_random_user_agent()
                );
                $mech->stack_depth(0);
                print __LINE__, "[" . $@ . "]\n";
                print __LINE__, ": Retrying...\n";
                sleep($config->{'retry_delay'});
                $retry++;
                next;
            }
        }
        else {
            $retry = 0;
        }
    }
}
    # else we are not getting specified links and are getting articles from the main page
else {
    while (1) {
        eval {
            $mech->get(
                "https://www.bloomberg.com/",
                'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
                'accept-encoding' => 'gzip, deflate, br',
                'accept-language' => 'en-US,en;q=0.9,ru;q=0.8',
                'referer' => 'https://www.bloomberg.com/',
            );
            unless ($mech->success()) {
                $mech->save_content('Error.html', binmode => 1);
                die $@;
            }
            
            parse_main_data( $mech->content, $processed_articles );
        };
        if ($@) {
            if ( $retry > $config->{'max_retries'} ) {
                print "[" . $@ . "]\n";
                print "Error processing page! Writng output...\n";
                last;
            }
            else {
                $mech = WWW::Mechanize->new(autocheck => 0);
                $mech->agent(
                    get_random_user_agent()
                );
                $mech->stack_depth(0);
                print "[" . $@ . "]\n";
                print __LINE__, ": Retrying...\n";
                sleep($config->{'retry_delay'});
                $retry++;
                next;
            }
        }
        else {
            $retry = 0;
        }
        
        print scalar localtime ();                          # prints current time:  Mon May 22 19:53:21 2023 
        print " - waiting for the next run...\n";
        my $update_delay = $config->{'update_min_delay'} + int(rand($config->{'update_max_delay'} - $config->{'update_min_delay'}));
        my $min_wait = $update_delay / 60 ;
        print __LINE__, ": \$update_delay:  $update_delay  -- minutes: $min_wait\n" ;
        sleep($update_delay);
        
    }
}

print "Done!\n";

sub get_random_user_agent {
    my @user_agents;
    open(my $fh, '<:encoding(utf-8)', $config->{'user_agents_file'}) or die $!;
    while (my $user_agent = readline($fh)) {
        chomp($user_agent);
        if ($user_agent) {
            $user_agent =~ s/^\s+|\s+$//g;
            push @user_agents, $user_agent;
        }
        
    }
    close($fh);
    my $random_user_agent = $user_agents[rand @user_agents];
    print __LINE__, ": Using UserAgent: $random_user_agent \n";
    return $random_user_agent;
}

sub random_delay {
    my $delay = $config->{'min_delay'} + int(rand($config->{'max_delay'} - $config->{'min_delay'}));
    sleep($delay);
}

sub read_articles_urls {
    my $urls_file = shift;
    my @articles_urls;
    
    open(my $fh, '<:encoding(utf-8)', $urls_file) or die $!;
    while (my $url = readline($fh)) {
        chomp($url);
        if ($url) {
            push @articles_urls, $url;
        }
    }
    close($fh);
    
    return @articles_urls;
}

sub clear_output_fields {
    my $article = shift;
    my $output_fields = shift;
    
    foreach my $field (@{$output_fields}) {
        unless ($article->{$field}) {
            $article->{$field} = '';
        }
    }
}

sub save_article {
    my $article        = shift;
    my $output_file = shift;

    my $output_fields = [
        'Publication Date', 'Category', 'Headline',
        'Author 1', 'Author 2', 'Author 3', 'Author 4',
        'Description', 'Download Date',   'URL',
        #'Images'
    ];
    
    foreach my $image_index (1 .. $config->{'max_images'}) {
        push @{$output_fields}, "Image $image_index Name", "Image $image_index Source", "Image $image_index Title";
    }
    
    clear_output_fields($article, $output_fields);

    my $fh;
    my $saved_articles = {};
    if ( -e $output_file ) {
        open( $fh, '>>:encoding(utf8)', $output_file ) or die $!;
    }
    else {
        open( $fh, '>:encoding(utf8)', $output_file ) or die $!;
        say {$fh} join('|', @{$output_fields});
    }

    $fh->autoflush(1);
    
    my $csv = Text::CSV_XS->new(
        {
            always_quote => 0,
            sep_char     => "|",
            quote_space  => 0,
            binary       => 1,
        }
    ) or die "Cannot use CSV: " . Text::CSV_XS->error_diag();
    
    #say {$fh} join('|', @{$article}{ @{$output_fields} });
    $csv->combine( @{$article}{ @{$output_fields} } );
    say {$fh} $csv->string();
    close($fh);
}

sub read_saved_articles {
    my $output_file = shift;
    my $saved_articles = {};
    
    if (-e $output_file) {
        open(my $fh, '<:encoding(utf-8)', $output_file) or die $!;
        
        my $csv = Text::CSV_XS->new(
            {
                always_quote => 0,
                sep_char     => "|",
                quote_space  => 0,
                binary       => 1,
            }
        ) or die "Cannot use CSV: " . Text::CSV_XS->error_diag();
        
        my $header;
        
        while ( my $row = $csv->getline($fh) ) {
            if ( $. == 1 ) {
                @{$header} = @{$row};
            }
            else {
                my $record = {};
                @{$record}{@{$header}} = @{$row};
                
                # Remove ?srnd=premium-europe etc
                $record->{'URL'} =~ s/\?.+//;
                
                $saved_articles->{ $record->{'URL'} } = 1;
            }
        }
    }
    
    return $saved_articles;
}

sub parse_publication_date {

    #2023-03-19T17:34:52-04:00
    my $raw_date = shift;

    $raw_date =~ s/:(\d+)$/$1/;    # clear timezone offset
    my $format = new DateTime::Format::Strptime(
        pattern => '%Y-%m-%dT%H:%M:%S%z',

        #time_zone => 'GMT',
    );

    my $t = $format->parse_datetime($raw_date);
    $t->set_time_zone( $config->{'timezone'} );
    my $date = $t->strftime('%Y-%m-%d,%H%M,%a');
    return split /,/, $date;
}

sub parse_main_data {
    my $content = shift;
    my $processed_articles = shift;
    
    my $tree    = HTML::TreeBuilder::LibXML->new_from_content($content);
    
    my $saved_articles = read_saved_articles($config->{'output_file'});
    
    foreach my $article_url ( $tree->findvalues('//a[contains(@href, "/articles/")]/@href') ) {
        
        # Remove ?srnd=premium-europe etc
        $article_url =~ s/\?.+//;
        
        unless ($article_url =~ m{^https://www.bloomberg.com}) {
            $article_url = 'https://www.bloomberg.com' . $article_url;
        }
        
        #DEBUG
        #$article_url = 'https://www.bloomberg.com/news/articles/2023-04-06/jim-o-neill-says-uk-treasury-needs-imagination-to-spur-growth';
        
        unless ( exists($processed_articles->{$article_url}) ) {
            unless ( exists($saved_articles->{$article_url})) {
                print scalar localtime ();                          # prints current time:  Mon May 22 19:53:21 2023 
                print "  -- $article_url \n";                       # prints out saved article url
                my $article = process_article($article_url);
                $article->{'URL'} = $article_url;
                #push @{$main_data}, $article;
                
                $processed_articles->{$article_url} = 1;
                save_article( $article, $config->{'output_file'} );
                random_delay();
            }
        }
    }
}

sub parse_main_image {
    my $tree = shift;
    my $main_image;
    
    $main_image = $tree->findvalue('//div[@aria-label="Open image in viewer"]//img/@data-native-src');
    my $main_image_caption = $tree->findvalue('normalize-space(//div[@aria-label="Open image in viewer"]/following-sibling::figcaption/span[1])');
    return $main_image, $main_image_caption;
}

sub parse_article {
    my $content = shift;
    my $article = {};
    
    my $image_index = 1;
    
    my $tree    = HTML::TreeBuilder::LibXML->new_from_content($content);
    
    my $raw_json = $tree->findvalue('//script[@data-component-props="OverlayAd"]/text()');
    my $data = parse_json($raw_json);


    ($article->{'Main Image URL'}, $article->{'Main Image Caption'}) = parse_main_image($tree);
    if ($article->{'Main Image URL'}) {
        
        $article->{"Image $image_index Name"} = process_main_image($image_index, $article->{'Main Image URL'}, $data->{'story'}->{'slug'});
        $article->{"Image $image_index Source"} = '';
        $article->{"Image $image_index Title"} =$article->{'Main Image Caption'};
        $image_index++;
    }
    
    $article->{'Headline'} = $tree->findvalue('normalize-space(//h1)');
    $article->{'Category'} = $tree->findvalue('normalize-space(//div[contains(@class, "section-identifier")]//span)');
    #$article->{'Author'} = $tree->findvalue('normalize-space(//a[@rel="author"])');
    @{$article}{'Author 1', 'Author 2', 'Author 3', 'Author 4'} = parse_authors($data->{'story'}->{'authors'});
    
    $article->{'Publication Date'} = $tree->findvalue('normalize-space(//div[contains(@class, "lede-times")]/time/@datetime)');
    $article->{'Publication Date'} =~ s/T.+//;
    
    $article->{'Description'} = parse_description($data->{'story'}->{'body'});
    my ($download_date, $download_time) = get_download_datetime();
    $article->{'Download Date'} = $download_date . ' ' . $download_time;
    my $images_ids = find_images_ids($data->{'story'}->{'body'});
    my $charts = parse_charts($data->{'story'}->{'charts'});
    
   # print __LINE__, ": Processing images...\n";       # finding line being printed
    
    foreach my $image_id (@{$images_ids}) {
        $article->{"Image $image_index Name"} = process_image($image_id, $image_index, $data->{'story'}->{'imageAttachments'}, $data->{'story'}->{'slug'});
        
        my $image_source = '';
        my $image_title = '';
        if ( exists($charts->{$image_id}) ){
            if (exists($charts->{$image_id}->{'title'})) {
                $image_title = $charts->{$image_id}->{'title'};
            }
            else {
                $image_title = '';
            }
            if (exists($charts->{$image_id}->{'source'})) {
                $image_source = $charts->{$image_id}->{'source'};
                $image_source =~ s/Source:\s*//i;
            }
            else {
                $image_source = '';
            }
        }
        $article->{"Image $image_index Source"} = $image_source;
        $article->{"Image $image_index Title"} = $image_title;
        
        $image_index++;
    }
    
    return $article;
}

sub parse_charts {
    my $data = shift;
    my $charts = {};
    
    foreach my $chart (@{$data}) {
        my $chart_id = $chart->{'id'};
        $charts->{$chart_id} = $chart;
    }
    
    return $charts;
}

sub find_images_ids {
    my $content = shift;
    my $ids = [];
    
    my $tree    = HTML::TreeBuilder::LibXML->new_from_content($content);
    
    foreach my $image_id ($tree->findvalues('//figure[not(@data-image-type="video")]/@data-id')) {
        push @{$ids}, $image_id;
    }
    return $ids;
}

sub process_main_image {
    my $index = shift;
    my $image_url = shift;
    my $slug = shift;

    my $downloaded_image_name = '';
    
    $slug =~ s{^.+?/}{};
    my ($extension) = $image_url =~ m/(\.\w+)$/;
    
    my $mech = WWW::Mechanize->new(autocheck => 0);
    $mech->agent(get_random_user_agent());
    $mech->get($image_url);
    
    $downloaded_image_name = $slug . '_' . $index . $extension;
    
    #Sanitize filename
    $downloaded_image_name =~ s/[^A-Za-z0-9\-\._ ]//g;
    
    $mech->save_content('images/' . $downloaded_image_name, binmode => 1);

    return $downloaded_image_name;
}

sub process_image {
    my $image_id = shift;
    my $index = shift;
    my $images_data = shift;
    my $slug = shift;

    my $image_url = '';
    my $downloaded_image_name = '';
    
    if (exists($images_data->{$image_id}->{'baseUrl'})) {
        $image_url = $images_data->{$image_id}->{'baseUrl'};
        
        $slug =~ s{^.+?/}{};
        my ($extension) = $image_url =~ m/(\.\w+)$/;
        
        my $mech = WWW::Mechanize->new(autocheck => 0);
        $mech->agent(get_random_user_agent());
        $mech->get($image_url);
        
        $downloaded_image_name = $slug . '_' . $index . $extension;
        
        #Sanitize filename
        $downloaded_image_name =~ s/[^A-Za-z0-9\-\._ ]//g;
        
        $mech->save_content('images/' . $downloaded_image_name, binmode => 1);
    }
    
    return $downloaded_image_name;
}

sub get_download_datetime {
    my $dt = DateTime->now;
    my $date = $dt->ymd;
    my $time = $dt->hms;
    return $date, $time;
}

sub parse_authors {
    my $authors = shift;
    return map {$_->{'name'}} @{$authors};
}

sub parse_description {
    my $content = shift;
    my $tree = HTML::TreeBuilder::LibXML->new_from_content($content);
    
    # Remove non-article nodes (ads etc.)
    foreach my $node ($tree->findnodes('//body/*[name() != "p"]|//body/p[a[contains(., "Read more:")]]')) {
        $node->delete();
    }
    
    my $formatter = HTML::FormatText->new( lm => 0, rm => 1000 );
    my $html = ($tree->findnodes('//body'))->[0]->as_HTML;
    $html =~ s/<meta.+?<\/meta>//g;
    my $node = HTML::TreeBuilder->new_from_content($html);
    my $description =
      $formatter->format( $node );
    
    #Keep original paragraph spacing
    #$description =~ s/\s+/ /g;
    
    return $description;
}

sub process_article {
    my $article_url = shift;

    my $mech = WWW::Mechanize->new(autocheck => 0);
    $mech->agent(get_random_user_agent());
    $mech->stack_depth(0);
    $mech->get(
        $article_url,
        'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'accept-encoding' => 'gzip, deflate, br',
        'accept-language' => 'en-US,en;q=0.9,ru;q=0.8',
        'referer' => 'https://www.bloomberg.com/',
    );
    unless ($mech->success()) {
        $mech->save_content('Error.html', binmode => 1);
        die $@;
    }
    #$mech->save_content('Article.html');
    my $article = parse_article($mech->content);
    
    return $article;
}

sub parse_json {
    my $content = shift;

    my $coder = JSON::XS->new->ascii->pretty->allow_nonref;
    my $data  = $coder->decode($content);
    return $data;
}
