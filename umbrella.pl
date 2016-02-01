# Copyright © 2015-2016 Difrex <difrex.punk@gmail.com>

use strict;
use warnings;

use Plack::Builder;
use Plack::Request;
use Plack::Response;

use Template;

use Search::Elasticsearch;
use II::Config;

use Encode qw(decode encode);

my $config = II::Config->new()->load();

# Connect to localhost:9200:
my $e = Search::Elasticsearch->new(
    nodes => [$config->{elastic_host}]
);

# Template::Toolkit
my $tt = Template->new({
            INCLUDE_PATH => 't',
            EVAL_PERL    => 1,
         }) || die $Template::ERROR, "\n";

# Debug
use Data::Dumper;

my $root = sub {
    my $env = shift;

    my $req = Plack::Request->new($env);
    my $query = $req->param('query');

    my $vars = {};
    
    my $b = '';
    my $body = '';
    if ($query) {
        $vars->{query} = $query;
        my @messages = search($query);
        foreach my $hit (@messages) {
            $vars->{score} = $hit->{_score};
            $vars->{message} = $hit->{_source}->{message};
            $vars->{msgid} = $hit->{_source}->{msgid};
            $vars->{author} = $hit->{_source}->{author};
            $vars->{to} = $hit->{_source}->{to};
            $vars->{subg} = $hit->{_source}->{subg};
            $vars->{echo} = $hit->{_source}->{echo};
            $vars->{time} = gmtime($hit->{_source}->{date});

            $tt->process('body.tpl', $vars, \$b);
            $body .= $b;
            $b = '';
        }
            
        print Dumper @messages;
    }


    my $h = '';
    my $form = '';
    my $f = '';
    $body = encode("UTF-8", $body);
    $tt->process('header.tpl', $vars, \$h);
    $tt->process('footer.tpl', $vars, \$f);
    $tt->process('form.tpl', $vars, \$form);
    return [ 200, [ 'Content-type' => 'text/html' ], [$h.$form.$body.$f], ];
};

# Mountpoints
# ###########
builder {
    mount '/'  => $root;
};


# Functions
# #########
sub search {
    my $req = shift;
    
    my $orig_req = $req;
    $req = decode('UTF-8', $req);
    my $results = $e->search(
        index => $config->{elastic_index},
        type  => 'post',
        body  => {
                query => {
                    match => { _all => "$req" }
                }
        }
    );

    my @m;
    foreach my $h ($results->{hits}->{hits}) {
        foreach my $hit (@$h) {
            print Dumper $hit;
            $hit->{_source}->{message} =~ s/\n/<br>\n/g;
            $hit->{_source}->{message} =~ s/^$/<br>\n/g;
            
            if ( $hit->{_score} <= 1 ) {
                $hit->{_score} = '<font color="green">&#9733;</font>';
            }
            elsif ( $hit->{_score} >= 1  and $hit->{_score} < 1.5 ) {
                $hit->{_score} = '<font color="green">&#9733;&#9733;</font>';
            }
            elsif ( $hit->{_score} >= 1.5 ) {
                $hit->{_score} = '<font color ="green">&#9733;&#9733;&#9733;</font>';
            }
            foreach my $keyword (split / /, $req) {
                $hit->{_source}->{post} =~ s/$keyword/<font color='red'>$keyword<\/font>/g;
                $hit->{_source}->{message} =~ s/$keyword/<font color='red'>$keyword<\/font>/g;
                $hit->{_source}->{subg} =~ s/$keyword/<font color='red'>$keyword<\/font>/g;
            }
            push @m, $hit;
        }
    }

    return @m;
}

