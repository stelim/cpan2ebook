#!/usr/bin/perl

use strict;
use warnings;

use LWP::Simple;
use Archive::Extract;
use DBI;
use YAML::Tiny;
 
my $yaml = YAML::Tiny->new;
$yaml = YAML::Tiny->read( 'config.yml' );
my $tmp_path = $yaml->[0]->{tmp_dir};

$| = 1;
 
my $db_file  = 'cpan_names.db';
my $source   = '02packages.details.txt.gz';
my $dir      = $tmp_path;
my $filename = "$dir/$source";

print "Downloading '$source' from CPAN to '$dir'...";
my $status = getstore(                                               # fetch
             "http://www.cpan.org/modules/02packages.details.txt.gz",# from
             $filename                                               # to
             );
print "DONE\n";
 
unless ( is_success($status) ) {
    print "FAIL\t$status\n";
    exit 1;
}

print 'Extracting archive...';
my $ae = Archive::Extract->new( archive => $filename );
my $ok = $ae->extract( to => $dir );

unless ($ok) {
    print "FAIL\n";
    exit 1;
}
print "DONE\n";

my $db = DBI->connect("dbi:SQLite:$db_file", "", "",
    {RaiseError => 1, AutoCommit => 1});

unless (-e $db_file) {
    print "No DB found. Creating new DB with table in '$db_file'...";
    $db->do("CREATE TABLE names (
                                 module  VARCHAR(200),
                                 release VARCHAR(100)
                                )"
           );
    print "DONE\n";
}

print 'Dumping DB into hash...';
my $res = $db->selectall_arrayref(
                        "SELECT module, release FROM names");
my %stored = ();
foreach my $row (@$res) {
    my ($module, $release) = @$row;
    $stored{"$module-$release"} = 1;
}
print "DONE\n";

print 'Updating DB...';
my $inserted = 0;
my $skipped  = 0;
my $nomatch  = 0;
my $nomatch_txt  = '';
open (my $f, "$dir/02packages.details.txt");
while (<$f>) {
    if ($_ =~ m%
                ^
                ([\w:]+)
                \s+
                [\w\d\.]+
                \s+
                \w{1}\/\w{2}\/\w+\/
                ([\w\d\-\.]+)
                \.(tar\.gz|tgz|zip)
              %x
       ) {
        my $module  = $1;
        my $release = $2;
        if ($release =~ m/(.*)-[\w\d\.]+/) {
            $release = $1;
        }
        #else {
            #print "ERROR: $release\n";
        #}

#print $_;
#print "$module\t$release\n";
#next;
        if ($stored{"$module-$release"}) {
            $skipped++;
            next;
        }
        else {
            $db->do("INSERT INTO names
                        VALUES ('$module', '$release')"
                   );
            $inserted++;
        }
    }
    else {
        $nomatch++;
        $nomatch_txt .= $_;
    }
}
close ($f); 
$db->disconnect;
print "DONE\n";

$| = 0;
print "Inserted: $inserted, Skipped: $skipped, Not matched: $nomatch\n";
print "The following lines did not match the criteria for data:\n";
print "--------------------------------------------------------\n";
print $nomatch_txt;

exit 0;

