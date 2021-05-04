package CTSMS::BulkProcessor::FileProcessors::CSVFileSimple;
use strict;

## no critic

use CTSMS::BulkProcessor::Logging qw(
    getlogger
);

use CTSMS::BulkProcessor::FileProcessor;

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::FileProcessor);
our @EXPORT_OK = qw();

my $default_lineseparator = '\\n\\r|\\r|\\n';
my $default_fieldseparator = ",";
my $default_encoding = 'UTF-8';

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::FileProcessor->new(@_);

    my %params = @_;
    ($self->{encoding},
    $self->{line_separator},
    $self->{field_separator}) = @params{qw(
        encoding
        line_separator
        field_separator
    )};

    $self->{encoding} //= $default_encoding;
    $self->{line_separator} //= $default_lineseparator;
    $self->{field_separator} //= $default_fieldseparator;

    bless($self,$class);

    return $self;

}

sub extractfields {
    my ($context,$line_ref) = @_;
    my $separator = $context->{instance}->{field_separator};
    my @fields = split(/$separator/,$$line_ref,-1);
    return \@fields;
}

1;
