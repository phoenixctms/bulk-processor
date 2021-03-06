package CTSMS::BulkProcessor::Projects::ETL::InquiryExporter::Settings;
use strict;

## no critic

use utf8;

use CTSMS::BulkProcessor::Globals qw(
    $enablemultithreading
    $cpucount
);


use CTSMS::BulkProcessor::Logging qw(
    getlogger
    scriptinfo
    configurationinfo
);

use CTSMS::BulkProcessor::LogError qw(
    fileerror
    configurationwarn
    configurationerror
);

use CTSMS::BulkProcessor::LoadConfig qw(
    split_tuple
    parse_regexp
);
use CTSMS::BulkProcessor::Utils qw(format_number prompt chopstring);


use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings

    $defaultsettings
    $defaultconfig

    $force

    $inquiry_data_row_block
);

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $force = 0;

our $inquiry_data_row_block = 100;

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;

        $inquiry_data_row_block = $data->{inquiry_data_row_block} if exists $data->{inquiry_data_row_block};


        return $result;

    }
    return 0;

}

1;
