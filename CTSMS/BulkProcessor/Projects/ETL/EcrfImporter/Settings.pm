package CTSMS::BulkProcessor::Projects::ETL::EcrfImporter::Settings;
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
#use CTSMS::BulkProcessor::Array qw(contains);
use CTSMS::BulkProcessor::Utils qw(format_number prompt chopstring);

#use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings

    $defaultsettings
    $defaultconfig

    $force

    $ecrf_import_filename
    $import_ecrf_data_horizontal_multithreading
    $import_ecrf_data_horizontal_numofthreads
    $import_ecrf_data_horizontal_blocksize




    $append_selection_set_values
    $update_listentrytag_values
    $clear_sections
    $clear_all_sections

    $ecrf_values_col_block
    $listentrytag_values_col_block
    
    $ecrf_name_column_name
    $ecrf_visit_column_name
    
    get_ecrf_columns

);
#$ecrf_department_nameL10nKey
#$ecrf_proband_alias_format
#$ecrf_proband_alias_column_index

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $force = 0;

our $ecrf_import_filename;
#our $ecrf_proband_alias_format = '%03d';

our $import_ecrf_data_horizontal_multithreading = 1;
our $import_ecrf_data_horizontal_numofthreads = $cpucount;

#our $ecrf_proband_alias_column_index = 0;
our $import_ecrf_data_horizontal_blocksize = 5;
our $update_listentrytag_values = 0;
our $ecrf_values_col_block = 1; # save one ecrf value after the other
our $listentrytag_values_col_block = 0; # save all proband list attributes at once
#our $ecrf_subject_gender = undef;
#our $ecrf_department_nameL10nKey = undef;
our $clear_sections;
our $clear_all_sections;
our $append_selection_set_values;

our $ecrf_name_column_name = 'ecrf';
our $ecrf_visit_column_name = 'visit';

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;

        $force = $data->{force} if exists $data->{force};

        $ecrf_import_filename = $data->{ecrf_import_filename} if exists $data->{ecrf_import_filename};
        #$ecrf_proband_alias_format = $data->{ecrf_proband_alias_format} if exists $data->{ecrf_proband_alias_format};

        $import_ecrf_data_horizontal_multithreading = $data->{import_ecrf_data_horizontal_multithreading} if exists $data->{import_ecrf_data_horizontal_multithreading};
        $import_ecrf_data_horizontal_numofthreads = _get_numofthreads($cpucount,$data,'import_ecrf_data_horizontal_numofthreads');
        $import_ecrf_data_horizontal_blocksize = $data->{import_ecrf_data_horizontal_blocksize} if exists $data->{import_ecrf_data_horizontal_blocksize};

        #$ecrf_subject_gender = $data->{ecrf_subject_gender} if exists $data->{ecrf_subject_gender};
        #$ecrf_department_nameL10nKey = $data->{ecrf_department_nameL10nKey} if exists $data->{ecrf_department_nameL10nKey};
        $clear_sections = $data->{clear_sections} if exists $data->{clear_sections};
        $clear_all_sections = $data->{clear_all_sections} if exists $data->{clear_all_sections};
        #check_clear_sections(sub {
        #    my $msg = shift;
        #    configurationinfo($configfile,$msg,getlogger(__PACKAGE__));
        #}, sub {
        #    my $msg = shift;
        #    configurationerror($configfile,$msg,getlogger(__PACKAGE__));
        #});
        $append_selection_set_values = $data->{append_selection_set_values} if exists $data->{append_selection_set_values};
        $update_listentrytag_values = $data->{update_listentrytag_values} if exists $data->{update_listentrytag_values};

        $ecrf_values_col_block = $data->{ecrf_values_col_block} if exists $data->{ecrf_values_col_block};
        $listentrytag_values_col_block = $data->{listentrytag_values_col_block} if exists $data->{listentrytag_values_col_block};
        
        $ecrf_name_column_name = $data->{ecrf_name_column_name} if exists $data->{ecrf_name_column_name};
        $ecrf_visit_column_name = $data->{ecrf_visit_column_name} if exists $data->{ecrf_visit_column_name};

        return $result;

    }
    return 0;

}

sub get_ecrf_columns {
    my @columns = ();
    push(@columns,lc($ecrf_name_column_name)) if length($ecrf_name_column_name);
    push(@columns,lc($ecrf_visit_column_name)) if length($ecrf_visit_column_name);
    return @columns;
}

sub _get_numofthreads {
    my ($default_value,$data,$key) = @_;
    my $numofthreads = $default_value;
    $numofthreads = $data->{$key} if exists $data->{$key};
    $numofthreads = $cpucount if $numofthreads > $cpucount;
    return $numofthreads;
}

1;
