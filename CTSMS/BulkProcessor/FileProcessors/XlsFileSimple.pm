package CTSMS::BulkProcessor::FileProcessors::XlsFileSimple;
use strict;

## no critic

use Spreadsheet::ParseExcel qw();
use Spreadsheet::ParseExcel::FmtUnicode qw();

use CTSMS::BulkProcessor::Logging qw(
    getlogger
);

use CTSMS::BulkProcessor::LogError qw(
    fileerror
);

use CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor);
our @EXPORT_OK = qw();

my $default_encoding;

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor->new(@_);

    my %params = @_;
    ($self->{encoding}) = @params{qw(
        encoding
    )};

    $self->{encoding} //= $default_encoding;

    bless($self,$class);

    return $self;

}

sub init_reader_context {

    my $self = shift;
    my ($context) = @_;

    #$context->{filename} = $context->{file};

    my $formatter;
    $formatter = Spreadsheet::ParseExcel::FmtUnicode->new(Unicode_Map => $self->{encoding}) if $self->{encoding};
    #    my $Recoder;
    #if ($DestCharset) {
    #$Recoder = Locale::Recode->new(from => $SourceCharset, to => $DestCharset);
    #}

    $context->{parser} = Spreadsheet::ParseExcel->new();
    $context->{workbook} = $context->{parser}->parse($context->{filename},$formatter);
    $context->{sheet} = undef;
    $context->{r} = undef;
    $context->{row_min} = undef;
    $context->{row_max} = undef;
    $context->{col_min} = undef;
    $context->{col_max} = undef;

    if (not defined $context->{workbook}) {
        fileerror('processing file - error reading file ' . $context->{filename} . ': ' . $context->{parser}->error(),getlogger(__PACKAGE__));
    } else {
        if ($context->{sheet_name}) {
            $context->{sheet} = $context->{workbook}->worksheet($context->{sheet_name});
        } else {
            $context->{sheet} = $context->{workbook}->worksheet(0);
        }
        if (not defined $context->{sheet}) {
            fileerror("processing file - invalid spreadsheet '$context->{sheet_name}'",getlogger(__PACKAGE__));
        } else {
            ($context->{row_min},$context->{row_max}) = $context->{sheet}->row_range();
            $context->{r} = $context->{row_min};
            ($context->{col_min},$context->{col_max}) = $context->{sheet}->col_range();
        }
    }

}

sub _next_row {
    my $self = shift;
    my $context = shift;
    my $r = $context->{r};
    if ($r <= $context->{row_max}) {
        my @row = ();
        foreach my $c ($context->{col_min} .. $context->{col_max}) {
            my $cell = $context->{sheet}->get_cell($r,$c);
            push(@row,$cell ? $cell->value() : '');
        }
        $r++;
        return(\@row,$r);
    } else {
        return(undef,$r);
    }
}

sub has_next_row {

    my $self = shift;
    my $context = shift;

    ($context->{row},$context->{r}) = $self->_next_row($context);
    return (defined $context->{row} ? 1 : 0);

}

sub get_row {

    my $self = shift;
    my $context = shift;

    return [ @{$context->{row}} ];

}

1;