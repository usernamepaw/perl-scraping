use strict;
use warnings;
use LWP::UserAgent;
use HTML::TreeBuilder;
use Text::CSV;
 my $csv = Text::CSV->new( { binary => 1, eol => "\n" } );
my $url = 'https://www.bloomberg.com';
 my $ua = LWP::UserAgent->new;
$ua->timeout(10);
$ua->agent("Mozilla/5.0");
 my $response = $ua->get($url);
die "Could not fetch content from Bloomberg.com\n" if !$response->is_success;
 my $html_tree = HTML::TreeBuilder->new_from_content($response->decoded_content);
 my @articles = $html_tree->look_down( _tag => 'div', class => 'story-package-module-story' );
die "No articles found on Bloomberg.com\n" if !@articles;
 foreach my $article (@articles) {
    my $pub_date = $article->look_down( class => 'published-at' )->as_text;
    my $category = $article->look_down( class => 'story-package-module-headline-category' )->as_text;
    my $headline = $article->look_down( class => 'story-package-module-headline-text' )->as_text;
    my $authors = $article->look_down( class => 'story-package-module-byline' )->as_text;
    my $description = $article->look_down( class => 'story-package-module-dek' )->as_text;
     my @images = ();
    my @image_links = $article->look_down( class => 'story-package-module-image' );
    foreach my $image_link (@image_links) {
        my $name = $image_link->attr('data-fallback-src') || '';
        my $source = $image_link->attr('src');
        my $title = $image_link->attr('alt') || '';
        push @images, ($name, $source, $title);
    }
     my $download_date = scalar localtime;
    my $article_url = $url . $article->look_down( class => 'story-package-module-headline-text' )->attr('href');
     my @row = ($pub_date, $category, $headline, $authors, $description, $download_date, $article_url, @images);
    $csv->print( \*STDOUT, \@row );
}
 $html_tree->delete;