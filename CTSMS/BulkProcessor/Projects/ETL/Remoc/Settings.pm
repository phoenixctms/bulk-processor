package CTSMS::BulkProcessor::Projects::ETL::Remoc::Settings;
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
use CTSMS::BulkProcessor::Utils qw(format_number prompt chopstring); #check_ipnet

#use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings

    $defaultsettings
    $defaultconfig

    $force

    $dialysis_substitution_volume_ignore_duplicates
    $dialysis_substitution_volume_truncate_table
    $dialysis_substitution_volume_header_row
    $dialysis_substitution_volume_sheet_name
    $dialysis_substitution_volume_row_block
    $dialysis_substitution_volume_custom_formats
    $dialysis_substitution_volume_file
    $dialysis_substitution_volume_file_pattern
    $dialysis_substitution_volume_api_file_page_size
    
    $dialysis_substitution_volume_ecrf_id
    $dialysis_substitution_volume_clear_ecrf
    $dialysis_substitution_volume_probandlistentrytag_id
    $dialysis_substitution_volume_ecrffield_externalid_pattern
    $dialysis_substitution_volume_mapping
    
);

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $force = 0;

our $dialysis_substitution_volume_ignore_duplicates = 0;
our $dialysis_substitution_volume_truncate_table = 1;
our $dialysis_substitution_volume_header_row = undef;
our $dialysis_substitution_volume_sheet_name = undef;
our $dialysis_substitution_volume_row_block = 100;
our $dialysis_substitution_volume_custom_formats = undef;
our $dialysis_substitution_volume_file = undef; #$input_path;
our $dialysis_substitution_volume_file_pattern = undef;
our $dialysis_substitution_volume_api_file_page_size = 10;

our $dialysis_substitution_volume_ecrf_id = undef;
our $dialysis_substitution_volume_clear_ecrf = 0;
our $dialysis_substitution_volume_probandlistentrytag_id = undef;
our $dialysis_substitution_volume_ecrffield_externalid_pattern = undef;

our $dialysis_substitution_volume_mapping = {};

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data and defined ($data = $data->[0])) {

        my $result = 1;
        #my $regexp_result;
        #&$configurationinfocode("testinfomessage",$configlogger);


        $dialysis_substitution_volume_ignore_duplicates = $data->{dialysis_substitution_volume_ignore_duplicates} if exists $data->{dialysis_substitution_volume_ignore_duplicates};
        $dialysis_substitution_volume_truncate_table = $data->{dialysis_substitution_volume_truncate_table} if exists $data->{dialysis_substitution_volume_truncate_table};
        $dialysis_substitution_volume_header_row = $data->{dialysis_substitution_volume_header_row} if exists $data->{dialysis_substitution_volume_header_row};
        $dialysis_substitution_volume_sheet_name = $data->{dialysis_substitution_volume_sheet_name} if exists $data->{dialysis_substitution_volume_sheet_name};
        $dialysis_substitution_volume_row_block = $data->{dialysis_substitution_volume_row_block} if exists $data->{dialysis_substitution_volume_row_block};
        $dialysis_substitution_volume_custom_formats = $data->{dialysis_substitution_volume_custom_formats} if exists $data->{dialysis_substitution_volume_custom_formats};
        $dialysis_substitution_volume_file_pattern = $data->{dialysis_substitution_volume_file_pattern} if exists $data->{dialysis_substitution_volume_file_pattern};
        #($regexp_result,$dialysis_substitution_volume_file_pattern) = parse_regexp($dialysis_substitution_volume_file_pattern,$configfile);
        #$result &= $regexp_result;
        $dialysis_substitution_volume_file = $data->{dialysis_substitution_volume_file} if exists $data->{dialysis_substitution_volume_file};
        $dialysis_substitution_volume_api_file_page_size = $data->{dialysis_substitution_volume_api_file_page_size} if exists $data->{dialysis_substitution_volume_api_file_page_size};

        $dialysis_substitution_volume_ecrf_id = $data->{dialysis_substitution_volume_ecrf_id} if exists $data->{dialysis_substitution_volume_ecrf_id};
        #$dialysis_substitution_volume_ecrf = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf::get_item($dialysis_substitution_volume_ecrf_id);
        #configurationerror($configfile,"error loading eCRF",getlogger(__PACKAGE__)) unless defined $dialysis_substitution_volume_ecrf;
        $dialysis_substitution_volume_clear_ecrf = $data->{dialysis_substitution_volume_clear_ecrf} if exists $data->{dialysis_substitution_volume_clear_ecrf};
        
        $dialysis_substitution_volume_probandlistentrytag_id = $data->{dialysis_substitution_volume_probandlistentrytag_id} if exists $data->{dialysis_substitution_volume_probandlistentrytag_id};
        $dialysis_substitution_volume_ecrffield_externalid_pattern = $data->{dialysis_substitution_volume_ecrffield_externalid_pattern} if exists $data->{dialysis_substitution_volume_ecrffield_externalid_pattern};
        if (not defined $dialysis_substitution_volume_ecrffield_externalid_pattern or length($dialysis_substitution_volume_ecrffield_externalid_pattern) == 0) {
            $dialysis_substitution_volume_ecrffield_externalid_pattern = '_%';
        }
        $dialysis_substitution_volume_mapping = $data->{dialysis_substitution_volume_mapping} if exists $data->{dialysis_substitution_volume_mapping};
        $dialysis_substitution_volume_mapping //= {};
        
        return $result;

    }
    return 0;

}

1;
