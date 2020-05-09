use strict;

## no critic

use File::Basename;
use Cwd;
use lib Cwd::abs_path(File::Basename::dirname(__FILE__) . '/../../../../');

use Getopt::Long qw(GetOptions);

use CTSMS::BulkProcessor::Globals qw();

use File::Find qw();

use CTSMS::BulkProcessor::Utils qw(fixdirpath run);

my $yuicompressor_jar = fixdirpath(Cwd::abs_path(File::Basename::dirname(__FILE__))) . 'yuicompressor-2.4.7.jar';

my @fileextensions = ('.js','.css');
my $rfileextensions = join('|',map { quotemeta($_) . '$'; } @fileextensions);
my $minified_suffix = '.min';
my $minified_pattern = quotemeta($minified_suffix) . '$';
my $root;
my %dirsdone;
my @dirstoskip = ();
my $cleanup = 0;

if (init()) {
    main();
    exit(0);
} else {
    exit(1);
}

sub init {

    return 0 unless GetOptions(
        "folder=s" => \$root,
        "skip=s" => \@dirstoskip,
        "cleanup" => \$cleanup,
    );

    die("no folder specified\n") unless $root;

    $root = fixdirpath($root);
    @dirstoskip = map { $root . fixdirpath($_); } @dirstoskip;

    return 1;

}

sub main {

    File::Find::find({ wanted => sub {
        _scandirs(sub {
            my $dir = shift;
            _scandirfiles($dir,sub {
                my ($filename,$filedir,$suffix) = @_;
                unless ($filename =~ /$minified_pattern/) {
                    my $input_file = $filedir.$filename . $suffix;

                    my $output_file = $filedir. $filename . $minified_suffix . $suffix;

                    if (-e $output_file) {
                        unlink $output_file;
                        if ($cleanup) {
                            print $filename . $minified_suffix . $suffix . " removed\n";
                        }
                    }
                    unless ($cleanup) {
                        my @args = (
                            'java',
                            '-jar',
                            $yuicompressor_jar,



                            $input_file,
                            '-o',
                            $output_file,
                        );
                        my ($result,$msg) = run(@args);
                        if ($result) {
                            print $filename . $suffix . ' -> ' . $filename . $minified_suffix . $suffix . "\n";
                        } else {
                            die();
                        }
                    }
                }
            });
        });
    }, follow => 1 }, $root);

}

sub _scandirs {

    my ($scandirfiles_code) = @_;
    my $path = $File::Find::dir;
    if (-d $path) {
        my $dir = $path . '/';
        if (not $dirsdone{$dir}
            and not scalar grep { substr($dir, 0, length($_)) eq $_; } @dirstoskip) {
            &$scandirfiles_code($dir);
        }
        $dirsdone{$dir} = 1;
    }
}

sub _scandirfiles {

    my ($inputdir,$code) = @_;

    local *DIR;
    if (not opendir(DIR, $inputdir)) {
        die('cannot opendir ' . $inputdir . ': ' . $!);
    }
    my @files = grep { /$rfileextensions$/ && -f $inputdir . $_} readdir(DIR);
    closedir DIR;
    return unless (scalar @files) > 0;
    foreach my $file (@files) {
        my $inputfilepath = $inputdir . $file;
        my ($inputfilename,$inputfiledir,$inputfilesuffix) = File::Basename::fileparse($inputfilepath, $rfileextensions);
        &$code($inputfilename,$inputfiledir,$inputfilesuffix);
    }

}
