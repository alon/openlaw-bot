#!/usr/bin/perl -w

use v5.14;
use strict;
no strict 'refs';
use English;
use utf8;

use Data::Dumper;

use constant { true => 1, false => 0 };

our $extref_sig = '\bו?[בהלמש]?(חוק|פקוד[הת]|תקנות|צו|החלטה|תקנון|הוראו?ת|הודעה|כללים?|חוק[הת]|אמנ[הת]|דברי?[ -]ה?מלך)\b';
our $type_sig = 'חלק|פרק|סימן|לוח(ות)? השוואה|נספח|תוספת|טופס|לוח|טבל[הא]';


if ($#ARGV>=0) {
	my $fin = $ARGV[0];
	my $fout = $fin;
	$fout =~ s/(.*)\.[^.]*/$1.txt2/;
	open(my $FIN,"<:utf8",$fin) || die "Cannot open file \"$fin\"!\n";
	open(STDOUT, ">$fout") || die "Cannot open file \"$fout\"!\n";
	local $/;
	$_ = <$FIN>;
} else {
	binmode STDIN, "utf8";
	local $/;
	$_ = <STDIN>;
}

binmode STDOUT, "utf8";
binmode STDERR, "utf8";

# General cleanup
s/<!--.*?-->//sg;  # Remove comments
s/\r//g;           # Unix style, no CR
s/[\t\xA0]/ /g;    # Tab and hardspace are whitespaces
s/^[ ]+//mg;       # Remove redundant whitespaces
s/[ ]+$//mg;       # Remove redundant whitespaces
s/$/\n/s;          # Add last linefeed
s/\n{3,}/\n\n/sg;  # Convert three+ linefeeds
s/\n\n$/\n/sg;     # Remove last linefeed

