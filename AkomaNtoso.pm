package AkomaNtoso;

# This module implements AkomaNtoso $StandardImplemented (3.0 as of this writing)
#
# See:
# http://www.akomantoso.org/release-notes/akoma-ntoso-3.0-schema/schema-for-AKOMA-NTOSO-3.0
#
# It is an XML format.

use strict;
use warnings;
use English;
use utf8;

use XML::DOM;
use Data::Dump;

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter);

    our $VERSION = "0.0";
    our @EXPORT = qw($StandardImplemented);
}

our $StandardImplemented = "3.0";
our $test2 = 20;

__PACKAGE__->main() unless (caller);

sub new {
    my $class = shift;
    my $thedoc = new XML::DOM::Document;
    my $root = $thedoc->createElement('akomantoso');
    my $meta = $thedoc->createElement('meta');
    $root->appendChild($meta);
    $thedoc->appendChild($root);
    return bless({doc => $thedoc}, $class);
}

sub __FUNC__ { (caller 1)[3] }

sub doc {
    # Debugging helper
    my $self = shift;
    return $self->{'doc'};
}

sub toString {
    my $self = shift;
    return $self->doc->toString;
}

sub set_title {
    my $self = shift;
    my $title = shift;
    $self->{'title'} = $title;
}

sub get_title {
    my $self = shift;
    return $self->{'title'}
}

sub main {
    print "AkomaNtoso doesn't do anything when called. TODO: Testing\n";
}

1;
