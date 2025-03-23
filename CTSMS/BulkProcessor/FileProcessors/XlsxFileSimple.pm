package CTSMS::BulkProcessor::FileProcessors::XlsxFileSimple;
use strict;

## no critic

use Excel::Reader::XLSX qw();

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    processing_info
);

use CTSMS::BulkProcessor::LogError qw(
    fileerror
);

use CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor);
our @EXPORT_OK = qw();

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor->new(@_);

    #$self->{custom_formats} = shift;

    bless($self,$class);

    return $self;

}

sub init_reader_context {

    my $self = shift;
    my ($context) = @_;

    #$context->{filename} = $context->{file};

    $context->{parser} = Excel::Reader::XLSX->new();
    $context->{workbook} = $context->{parser}->read_file($context->{filename});
    $context->{sheet} = undef;

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
            processing_info($context->{tid},"spreadsheet '" . $context->{sheet}->name() . "'",getlogger(__PACKAGE__));
        }
    }

}

sub has_next_row {

    my $self = shift;
    my $context = shift;

    $context->{row} = $context->{sheet}->next_row();
    return (defined $context->{row} ? 1 : 0);

}

sub get_row {

    my $self = shift;
    my $context = shift;

    return [ $context->{row}->values() ];

}

sub get_sheet_names {

    my $self = shift;
    my $file = shift;

    my $parser = Excel::Reader::XLSX->new();
    return map { $_->name() ; } $parser->read_file($file)->worksheets();
    
}

1;