package XML::Compile::WSDL11::Recursive;

use Modern::Perl '2010';    ## no critic (Modules::ProhibitUseQuotedVersion)

our $VERSION = '0.001';     # TRIAL VERSION
use utf8;
use Moo;
use MooX::Types::MooseLike::Base qw(HashRef InstanceOf);
use CHI;
use HTTP::Exception;
use LWP::UserAgent;
use URI;
use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::Transport::SOAPHTTP;
use XML::Compile::Util 'SCHEMA2001';
use XML::Compile::SOAP::Util 'WSDL11';
use XML::LibXML;

has cache => (
    is       => 'lazy',
    isa      => InstanceOf('CHI::Driver'),
    init_arg => undef,
    default  => sub { CHI->new( %{ shift->cache_parameters } ) },
);

has cache_parameters => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { { driver => 'Null' } },
);

has options => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { { allow_undeclared => 1 } },
);

has proxy => (
    is       => 'lazy',
    isa      => InstanceOf('XML::Compile::WSDL11'),
    init_arg => undef,
);

sub _build_proxy {
    my $self = shift;

    my $uri   = $self->uri;
    my $cache = $self->cache;

    my $proxy = $self->_build_proxy_cache(
        XML::Compile::WSDL11->new(
            $self->_get_uri_content_ref($uri),
            %{ $self->options },
        ),
        $uri,
    );
    $proxy->importDefinitions(
        $cache->get_multi_arrayref(
            [ grep { $cache->is_valid($_) } $cache->get_keys ],
        ),
    );
    return $proxy;
}

sub _build_proxy_cache {
    my ( $self, $proxy, @locations ) = @_;

    my $cache = $self->cache;

    for my $uri ( grep { not $cache->is_valid( $_->as_string ) } @locations )
    {
        my $content_ref = $self->_get_uri_content_ref($uri);
        my $document = XML::LibXML->load_xml( string => $content_ref );
        $cache->set( $uri->as_string => $document->toString );

        if ( 'definitions' eq $document->documentElement->getName ) {
            $proxy->addWSDL($content_ref);
        }
        $proxy->importDefinitions($content_ref);

        if ( my @imports
            = map { URI->new_abs( $_->getAttribute('schemaLocation'), $uri ) }
            $document->getElementsByTagNameNS( (SCHEMA2001) => 'import' ) )
        {
            $proxy = $self->_build_proxy_cache( $proxy, @imports );
        }
        if ( my @imports
            = map { URI->new_abs( $_->getAttribute('location'), $uri ) }
            $document->getElementsByTagNameNS( (WSDL11) => 'import' ) )
        {
            $proxy = $self->_build_proxy_cache( $proxy, @imports );
        }
        undef $document;
    }
    return $proxy;
}

has uri => (
    is       => 'ro',
    isa      => InstanceOf('URI'),
    required => 1,
    coerce   => sub { URI->new( $_[0] ) },
);

has user_agent => (
    is      => 'lazy',
    isa     => InstanceOf('LWP::UserAgent'),
    default => sub { LWP::UserAgent->new() },
);

