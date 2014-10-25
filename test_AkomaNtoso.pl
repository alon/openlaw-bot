#!/usr/bin/env perl
use AkomaNtoso;
use Data::Dump;

print("StandardImplemented ${StandardImplemented}\n");
print("StandardImplemented explicit: ${AkomaNtoso::StandardImplemented}\n");

print("Testing version ${AkomaNtoso::VERSION}\n");
my $a = new AkomaNtoso();
$a->set_title("well");
my $title = $a->get_title();
print("title: $title\n");
my $asString = $a->toString;
print("doc:   $asString\n");
