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

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter);

    our $VERSION = 0.0;
    our @EXPORT = qw($StandardImplemented);
}

our $StandardImplemented = "3.0";
our $test2 = 20;

__PACKAGE__->main() unless (caller);

sub new {
    my $class = shift;
    return bless({}, $class);
}

sub __FUNC__ { (caller 1)[3] }

sub set_title {
    my $self = shift;
    my $title = shift;
    print STDERR __FUNC__, ": $title\n";
}

sub main {
    print "AkomaNtoso doesn't do anything when called. TODO: Testing\n";
}

1;
