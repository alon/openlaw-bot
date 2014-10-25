#!/usr/bin/env perl
use AkomaNtoso;
use Data::Dump;

print("StandardImplemented ${StandardImplemented}\n");
print("StandardImplemented explicit: ${AkomaNtoso::StandardImplemented}\n");

my $a = new AkomaNtoso();
dd $a;
$a->set_title("well");
my $title = $a->get_title();
print("title: $title\n");