sub _get_uri_content_ref {
    my ( $self, $uri ) = @_;
    my $response = $self->user_agent->get($uri);
    if ( $response->is_error ) {
        HTTP::Exception->throw( $response->code,
            status_message => sprintf '"%s": %s' =>
                ( $uri->as_string, $response->message // q{} ) );
    }
    return $response->decoded_content( ref => 1, raise_error => 1 );
}

1;

# ABSTRACT: Recursively compile a web service proxy

__END__

=pod

=encoding UTF-8

=for :stopwords Mark Gardner ZipRecruiter cpan testmatrix url annocpan anno bugtracker rt
cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 NAME

XML::Compile::WSDL11::Recursive - Recursively compile a web service proxy

=head1 VERSION

version 0.001

=head1 SYNOPSIS

    use XML::Compile::WSDL11::Recursive;

    my $wsdl = XML::Compile::WSDL11::Recursive->new(
                uri => 'http://example.com/foo.wsdl' );
    $wsdl->proxy->compileCalls();
    my ( $answer, $trace ) = $wsdl->proxy->call( hello => {name => 'Joe'} );

=head1 DESCRIPTION

From the
L<description of XML::Compile::WSDL11|XML::Compile::WSDL11/DESCRIPTION>:

=over

When the [WSDL] definitions are spread over multiple files you will need to
use L<addWSDL()|XML::Compile::WSDL11/"Extension"> (wsdl) or
L<importDefinitions()|XML::Compile::Schema/"Administration">
(additional schema's)
explicitly. Usually, interreferences between those files are broken.
Often they reference over networks (you should never trust). So, on
purpose you B<must explicitly load> the files you need from local disk!
(of course, it is simple to find one-liners as work-arounds, but I will
to tell you how!)

=back

This module implements that work-around, recursively parsing and compiling a
WSDL specification and any imported definitions and schemas. The wrapped WSDL
is available as a C<proxy> attribute.

It also provides a hook to use any L<CHI|CHI> driver so that retrieved files
may be cached locally, reducing dependence on network-accessible definitions.

You may also provide your own L<LWP::UserAgent|LWP::UserAgent> (sub)class
instance, possibly to correct on-the-fly any broken interreferences between
files as warned above.

=head1 ATTRIBUTES

=head2 cache

A read-only reference to the underlying L<CHI::Driver|CHI::Driver> object used
to cache schemas.

=head2 cache_parameters

A hash reference settable at construction to pass parameters to the L<CHI|CHI>
module used to cache schemas.  By default nothing is cached.

=head2 options

Optional hash reference of additional parameters to pass to the
L<XML::Compile::WSDL11|XML::Compile::WSDL11> constructor. Defaults to:

    { allow_undeclared => 1 }

=head2 proxy

Retrieves the resulting L<XML::Compile::WSDL11|XML::Compile::WSDL11> object.
Any definitions are retrieved and compiled on first access to this attribute.
If there are problems retrieving any files, an
L<HTTP::Exception|HTTP::Exception> is thrown with the details.

=head2 uri

Required string or L<URI|URI> object pointing to a WSDL file to compile.

=head2 user_agent

Optional instance of an L<LWP::UserAgent|LWP::UserAgent> that will be used to
get all WSDL and XSD content when the proxy cache is built.

=head1 SUPPORT

=head2 Perldoc

You can find documentation for this module with the perldoc command.

  perldoc XML::Compile::WSDL11::Recursive

=head2 Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

=over 4

=item *

MetaCPAN

A modern, open-source CPAN search engine, useful to view POD in HTML format.

L<http://metacpan.org/release/XML-Compile-WSDL11-Recursive>

=item *

Search CPAN

The default CPAN search engine, useful to view POD in HTML format.

L<http://search.cpan.org/dist/XML-Compile-WSDL11-Recursive>

=item *

AnnoCPAN

The AnnoCPAN is a website that allows community annotations of Perl module documentation.

L<http://annocpan.org/dist/XML-Compile-WSDL11-Recursive>

=item *

CPAN Ratings

The CPAN Ratings is a website that allows community ratings and reviews of Perl modules.

L<http://cpanratings.perl.org/d/XML-Compile-WSDL11-Recursive>

=item *

CPAN Forum

The CPAN Forum is a web forum for discussing Perl modules.

L<http://cpanforum.com/dist/XML-Compile-WSDL11-Recursive>

=item *

CPANTS

The CPANTS is a website that analyzes the Kwalitee ( code metrics ) of a distribution.

L<http://cpants.cpanauthors.org/dist/XML-Compile-WSDL11-Recursive>

=item *

CPAN Testers

The CPAN Testers is a network of smokers who run automated tests on uploaded CPAN distributions.

L<http://www.cpantesters.org/distro/X/XML-Compile-WSDL11-Recursive>

=item *

CPAN Testers Matrix

The CPAN Testers Matrix is a website that provides a visual overview of the test results for a distribution on various Perls/platforms.

L<http://matrix.cpantesters.org/?dist=XML-Compile-WSDL11-Recursive>

=item *

CPAN Testers Dependencies

The CPAN Testers Dependencies is a website that shows a chart of the test results of all dependencies for a distribution.

L<http://deps.cpantesters.org/?module=XML::Compile::WSDL11::Recursive>

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the web
interface at
L<https://github.com/mjgardner/xml-compile-wsdl11-recursive/issues>.
You will be automatically notified of any progress on the
request by the system.

=head2 Source Code

The code is open to the world, and available for you to hack on. Please feel free to browse it and play
with it, or whatever. If you want to contribute patches, please send me a diff or prod me to pull
from your repository :)

L<https://github.com/mjgardner/xml-compile-wsdl11-recursive>

  git clone git://github.com/mjgardner/xml-compile-wsdl11-recursive.git

=head1 AUTHOR

Mark Gardner <mjgardner@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by ZipRecruiter.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
