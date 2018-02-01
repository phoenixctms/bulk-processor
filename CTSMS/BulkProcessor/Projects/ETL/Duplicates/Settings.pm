package CTSMS::BulkProcessor::Projects::ETL::Duplicates::Settings;
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
    $sqlite_db_file

    $skip_errors
    $force
    $dry

    $proband_plain_text_ignore_duplicates
    $proband_plain_text_truncate_table
    $person_name_prefix_length
    $import_proband_page_size
    $import_proband_multithreading
    $import_proband_numofthreads

    $proband_duplicate_truncate_table
    $create_duplicate_multithreading
    $create_duplicate_numofthreads

    $update_proband_multithreading
    $update_proband_numofthreads
    $duplicate_proband_category
    $duplicate_comment_prefix
    $proband_categories_not_to_update

);
    #$proband_plain_text_row_block
    #$import_proband_api_page_size

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $input_path = $working_path . 'input/';
our $output_path = $working_path . 'output/';
#our $rollback_path = $working_path . 'rollback/';
our $sqlite_db_file = 'dubplicates';

our $skip_errors = 0;

our $force = 0;
our $dry = 0;

our $proband_plain_text_ignore_duplicates = 0;
our $proband_plain_text_truncate_table = 1;
#our $proband_plain_text_row_block = 100;
#our $import_proband_api_page_size = 10;
our $person_name_prefix_length = 2;
our $import_proband_page_size = 100;
our $import_proband_multithreading = $enablemultithreading;
our $import_proband_numofthreads = $cpucount;

our $proband_duplicate_truncate_table = 1;
our $create_duplicate_multithreading = $enablemultithreading;
our $create_duplicate_numofthreads = $cpucount;

our $update_proband_multithreading = $enablemultithreading;
our $update_proband_numofthreads = $cpucount;
our $duplicate_proband_category = 'duplicate';
our $duplicate_comment_prefix = 'this subject has duplicates: ';
our $proband_categories_not_to_update = [];

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data and defined ($data = $data->[0])) {

        my $result = 1;

        $result &= _prepare_working_paths(1);
        #$dialysis_substitution_volume_file = $input_path;

        $sqlite_db_file = $data->{sqlite_db_file} if exists $data->{sqlite_db_file};

        $skip_errors = $data->{skip_errors} if exists $data->{skip_errors};

        $proband_plain_text_ignore_duplicates = $data->{proband_plain_text_ignore_duplicates} if exists $data->{proband_plain_text_ignore_duplicates};
        $proband_plain_text_truncate_table = $data->{proband_plain_text_truncate_table} if exists $data->{proband_plain_text_truncate_table};
        #$proband_plain_text_row_block = $data->{proband_plain_text_row_block} if exists $data->{proband_plain_text_row_block};
        #$import_proband_api_page_size = $data->{import_proband_api_page_size} if exists $data->{import_proband_api_page_size};
        $person_name_prefix_length = $data->{person_name_prefix_length} if exists $data->{person_name_prefix_length};
        $import_proband_page_size = $data->{import_proband_page_size} if exists $data->{import_proband_page_size};
        $import_proband_multithreading = $data->{import_proband_multithreading} if exists $data->{import_proband_multithreading};
        $import_proband_numofthreads = _get_numofthreads($cpucount,$data,'import_proband_numofthreads');

        $proband_duplicate_truncate_table = $data->{proband_duplicate_truncate_table} if exists $data->{proband_duplicate_truncate_table};
        $create_duplicate_multithreading = $data->{create_duplicate_multithreading} if exists $data->{create_duplicate_multithreading};
        $create_duplicate_numofthreads = _get_numofthreads($cpucount,$data,'create_duplicate_numofthreads');

        $update_proband_multithreading = $data->{update_proband_multithreading} if exists $data->{update_proband_multithreading};
        $update_proband_numofthreads = _get_numofthreads($cpucount,$data,'update_proband_numofthreads');
        $duplicate_proband_category = $data->{duplicate_proband_category} if exists $data->{duplicate_proband_category};
        $duplicate_comment_prefix = $data->{duplicate_comment_prefix} if exists $data->{duplicate_comment_prefix};
        $proband_categories_not_to_update = $data->{proband_categories_not_to_update} if exists $data->{proband_categories_not_to_update};
        $proband_categories_not_to_update = [ $proband_categories_not_to_update ] unless ref $proband_categories_not_to_update;

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

sub _get_numofthreads {
    my ($default_value,$data,$key) = @_;
    my $numofthreads = $default_value;
    $numofthreads = $data->{$key} if exists $data->{$key};
    $numofthreads = $cpucount if $numofthreads > $cpucount;
    return $numofthreads;
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
