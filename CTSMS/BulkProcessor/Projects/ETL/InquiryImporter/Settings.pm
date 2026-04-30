package CTSMS::BulkProcessor::Projects::ETL::InquiryImporter::Settings;
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


require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings

    $defaultsettings
    $defaultconfig

    $force

    $inquiry_import_filename
    $import_inquiry_data_horizontal_multithreading
    $import_inquiry_data_horizontal_numofthreads
    $import_inquiry_data_horizontal_blocksize

    $append_selection_set_values
    $update_listentrytag_values
    $clear_categories
    $clear_all_categories

    $inquiry_values_col_block
    
);

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $force = 0;

our $inquiry_import_filename;

our $import_inquiry_data_horizontal_multithreading = 1;
our $import_inquiry_data_horizontal_numofthreads = $cpucount;

our $import_inquiry_data_horizontal_blocksize = 5;
our $update_listentrytag_values = 0;
our $inquiry_values_col_block = 1; # save one inquiry value after the other
our $clear_categories;
our $clear_all_categories;
our $append_selection_set_values;

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;

        $force = $data->{force} if exists $data->{force};

        $inquiry_import_filename = $data->{inquiry_import_filename} if exists $data->{inquiry_import_filename};

        $import_inquiry_data_horizontal_multithreading = $data->{import_inquiry_data_horizontal_multithreading} if exists $data->{import_inquiry_data_horizontal_multithreading};
        $import_inquiry_data_horizontal_numofthreads = _get_numofthreads($cpucount,$data,'import_inquiry_data_horizontal_numofthreads');
        $import_inquiry_data_horizontal_blocksize = $data->{import_inquiry_data_horizontal_blocksize} if exists $data->{import_inquiry_data_horizontal_blocksize};

        $clear_categories = $data->{clear_categories} if exists $data->{clear_categories};
        $clear_all_categories = $data->{clear_all_categories} if exists $data->{clear_all_categories};

        $append_selection_set_values = $data->{append_selection_set_values} if exists $data->{append_selection_set_values};
        $update_listentrytag_values = $data->{update_listentrytag_values} if exists $data->{update_listentrytag_values};

        $inquiry_values_col_block = $data->{inquiry_values_col_block} if exists $data->{inquiry_values_col_block};
        
        return $result;

    }
    return 0;

}

sub _get_numofthreads {
    my ($default_value,$data,$key) = @_;
    my $numofthreads = $default_value;
    $numofthreads = $data->{$key} if exists $data->{$key};
    $numofthreads = $cpucount if $numofthreads > $cpucount;
    return $numofthreads;
}

1;
