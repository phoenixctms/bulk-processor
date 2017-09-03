package CTSMS::BulkProcessor::Projects::Render::GnuPlot;
use strict;

## no critic

use CTSMS::BulkProcessor::Logging qw (
    getlogger
    runinfo
    rundebug
);
use CTSMS::BulkProcessor::LogError qw(
    runerror
);

use CTSMS::BulkProcessor::Utils qw(run);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    plot
    convert
);

my $magick = 'magick';

# Try to find the executable of Gnuplot
my $gnuplot = 'gnuplot';
if ($^O =~ /MSWin/) {
    my $gnuplotDir = 'C:\Program Files\gnuplot';
    $gnuplotDir = 'C:\Program Files (x86)\gnuplot' if (!-e $gnuplotDir);

    my $binDir = $gnuplotDir.'\bin';
    $binDir = $gnuplotDir.'\binary' if (!-e $binDir);

    $gnuplot = $binDir.'\gnuplot.exe';
    if (!-e $gnuplot) {
        $gnuplot = $binDir.'\wgnuplot.exe';
    }
}

# Call Gnuplot to generate the image file
sub plot {

    my ($script,$terminal) = @_;
    
    if ($^O =~ /MSWin/ and !-e $gnuplot) {
        runerror("gnuplot command not found.",getlogger(__PACKAGE__)); 
    }
    
    my @args = ($script);
    if ($terminal =~ /^(ggi|pm|windows|wxt|x11)(\s|$)/) {
        push(@args,'-');
    }
    
    my ($result,$msg) = run($gnuplot,@args);
    if ($result) {
        runinfo($msg,getlogger(__PACKAGE__));
    } else {
        runerror($msg,getlogger(__PACKAGE__));
    }
    

}

sub convert {
    
    my ($inputfile, $outputfile, $rotate, $dpi, $dimension) = @_;
    
    my @args = ();
    if ($dpi > 0) {
        push(@args,'-density');
        push(@args,$dpi);
    }
    push(@args,$inputfile);
    if ($dimension) {
        push(@args,'-resize');
        push(@args,$dimension);
    }
    if ($rotate) {
        #push(@args,'-rotate 90');
        push(@args,'-rotate');
        push(@args,$rotate);        
    }    
    push(@args,'-quality');
    push(@args,'100%');   
    #push(@args,'-colorspace');
    #push(@args,'RGB');       
    push(@args,$outputfile);
    
    my ($result,$msg) = run($magick,@args);
    if ($result) {
        runinfo($msg,getlogger(__PACKAGE__));
    } else {
        runerror($msg,getlogger(__PACKAGE__));
    }

}

1;