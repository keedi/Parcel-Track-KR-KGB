package Parcel::Track::KR::KGB;
# ABSTRACT: Parcel::Track driver for the KGB LOGIS

use utf8;

use Moo;

our $VERSION = '0.002';

with 'Parcel::Track::Role::Base';

use Encode;
use HTML::Selector::XPath;
use HTML::TreeBuilder::XPath;
use HTTP::Tiny;
use List::MoreUtils;

#
# to support HTTPS
#
use IO::Socket::SSL;
use Mozilla::CA;
use Net::SSLeay;

our $URI   = 'https://www.kgbls.co.kr/sub5/trace.asp?f_slipno=%s';
our $AGENT = 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';

sub BUILDARGS {
    my ( $class, @args ) = @_;

    my %params;
    if ( ref $args[0] eq 'HASH' ) {
        %params = %{ $args[0] };
    }
    else {
        %params = @args;
    }
    $params{id} =~ s/\D//g;

    return \%params;
}

sub uri { sprintf( $URI, $_[0]->id ) }

sub track {
    my $self = shift;

    my %result = (
        from   => q{},
        to     => q{},
        result => q{},
        htmls  => [],
        descs  => [],
    );

    my $http = HTTP::Tiny->new(
        agent      => $AGENT,
        verify_SSL => 1,
    );

    my $res = $http->get( $self->uri );
    unless ( $res->{success} ) {
        $result{result} = 'failed to get parcel tracking info from the site';
        return \%result;
    }

    my $content = Encode::encode( 'utf-8', Encode::decode( 'cp949', $res->{content} ) );

    #
    # http://stackoverflow.com/questions/19703341/disabling-html-entities-expanding-in-htmltreebuilder-perl-module
    #
    my $tree = HTML::TreeBuilder::XPath->new;
    $tree->ignore_unknown(0);
    $tree->no_expand_entities(1);
    $tree->attr_encoded(1);
    $tree->parse($content);
    $tree->eof;

    my $prefix =
        '/html/body/table[3]/tr/td[4]/table[2]/tr/td[2]/table[3]/tr/td[2]/table[1]/tr[2]/td/table/tr/td[2]';

    my @tables = ( $tree->findnodes("$prefix/table") );

    #
    # remove some need-less inner tables
    #
    shift @tables;
    shift @tables;
    shift @tables;
    pop @tables;

    #
    # extract each rows
    #
    my @real_tables;
    my @table_indexes;
    my $it = List::MoreUtils::natatime( 2, @tables );
    while ( my ( $table, $border ) = $it->() ) {
        push @real_tables, $table;
    }

    unless (@real_tables) {
        $result{result} = 'cannot find such parcel info';
        return \%result;
    }

    #$result{from}  = 'N/A'; # KGB doesn't provide from information
    #$result{to}    = 'N/A'; # KGB doesn't provide to   information
    $result{htmls} = [ join( "\n", map $_->as_HTML, @real_tables ) ];

    my $index       = 0;
    my $xpath_index = 0;
    for my $table (@real_tables) {
        $xpath_index = $index++ * 2 + 4;

        my $place  = $tree->findvalue("$prefix/table[$xpath_index]/tr/td[1]");
        my $time   = $tree->findvalue("$prefix/table[$xpath_index]/tr/td[2]");
        my $detail = $tree->findvalue("$prefix/table[$xpath_index]/tr/td[3]");

        push(
            @{ $result{descs} },
            map {
                my $desc = $_;

                my $regex = Encode::encode_utf8('다\\.');
                $desc =~ s/($regex)(\S)/$1 $2/gms;

                $desc =~ s/(^\s+|\s+$)//gms;
                $desc =~ s/\r+//gms;
                $desc =~ s/\n+/ /gms;
                $desc =~ s/ +/ /gms;

                $desc;
            } join( q{ }, $time, $place, $detail ),
        );

        $result{result} = $result{descs}->[-1];
        $result{result} =~ s/\..*//;
    }

    return \%result;
}

1;

# COPYRIGHT

__END__

=for Pod::Coverage BUILDARGS

=head1 SYNOPSIS

    use Parcel::Track;

    # Create a tracker
    my $tracker = Parcel::Track->new( 'KR::KGB', '1234-567-890' );

    # ID & URI
    print $tracker->id . "\n";
    print $tracker->uri . "\n";
    
    # Track the information
    my $result = $tracker->track;
    
    # Get the information what you want.
    if ( $result ) {
        print "$result->{from}\n";
        print "$result->{to}\n";
        print "$result->{result}\n";
        print "$_\n" for @{ $result->{descs} };
        print "$_\n" for @{ $result->{htmls} };
    }
    else {
        print "Failed to track information\n";
    }


=attr id

=method track

=method uri


=head1 SEE ALSO

=for :list
* L<Parcel::Track>
* L<KGB LOGIS|https://www.kgbls.co.kr/>