if (/[\x{202A}-\x{202E}]/) {
	tr/\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}//d; # Throw away all BIDI characters
}
tr/\x{2000}-\x{200A}\x{205F}/ /; # Convert typographic spaces
tr/\x{200B}-\x{200D}//d;         # Remove zero-width spaces
tr/־–—‒―\xAD/-/;   # Convert typographic dashes
tr/״”“„‟″‶/"/;     # Convert typographic double quotes
tr/`׳’‘‚‛′‵/'/;    # Convert typographic single quotes
s/[ ]{2,}/ /g;     # Pack  long spaces

# Unescape HTML characters
$_ = unescape_text($_);

s/([ :])-([ \n])/$1–$2/g;
s/([א-ת]) ([,.:;])/$1$2/g;

s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&escape_text($1)/egs;

# Parse various elements
s/^(?|<שם> *\n?(.*)|=([^=].*)=)\n/&parse_title($1)/em; # Once!
s/^<חתימות> *\n?(((\*.*\n)+)|(.*\n))/&parse_signatures($1)/egm;
s/^<פרסום> *\n?(.*)\n/&parse_pubdate($1)/egm;
# s/^<מקור> *\n?(.*)\n\n/<מקור>\n$1\n<\\מקור>\n\n/egm;
s/^<(מבוא|הקדמה)> *\n?/<הקדמה>\n/gm;
s/^-{3,}$/<מפריד>/gm;

# Parse links and remarks
s/\[\[(?:קובץ:|תמונה:|[fF]ile:)(.*?)\]\]/<תמונה $1>/gm;

s/(?<=[^\[])\[\[ *([^\]]*?) *\| *(.*?) *\]\](?=[^\]])/&parse_link($1,$2)/egm;
s/(?<=[^\[])\[\[ *(.*?) *\]\](?=[^\]])/&parse_link('',$1)/egm;

s/(?<=[^\(])\(\( *(.*?) *(?:\| *(.*?) *)?\)\)(?=[^\)])/&parse_remark($1,$2)/egs;

# Parse structured elements
s/^(=+)(.*?)\1\n/&parse_section(length($1),$2)/egm;
s/^<סעיף *(.*?)>(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
s/^(@.*?) +(:+ .*)$/$1\n$2/gm;
s/^@ *(\(תיקון.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
s/^@ *(\d\S*) *\n/&parse_chapter($1,"","סעיף")/egm;
s/^@ *(\d[^ .]*\.) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
s/^@ *([^ \n.]+\.) *(.*?)\n/&parse_chapter($1,$2,"סעיף")/egm;
s/^@ *(\(.*?\)) *(.*?)\n/&parse_chapter($1,$2,"סעיף*")/egm;
s/^@ *(.*?)\n/&parse_chapter("",$1,"סעיף*")/egm;
s/^([:]+) *(\([^( ]+\)) *(\([^( ]+\))/$1 $2\n$1: $3/gm;
s/^([:]+) *(\([^( ]+\)|\[[^[ ]+\]|) *(.*)\n/&parse_line(length($1),$2,$3)/egm;

# Parse file linearly, constructing all ankors and links
$_ = linear_parser($_);
s/__TOC__/&insert_TOC()/e;
s/__NOTOC__ *//g;

s/(?<=\<ויקי\>)\s*(.*?)\s*(?=\<\/(ויקי)?\>)/&unescape_text($1)/egs;
# s/\<תמונה\>\s*(.*?)\s*\<\/(תמונה)?\>/&unescape_text($1)/egs;

s/(^\{\|(.*\n)+^\|\} *$)/&parse_wikitable($1)/egm;

print $_;
exit;
1;


sub parse_title {
	my $_ = shift;
	my ($fix, $str);
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	$str = "<שם>\n";
	$str .= "<תיקון $fix>\n" if ($fix);
	$str .= "$_\n";
	return $str;
}

sub parse_section {
	my ($level, $_) = @_;
	my ($type, $num, $fix, $extra);
	
	$level = 2 unless defined $level;
	
	$_ = unquote($_);
	($_, $fix) = get_fixstr($_);
	($_, $extra) = get_extrastr($_);
	
	# print STDERR "parse_section with |$_|\n";
	
	if (/^\((.*?)\)$/) {
		$num = '';
	} elsif (s/^\((.*?)\) *//) {
		$num = $1;
	} elsif (/^(.+?)( *:| +[-])/) {
		$num = get_numeral($1);
	} elsif (/^((?:[^ (]+( +|$)){2,3})/) {
		$num = get_numeral($1);
	} else {
		$num = '';
	}
	
	($type) = (/\bה?($type_sig)\b/);
	$type = '' if !defined $type;
	$type = 'לוחהשוואה' if ($type =~ /השוואה/);
	
	my $str = "<קטע";
	$str .= " $level" if ($level);
	$str .= " $type" if ($type);
	$str .= " $num" if ($type && $num ne '');
	$str .= ">";
	$str .= "<תיקון $fix>" if ($fix);
	$str .= "<אחר [$extra]>" if ($extra);
	$str .= " $_\n";
	return $str;
}

sub parse_chapter {
	my ($num, $desc,$type) = @_;
	my ($fix, $extra, $ankor);
	
	$desc = unquote($desc);
	($desc, $fix) = get_fixstr($desc);
	($desc, $extra) = get_extrastr($desc);
	($desc, $ankor) = get_ankor($desc);
	$desc =~ s/"/&quote;/g;
	$num =~ s/[.,]$//;
	
	my $str = "<$type" . ($num ? " $num" : "") . ">";
	$str .= "<תיאור \"$desc\">" if ($desc);
	$str .= "<תיקון $fix>" if ($fix);
	$str .= "<אחר \"[$extra]\">" if ($extra);
	$str .= "\n";
	return $str;
}

sub parse_line {
	my ($len,$id,$line) = @_;
	# print STDERR "|$id|$line|\n";
	if ($id =~ /\(\(/) {
		# ((remark))
		$line = $id.$line;
		$id = '';
	}
	$id = unparent($id);
	$line =~ s/^ *(.*?) *$/$1/;
	my $str;
	$str = "ת"x($len+($id?1:0));
	$str = ($id ? "<$str $id> " : "<$str> ");
	$str .= "<הגדרה> " if ($line =~ s/^[-–] *//);
	$str .= "$line" if (length($line)>0);
	$str .= "\n";
	return $str;
}

sub parse_link {
	my ($id,$txt) = @_;
	my $str;
	$id = unquote($id);
	($id,$txt) = ($txt,$1) if ($txt =~ /^w:(.*)$/ && !$id); 
	$str = ($id ? "<קישור $id>$txt</>" : "<קישור>$txt</>");
	return $str;
}

sub parse_remark {
	my ($text,$tip) = @_;
	# print STDERR "|$text|$tip|" . length($tip) . "\n";
	if ($tip) {
		return "<תיבה $tip>$text</>";
	} else {
		return "<הערה>$text</>";
	}
}

sub parse_signatures {
	my $_ = shift;
	chomp;
#	print STDERR "Signatures = |$_|\n";
	my $str = "<חתימות>\n";
	s/;/\n/g;
	foreach (split("\n")) {
		s/^\*? *(.*?) *$/$1/;
		s/ *[\|\,] */ | /g;
		$str .= "* $_\n";
		# /^\*? *([^,|]*?)(?: *[,|] *(.*?) *)?$/;
		# $str .= ($2 ? "* $1 | $2\n" : "* $1\n");
	}
	return $str;
}

sub parse_pubdate {
	my $_ = shift;
	return "<פרסום>\n  $_\n"
}

#---------------------------------------------------------------------

sub parse_wikitable {
	# Based on [mediawiki/core.git]/includes/parser/Parser.php doTableStuff() function
	my @lines = split(/\n/,shift);
	my $out = '';
	my ($last_tag, $previous);
	my (@td_history, @last_tag_history, @tr_history, @tr_attributes, @has_opened_tr);
	my ($indent_level, $attributes);
	for (@lines) {
		s/^ *(.*?) *$/$1/;
		if ($_ eq '') {
			$out .= "\n";
			next;
		}
		
		if (/^\{\|(.*)$/) {
			$attributes = ($1);
			$_ = "<table$1>\n";
			push @td_history, false;
			push @last_tag_history, '';
			push @tr_history, false;
			push @tr_attributes, '';
			push @has_opened_tr, false;
		} elsif ( scalar(@td_history) == 0 ) {
			# Don't do any of the following
			$out .= "$_\n";
			next;
		} elsif (/^\|\}(.*)$/ ) {
			# We are ending a table
			$_ = "</table>\n$1";
			$last_tag = pop @last_tag_history;
			$_ = "<tr><td></td></tr>\n$_" if (!(pop @has_opened_tr));
			$_ = "</tr>\n$_" if (pop @tr_history);
			$_ = "</$last_tag>$_" if (pop @td_history);
			pop @tr_attributes;
			# $_ .= "</dd></dl>" x $indent_level;
		} elsif ( /^\|-(.*)/ ) {
			# Now we have a table row
			
			# Whats after the tag is now only attributes
			$attributes = $1;
			pop @tr_attributes;
			push @tr_attributes, $attributes;
			
			$_ = '';
			$last_tag = pop @last_tag_history;
			pop @has_opened_tr;
			push @has_opened_tr, true;
			
			$_ = "</tr>\n" if (pop @tr_history);
			$_ = "</$last_tag>$_" if (pop @td_history);
			
			push @tr_history, false;
			push @td_history, false;
			push @last_tag_history, '';
		} elsif (/^\!\! *(.*)$/) {
			my @cells = split( / *\|\| */, $1 );
			s/(.*)/<col>$1<\/col>/ for (@cells);
			$_ = join('', @cells);
			$_ = "<colgroup>$_</colgroup>";
		} elsif (/^(?|\|(\+)|(\|)|(\!)) *(.*)$/) {
			# This might be cell elements, td, th or captions
			my $type = $1; $_ = $2;
			
			s/!!/||/g if ( $type eq '!' );
			my @cells = split( / *\|\| */, $_ , -1);
			$_ = '';
			# print STDERR "Cell is |" . join('|',@cells) . "|\n";
			
			# Loop through each table cell
			foreach my $cell (@cells) {
				
				$previous = '';
				if ($type ne '+') {
					my $tr_after = pop @tr_attributes;
					if ( !(pop @tr_history) ) {
						# $previous = "<tr " . (pop @tr_attributes) . ">\n";
						$previous = "<tr$tr_after>";
					}
					push @tr_history, true;
					push @tr_attributes, '';
					pop @has_opened_tr;
					push @has_opened_tr, true;
				}
				
				$last_tag = pop @last_tag_history;
				$previous = "</$last_tag>$previous" if (pop @td_history);
				
				if ( $type eq '|' ) {
					$last_tag = 'td';
				} elsif ( $type eq '!' ) {
					$last_tag = 'th';
				} elsif ( $type eq '+' ) {
					$last_tag = 'caption';
				} else {
					$last_tag = '';
				}
				
				push @last_tag_history, $last_tag;
				
				# A cell could contain both parameters and data
				my @cell_data = split( / *\| */, $cell, 2 );
				
				if (!defined $cell_data[0]) {
					$cell = "$previous<$last_tag>"; 
					# print STDERR "Empty cell data at |" . join('|',@cells) . "|\n";
				} elsif ( $cell_data[0] =~ /\[\[|\{\{/ ) {
					$cell = "$previous<$last_tag>$cell";
				} elsif ( @cell_data < 2 ) {
					$cell = "$previous<$last_tag>$cell_data[0]";
				} else {
					$attributes = $cell_data[0];
					$cell = $cell_data[1];
					$cell = "$previous<$last_tag $attributes>$cell";
				}
				
				$_ .= $cell;
				push @td_history, true;
			}
		}
		# $out .= $_ . "\n";
		$out .= $_;
	}

	# Closing open td, tr && table
	while ( @td_history ) {
		$out .= "</td>" if (pop @td_history);
		$out .= "</tr>\n" if (pop @tr_history);
		$out .= "<tr><td></td></tr>\n" if (!(pop @has_opened_tr));
		$out .= "</table>\n";
	}

	# Remove trailing line-ending (b/c)
	$out =~ s/\n$//s;
	
	# special case: don't return empty table
	if ( $out eq "<table>\n<tr><td></td></tr>\n</table>" ) {
		$out = '';
	}
	
	return $out;
}

#---------------------------------------------------------------------

sub get_fixstr {
	my $_ = shift;
	my @fix = ();
	my $fix_sig = '(?:תיקון|תקון|תיקונים):?';
	push @fix, unquote($1) while (s/(?| *\($fix_sig *(.*?) *\)| *\[$fix_sig *(.*?) *\])//);
	s/^ *(.*?) *$/$1/;
	s/\bה(תש[א-ת"]+)\b/$1/g for (@fix);
	return ($_, join(', ',@fix));
}

sub get_extrastr {
	my $_ = shift;
	my $extra = undef;
	$extra = unquote($1) if (s/(?<=[^\[])\[ *([^\[\]]+) *\] *//) || (s/^\[ *([^\[\]]+) *\] *//);
	s/^ *(.*?) *$/$1/;
	$extra =~ s/(?=\()/\<wbr\>/g if defined $extra;
	return ($_, $extra);
}

sub get_ankor {
	my $_ = shift;
	my @ankor = ();
	push @ankor, unquote($1) while (s/(?| *\(עוגן:? *(.*?) *\)| *\[עוגן:? *(.*?) *\])//);
	return ($_, join(', ',@ankor));
}

sub get_numeral {
	my $_ = shift;
	return '' if (!defined($_));
	my $num = '';
	my $token = '';
	s/[.,"']//g;
	$_ = unparent($_);
	while ($_) {
		$token = '';
		given ($_) {
			($num,$token) = ("0",$1) when /^(ה?מקדמית?)\b/;
			($num,$token) = ("1",$1) when /^(ה?ראשו(ן|נה)|אחד|אחת])\b/;
			($num,$token) = ("2",$1) when /^(ה?שניי?ה?|ש[תנ]יי?ם)\b/;
			($num,$token) = ("3",$1) when /^(ה?שלישית?|שלושה?)\b/;
			($num,$token) = ("4",$1) when /^(ה?רביעית?|ארבעה?)\b/;
			($num,$token) = ("5",$1) when /^(ה?חמי?שית?|חמש|חמי?שה)\b/;
			($num,$token) = ("6",$1) when /^(ה?שי?שית?|שש|שי?שה)\b/;
			($num,$token) = ("7",$1) when /^(ה?שביעית?|שבעה?)\b/;
			($num,$token) = ("8",$1) when /^(ה?שמינית?|שמונה)\b/;
			($num,$token) = ("9",$1) when /^(ה?תשיעית?|תשעה?)\b/;
			($num,$token) = ("10",$1) when /^(ה?עשירית?|עשרה?)\b/;
			($num,$token) = ("11",$1) when /^(ה?אחד[- ]עשר|ה?אחת[- ]עשרה)\b/;
			($num,$token) = ("12",$1) when /^(ה?שניי?ם[- ]עשר|ה?שתיי?ם[- ]עשרה)\b/;
			($num,$token) = ("13",$1) when /^(ה?שלושה[- ]עשר|ה?שלוש[- ]עשרה)\b/;
			($num,$token) = ("14",$1) when /^(ה?ארבעה[- ]עשר|ה?ארבע[- ]עשרה)\b/;
			($num,$token) = ("15",$1) when /^(ה?חמי?שה[- ]עשר|ה?חמש[- ]עשרה)\b/;
			($num,$token) = ("16",$1) when /^(ה?שי?שה[- ]עשר|ה?שש[- ]עשרה)\b/;
			($num,$token) = ("17",$1) when /^(ה?שבעה[- ]עשר|ה?שבע[- ]עשרה)\b/;
			($num,$token) = ("18",$1) when /^(ה?שמונה[- ]עשרה?)\b/;
			($num,$token) = ("19",$1) when /^(ה?תשעה[- ]עשר|ה?תשע[- ]עשרה)\b/;
			($num,$token) = ("20",$1) when /^(ה?עשרים)\b/;
			($num,$token) = ("$1-2",$1) when /^(\d+[- ]?bis)\b/i;
			($num,$token) = ("$1-3",$1) when /^(\d+[- ]?ter)\b/i;
			($num,$token) = ("$1-4",$1) when /^(\d+[- ]?quater)\b/i;
			($num,$token) = ($1,$1) when /^(\d+(([א-י]|טו|טז|[יכלמנסעפצ][א-ט]?|)\d*|))\b/;
			($num,$token) = ($1,$1) when /^(([א-י]|טו|טז|[יכלמנ][א-ט]?)(\d+[א-י]*|))\b/;
		}
		if ($num ne '') {
			# Remove token from rest of string
			s/^$token//;
			last;
		} else {
			# Fetch next token
			s/^[^ ()|]*[ ()|]+// || s/^.*//;
		}
	}
	
	$num .= "-$1" if (/^[- ]([א-י])\b/);
	$num .= "-$1" if ($num =~ /^\d/ and $token !~ /^\d/ and /^[- ]?(\d[א-י]?)\b/);
	$num =~ s/(?<=\d)-(?=[א-ת])//;
	return $num;
}

sub unquote {
	my $_ = shift;
	s/^ *(.*?) *$/$1/;
	s/^(["'])(.*?)\1$/$2/;
	s/^ *(.*?) *$/$1/;
	return $_;
}

sub unparent {
	my $_ = unquote(shift);
	s/^\((.*?)\)$/$1/;
	s/^\[(.*?)\]$/$1/;
	s/^\{(.*?)\}$/$1/;
	s/^ *(.*?) *$/$1/;
	return $_;
}

sub escape_text {
	my $_ = unquote(shift);
#	print STDERR "|$_|";
	s/&/\&amp;/g;
	s/([(){}"'\[\]<>])/"&#" . ord($1) . ";"/ge;
#	print STDERR "$_|\n";
	return $_;
}

sub unescape_text {
	my $_ = shift;
	my %table = ( 'quote' => '"', 'lt' => '<', 'gt' => '>', 'ndash' => '–', 'nbsp' => ' ', 'apos' => "'", 
		'lrm' => "\x{200E}", 'rlm' => "\x{200F}", 'shy' => '&nil;',
		'deg' => '°', 'plusmn' => '±', 'times' => '×', 'sup1' => '¹', 'sup2' => '²', 'sup3' => '³', 'frac14' => '¼', 'frac12' => '½', 'frac34' => '¾', 'alpha' => 'α', 'beta' => 'β', 'gamma' => 'γ', 'delta' => 'δ', 'epsilon' => 'ε',
	);
	s/&#(\d+);/chr($1)/ge;
	s/(&([a-z]+);)/($table{$2} || $1)/ge;
# 	s/&quote;/"/g;
# 	s/&lt;/</g;
# 	s/&gt;/>/g;
# 	s/&ndash;/–/g;
# 	s/&nbsp;/ /g;
# 	s/&lrm;/\x{200E}/g;
# 	s/&rlm;/\x{200F}/g;
# 	s/&shy;//g;
	s/&nil;//g;
	s/&amp;/&/g;
#	print STDERR "|$_|\n";
	return $_;
}

sub bracket_match {
	my $_ = shift;
	print STDERR "Bracket = $_ -> ";
	tr/([{<>}])/)]}><{[(/;
	print STDERR "$_\n";
	return $_;
}


#---------------------------------------------------------------------

our %glob;
our %hrefs;
our %sections;
our (@line, $idx);

sub linear_parser {
	my $_ = shift;
	
	my @sec_list = (m/<קטע \d (.*?)>/g);
	check_structure(@sec_list);
	# print STDERR "part_type = $glob{part_type}; sect_type = $glob{sect_type}; subs_type = $glob{subs_type};\n";
	
	$glob{context} = '';
	
	@line = split(/(<(?: "[^"]*"|[^>])*>)/, $_);
	$idx = 0;
	for (@line) {
		if (/<(.*)>/) {
			parse_element($1);
		} elsif ($glob{context} eq 'href') {
			$glob{href}{txt} .= $_;
		}
		$idx++;
	}
	
	$line[$_] = "<קישור $hrefs{$_}>" for (keys %hrefs);
	$line[$_] =~ s/<(קטע \d).*?>/<$1 $sections{$_}>/ for (keys %sections);
	
	return join('',@line);
}

sub parse_element {
	my $all = shift;
	my ($element, $params) = split(/ |$/,$all,2);
	
	given ($element) {
		when (/קטע/) {
			my ($level,$name) = split(/ /,$params,2);
			my ($type,$num) = split(/ /,$name || '');
			$num = get_numeral($num) if defined($num);
			given ($type) {
				when (undef) {}
				when (/חלק/) { $glob{part} = $num; $glob{sect} = $glob{subs} = undef; }
				when (/פרק/) { $glob{sect} = $num; $glob{subs} = undef; }
				when (/סימן/) { $glob{subs} = $num; }
				when (/לוחהשוואה/) { $glob{supl} = $glob{part} = $glob{sect} = $glob{subs} = undef; }
				when (/תוספת|נספח/) { $glob{supl} = ($num || ""); $glob{part} = $glob{sect} = $glob{subs} = undef; }
				when (/טופס/) { $glob{form} = ($num || ""); $glob{part} = $glob{sect} = $glob{subs} = undef; }
				when (/לוח/) { $glob{tabl} = ($num || ""); $glob{part} = $glob{sect} = $glob{subs} = undef; }
				when (/טבלה/) { $glob{tabl2} = ($num || ""); $glob{part} = $glob{sect} = $glob{subs} = undef; }
			}
			if (defined $type) {
				$name = "פרק $glob{sect} $name" if ($type eq 'סימן' && defined $glob{sect});
				$name = "חלק $glob{part} $name" if ($type =~ 'סימן|פרק' && $glob{sect_type}==3 && defined $glob{part});
				$name = "תוספת $glob{supl} $name" if ($type ne 'תוספת' && defined $glob{supl});
				$name = "לוח השוואה" if ($type eq 'לוחהשוואה');
				$name =~ s/  / /g;
				$sections{$idx} = $name;
				# print STDERR "GOT section |$type|$num| as |$name| (position is " . current_position() . ")\n" if ($type);
			}
		}
		when (/סעיף/) {
			my $num = get_numeral($params);
			$glob{chap} = $num;
			if ((defined $glob{supl} || defined $glob{tabl}) && $num) {
				my $ankor = "פרט $num";
				$ankor = "לוח $glob{tabl} $ankor" if defined $glob{tabl};
				$ankor = "טבלה $glob{tabl2} $ankor" if defined $glob{tabl2};
				$ankor = "תוספת $glob{supl} $ankor" if defined $glob{supl};
				$ankor =~ s/  / /g;
				$line[$idx] =~ s/סעיף\*?/סעיף*/;
				$line[$idx] .= "<עוגן $ankor>";
			}
		}
		when (/תיאור/) {
			# Split, ignore outmost parenthesis.
			my @inside = split(/(<[^>]*>)/, $all);
			continue if ($#inside<=1);
			$inside[0] =~ s/^/</; $inside[-1] =~ s/$/>/;
			# print STDERR "Spliting: |" . join('|',@inside) . "| (";
			# print STDERR "length $#line -> ";
			splice(@line, $idx, 1, @inside);
			# print STDERR "$#line)\n";
		}
		when (/קישור/) {
			$glob{context} = 'href';
			$glob{href}{helper} = $params || '';
			$glob{href}{txt} = '';
			$glob{href}{idx} = $idx;
			$hrefs{$idx} = '';
			$params = "#" . $idx;
		}
		when ('/' and $glob{context} eq 'href') {
			my $href_idx = $glob{href}{idx};
			$hrefs{$href_idx} = processHREF();
			# print STDERR "GOT href at $href_idx = |$hrefs{$href_idx}|\n";
			$glob{context} = '';
		}
		default {
			# print STDERR "GOT element $element.\n";
		}
	}
	
}


sub insert_TOC {
	# str = "== תוכן ==\n";
	my $str = "<קטע 2> תוכן עניינים\n<סעיף*>\n";
	$str .= "<div style=\"columns: 2 auto; -moz-columns: 2 auto; -webkit-columns: 2 auto; text-align: right; padding-bottom: 1em;\">\n";
	for (sort {$a <=> $b} keys %sections) {
		my ($name, $indent, $text, $next, $style);
		$text = $next = '';
		$name = $sections{$_};
		$indent = $line[$_++];
		$indent = $indent =~ /<קטע (\d)/ ? $1 : 2;
		$text .= $line[$_++] while ($text !~ /\n/ and defined $line[$_]);
		$next .= $line[$_++] while ($next !~ /\n/ and defined $line[$_]);
		if ($next =~ /<הערה>.?<קישור/) {
			$next = '';
			$next .= $line[$_++] while ($next !~ /\n/ and defined $line[$_]);
		}
		next if ($text =~ /__NOTOC__/);
		next if ($indent>3);
		$text =~ s/<(תיקון|אחר).*?> *//g;
		$text =~ s/<קישור.*?>(.*?)<\/>/$1/g;
		$text =~ s/<b>(.*?)<\/b?>/$1/g;
		($text) = ($text =~ /^ *(.*) *$/m);
		if ($next =~ /^<קטע (\d)> *(.*?) *$/m && $1>=$indent) {
			$next =~ s/<(תיקון|אחר).*?> *//g;
			$next =~ s/<קישור.*?>(.*?)<\/>/$1/g;
			$next =~ s/<b>(.*?)<\/b?>/$1/g;
			$next = $2;
			if ($text =~ /^(.*?) *(<הערה>.*<\/>$)/) {
				$text = "$1: $next $2";
			} else {
				$text .= ": $next";
			}
		}
		given ($indent) {
			when ($_==1) { $style = "font-weight: bold; font-size: 120%; padding-top: 3px;"; }
			when ($_==2) { $style = "margin-right: 25px; padding-top: 3px;"; }
			when ($_==3) { $style = "font-size: 90%; margin-right: 50px;"; }
		}
		$style .= " padding-right: 25px; text-indent: -25px;";
		# print STDERR "Visiting section |$_|$indent|$name|$text|\n";
		$str .= "<div style=\"$style\"><קישור 1 $name>$text</></div>\n";
	}
	$str .= "</div>\n";
	return $str;
}


sub current_position {
	my $str = '';
	$str .= " תוספת $glob{supl}" if (defined $glob{supl});
	$str .= " טופס $glob{form}" if (defined $glob{form});
	$str .= " לוח $glob{tabl}" if (defined $glob{tabl});
	$str .= " טבלה $glob{tabl}" if (defined $glob{tabl2});
	$str .= " חלק $glob{part}" if (defined $glob{part});
	$str .= " פרק $glob{sect}" if (defined $glob{sect});
	$str .= " סימן $glob{subs}" if (defined $glob{subs});
	return substr($str,1);
}


sub check_structure {
	my %types;
	$glob{part_type} = $glob{sect_type} = $glob{subs_type} = 0;
	for (@_) {
		if (/תוספת|נספח|טופס|לוח|טבלה/) { last; }
		/^(.*?) (.*?)$/;
		# print STDERR "Got |$1|$2|\n";
		if (++$types{$1}{$2} > 1) {
			if ($1 eq 'פרק') { $glob{sect_type} = 3; }
			if ($1 eq 'סימן') { $glob{subs_type} = 3; }
		} else {
			if ($1 eq 'חלק' and !$glob{part_type}) { $glob{part_type} = 1; }
			if ($1 eq 'פרק' and !$glob{sect_type}) { $glob{sect_type} = 1; }
			if ($1 eq 'סימן' and !$glob{subs_type}) { $glob{subs_type} = 1; }
		}
	}
}

#---------------------------------------------------------------------

sub processHREF {
	
	my $text = $glob{href}{txt};
	my $helper = $glob{href}{helper};
	my $id = $glob{href}{idx};
	
	my ($int,$ext) = findHREF($text);
	my $marker = '';
	my $found = false;
	my $hash = false;
	
	my $type = ($ext) ? 3 : 1;
	
	$ext = '' if ($type == 1);
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^קובץ:|file:|תמונה:|image:/) {
		return "";
	} elsif ($helper =~ /^https?:\/\//) {
		$ext = $helper;
		$int = '';
		$found = true;
	} elsif ($helper =~ /^(.*?)#(.*)/) {
		$type = 3;
		$helper = $1 || $ext;
		# $ext = '' if ($1 ne '');
		$ext = $1;
		($int, undef) = findHREF("+#$2") if ($2);
		$found = true;
		$hash = ($2 eq '');
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($helper =~ /^=\s*(.*)/) {
		$type = 3;
		$helper = $1;
		(undef,$ext) = findHREF($text);
		$glob{href}{marks}{$helper} = $ext;
	} elsif ($helper eq '+' || $ext eq '+') {
		$type = 2;
		($int, $ext) = findHREF("+#$text") unless ($found);
		push @{$glob{href}{ahead}}, $id;
	} elsif ($helper eq '-' || $ext eq '-') {
		$type = 2;
		$ext = $glob{href}{last};
		($int, undef) = findHREF("-#$text") unless ($found);
	} elsif ($helper) {
		if ($found) {
			(undef,$ext) = findHREF($helper);
			$ext = $helper unless ($ext);
		} else {
			($int,$ext) = findHREF($helper);
		}
		$ext = $glob{href}{last} if ($ext eq '-');
		$type = ($ext) ? 3 : 1;
	} else {
	}
	
	# print STDERR "## X |$text| X |$ext|$int| X |$helper|\n";
	
	if ($ext) {
		$ext = $glob{href}{marks}{$ext} if ($glob{href}{marks}{$ext});
		$text = ($int ? "$ext#$int" : $ext);
		
		if ($type==3) {
			$glob{href}{last} = $ext;
			for (@{$glob{href}{ahead}}) {
				$hrefs{$_} =~ s/\+#/$ext#/;
			}
			$glob{href}{ahead} = [];
		}
	} else {
		$text = $int;
	}
	$glob{href}{ditto} = $text;
	
	return "$type $text";
}

sub findHREF {
	my $_ = shift;
	if (!$_) { return $_; }
	
	my $ext = '';
	
	if (/^(w:|http:|https:|קובץ:|file:|תמונה:|image:)/) {
		return ('',$_);
	}
	
	if (/^(.*?)#(.*)$/) {
		$_ = $2;
		$ext = findExtRef($1);
	}
	
	$_ = $glob{href}{ditto} if (/^(אות[וה] ה?(סעיף|תקנה)|[בהלמ]?(סעיף|תקנה) האמורה?)$/);
	
	if (/דברי?[- ]ה?מלך/ and /(סימן|סימנים) \d/) {
		s/(סימן|סימנים)/סעיף/;
	}
	
	s/(\b[לב]?(אותו|אותה)\b) *($extref_sig[- ]*([א-ת]+\b.*)?)$/$4 $2/;
		
	if (/^(.*?)\s*($extref_sig\b[- ]*([א-ת]+\b.*)?)$/) {
		$_ = $1;
		$ext = findExtRef($2);
	}
	
	s/[\(_]/ ( /g;
	s/[\"\']//g;
	s/\bו-//g;
	s/\bאו\b/ /g;
	s/^ *(.*?) *$/$1/;
	s/טבלת השוואה/טבלת_השוואה/;
	
	my $href = $_;
	my @parts = split /[ ,.\-\)]+/;
	my $class = '';
	my ($num, $numstr);
	my %elm = ();
	
	my @matches = ();
	my @pos = ();
	push @pos, $-[0] while (/([^ ,.\-\)]+)/g);
	
	for my $p (@pos) {
		$_ = substr($href,$p);
		$num = undef;
		given ($_) {
			when (/טבלתהשוואה/) { $class = "table"; $num = ""; }
			when (/^ו?ש?[בהל]?(חלק|חלקים)/) { $class = "part"; }
			when (/^ו?ש?[בהל]?(פרק|פרקים)/) { $class = "sect"; }
			when (/^ו?ש?[בהל]?(סימן|סימנים)/) { $class = "subs"; }
			when (/^ו?ש?[בהל]?(תוספת|נספח)/) { $class = "supl"; $num = ""; }
			when (/^ו?ש?[בהל]?(טופס|טפסים)/) { $class = "form"; }
			when (/^ו?ש?[בהל]?(לוח|לוחות)/) { $class = "tabl"; }
			when (/^ו?ש?[בהל]?(טבל[הא]|טבלאות)/) { $class = "tabl2"; }
			when (/^ו?ש?[בהל]?(סעיף|סעיפים|תקנה|תקנות)/) { $class = "chap"; }
			when (/^ו?ש?[בהל]?(פריט|פרט)/) { $class = "supchap"; }
			when (/^ו?ש?[בהל]?(קט[נן]|פי?סקה|פסקאות|משנה|טור)/) { $class = "small"; }
			when ("(") { $class = "small" unless ($class eq "supchap"); }
			when (/^ה?(זה|זו|זאת)/) {
				given ($class) {
					when (/supl|form|tabl|table2/) { $num = $glob{$class} || ''; }
					when (/part|sect|form|chap/) { $num = $glob{$class}; }
					when (/subs/) {
						$elm{subs} = $glob{subs} unless defined $elm{subs};
						$elm{sect} = $glob{sect} unless defined $elm{sect};
					}
				}
				$elm{supl} = $glob{supl} if ($glob{supl} && !defined($elm{supl}));
			}
			default {
				$num = get_numeral($_);
				$class = "chap_" if ($num ne '' && $class eq '');
			}
		}
		# print STDERR "  --> |$_|$class|" . ($num || '') . "|\n";
		
		if (defined($num) && !$elm{$class}) {
			$elm{$class} = $num;
		}
	}
	
	$elm{chap} = $elm{chap_} if (defined $elm{chap_} and !defined $elm{chap});
	
	$href = '';
	if (defined $elm{table}) {
		$href = "טבלת השוואה";
	} elsif (defined $elm{supl}) {
		$elm{supl} = $elm{supl} || $glob{supl} || '' if ($ext eq '');
		$elm{supchap} = $elm{supchap} || $elm{chap};
		$href = "תוספת $elm{supl}";
		$href .= " חלק $elm{part}" if (defined $elm{part});
		$href .= " פרק $elm{sect}" if (defined $elm{sect});
		$href .= " סימן $elm{subs}" if (defined $elm{subs});
		$href .= " טופס $elm{form}" if (defined $elm{form});
		$href .= " לוח $elm{tabl}" if defined $elm{tabl};
		$href .= " טבלה $elm{tabl2}" if defined $elm{tabl2};
		$href .= " פרט $elm{supchap}" if (defined $elm{supchap});
	} elsif (defined $elm{form} || defined $elm{tabl} || defined $elm{tabl2}) {
		$href = "טופס $elm{form}" if defined $elm{form};
		$href = "לוח $elm{tabl}" if defined $elm{tabl};
		$href = "טבלה $elm{tabl2}" if defined $elm{tabl2};
		$href = "$href חלק $elm{part}" if (defined $elm{part});
		$href = "$href פרק $elm{sect}" if (defined $elm{sect});
		$href = "$href סימן $elm{subs}" if (defined $elm{subs});
	} elsif (defined $elm{part}) {
		$href = "חלק $elm{part}";
		$href .= " פרק $elm{sect}" if (defined $elm{sect});
		$href .= " סימן $elm{subs}" if (defined $elm{subs});
	} elsif (defined $elm{sect}) {
		$href = "פרק $elm{sect}";
		$href = "$href סימן $elm{subs}" if (defined $elm{subs});
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && $ext eq '');
		# $href = "תוספת $glob{supl} $href" if ($glob{supl} && $ext eq '');
	} elsif (defined $elm{subs}) {
		$href = "סימן $elm{subs}";
		$href = "פרק $glob{sect} $href" if (defined $glob{sect} && $ext eq '');
		$href = "חלק $glob{part} $href" if ($glob{sect_type}==3 && defined $glob{part} && $ext eq '');
		# $href = "תוספת $glob{supl} $href" if (defined $elm{supl} && $glob{supl} && $ext eq '');
	} elsif (defined $elm{chap}) {
		$href = "סעיף $elm{chap}";
	} elsif (defined $elm{supchap} && $ext eq '') {
		$href = "פרט $elm{supchap}";
		$href = "לוח $glob{tabl} $href" if (defined $glob{tabl});
		$href = "טבלה $glob{tabl2} $href" if (defined $glob{tabl2});
		$href = "תוספת $glob{supl} $href" if (defined $glob{supl});
	} else {
		$href = "";
	}
	
	$href =~ s/  / /g;
	$href =~ s/^ *(.*?) *$/$1/;
	
	# print STDERR "$_ => $elm{$_}; " for (keys %elm);
	# print STDERR "\n";
	# print STDERR "GOT |$href|$ext|\n";
	return ($href,$ext);
}	


sub findExtRef {
	my $_ = shift;
	return $_ if (/^https?:\/\//);
	tr/"'`//;
	s/ *\(נוסח (חדש|משולב)\)//g;
	s/ *\[נוסח (חדש|משולב)\]//g;
#	s/(^[^\,\.]*).*/$1/;
	s/#.*$//;
	s/\.[^\.]*$//;
	s/\, *[^ ]*\d+$//;
	s/ מיום \d+.*$//;
	s/\, *\d+ עד \d+$//;
	s/\[.*?\]//g;
	s/^\s*(.*?)\s*$/$1/;
	
	if (/^$extref_sig(.*)$/) {
		$_ = "$1$2";
		return '' if ($2 =~ /^ *ה?(זאת|זו|זה|אלה|אלו)\b/);
		return '' if ($2 eq "" && !defined $glob{href}{marks}{"$1"});
		return '-' if ($2 =~ /^ *[בלמ]?(האמור|האמורה|האמורות|אותו|אותה|שבו|שבה|ההוא|ההיא)\b/);
	}
	s/\s[-——]+\s/_XX_/g;
	s/_/ /g;
	s/ {2,}/ /g;
	# s/[-]+/ /g;
	s/_XX_/ - /g;
	# s/[ _\:.]+/ /g;
#	print STDERR "$prev -> $_\n";
	return $_;
}
