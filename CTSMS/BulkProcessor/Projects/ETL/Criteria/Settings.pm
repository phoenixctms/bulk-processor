package CTSMS::BulkProcessor::Projects::ETL::Criteria::Settings;
use strict;

## no critic

use utf8;

use CTSMS::BulkProcessor::Globals qw(
    $working_path
    $enablemultithreading
    $cpucount
    create_path

);
#$ctsmsrestapi_path

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

#use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings
    check_dry

    $defaultsettings
    $defaultconfig

    $input_path
    $output_path

    $skip_errors
    $force
    $dry

    $export_criteria_page_size
    $criteria_export_xlsx_filename
    $criteria_import_xlsx_filename

);

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $input_path = $working_path . 'input/';
our $output_path = $working_path . 'output/';

our $skip_errors = 0;

our $force = 0;
our $dry = 0;

our $export_criteria_page_size = 100;
our $criteria_export_xlsx_filename = '%s%s';
our $criteria_import_xlsx_filename = undef;

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) { # and defined ($data = $data->[0])) {

        my $result = 1;

        $result &= _prepare_working_paths(1);

        $skip_errors = $data->{skip_errors} if exists $data->{skip_errors};

        $export_criteria_page_size = $data->{export_criteria_page_size} if exists $data->{export_criteria_page_size};
        $criteria_export_xlsx_filename = $data->{criteria_export_xlsx_filename} if exists $data->{criteria_export_xlsx_filename};
        $criteria_import_xlsx_filename = $data->{criteria_import_xlsx_filename} if exists $data->{criteria_import_xlsx_filename};

        return $result;

    }
    return 0;

}

sub _prepare_working_paths {

    my ($create) = @_;
    my $result = 1;
    my $path_result;

    ($path_result,$input_path) = create_path($working_path . 'input',$input_path,$create,\&fileerror,getlogger(__PACKAGE__));
    $result &= $path_result;
    ($path_result,$output_path) = create_path($working_path . 'output',$output_path,$create,\&fileerror,getlogger(__PACKAGE__));
    $result &= $path_result;
    #($path_result,$rollback_path) = create_path($working_path . 'rollback',$rollback_path,$create,\&fileerror,getlogger(__PACKAGE__));
    #$result &= $path_result;

    return $result;

}

sub check_dry {

    if ($dry) {
        scriptinfo('running in dry mode (readonly)',getlogger(__PACKAGE__));
        return 1;
    } else {
        scriptinfo('NO DRY MODE - RECORDS WILL BE MODIFIED!',getlogger(__PACKAGE__));
        if (!$force) {
            if ('yes' eq lc(prompt("Type 'yes' to proceed: "))) {
                return 1;
            } else {
                return 0;
            }
        } else {
            scriptinfo('force option applied',getlogger(__PACKAGE__));
            return 1;
        }
    }

}

1;
