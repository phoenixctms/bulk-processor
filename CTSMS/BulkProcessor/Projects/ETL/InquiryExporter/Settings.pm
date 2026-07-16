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
use CTSMS::BulkProcessor::Utils qw(format_number prompt chopstring stringtobool);

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings

    $defaultsettings
    $defaultconfig

    $force

    $inquiry_data_row_block
    
    $inquiry_data_truncate_table
    $inquiry_data_ignore_duplicates
    
    $inquiry_data_export_upload_folder
    $inquiry_data_export_sqlite_filename
    $inquiry_data_export_horizontal_csv_filename
    $inquiry_data_export_xls_filename
    $inquiry_data_export_xlsx

    $inquiry_data_export_pdfs_filename
    
    $publish_public_file

);

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $force = 0;

our $inquiry_data_truncate_table = 1;
our $inquiry_data_ignore_duplicates = 0;

our $inquiry_data_export_upload_folder = '';
our $inquiry_data_export_sqlite_filename = '%s%s';
our $inquiry_data_export_horizontal_csv_filename = '%s%s';
our $inquiry_data_export_xls_filename = '%s%s';
our $inquiry_data_export_xlsx = 0;

our $inquiry_data_export_pdfs_filename = '%s_%s%s';

our $publish_public_file = 0;

our $inquiry_data_row_block = 100;

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;

        $inquiry_data_truncate_table = $data->{inquiry_data_truncate_table} if exists $data->{inquiry_data_truncate_table};
        $inquiry_data_ignore_duplicates = $data->{inquiry_data_ignore_duplicates} if exists $data->{inquiry_data_ignore_duplicates};
        
        $inquiry_data_export_upload_folder = $data->{inquiry_data_export_upload_folder} if exists $data->{inquiry_data_export_upload_folder};

        $inquiry_data_export_sqlite_filename = $data->{inquiry_data_export_sqlite_filename} if exists $data->{inquiry_data_export_sqlite_filename};
        $inquiry_data_export_horizontal_csv_filename = $data->{inquiry_data_export_horizontal_csv_filename} if exists $data->{inquiry_data_export_horizontal_csv_filename};
        $inquiry_data_export_xls_filename = $data->{inquiry_data_export_xls_filename} if exists $data->{inquiry_data_export_xls_filename};
        $inquiry_data_export_xlsx = $data->{inquiry_data_export_xlsx} if exists $data->{inquiry_data_export_xlsx};

        $inquiry_data_export_pdfs_filename = $data->{inquiry_data_export_pdfs_filename} if exists $data->{inquiry_data_export_pdfs_filename};        
        
        $inquiry_data_row_block = $data->{inquiry_data_row_block} if exists $data->{inquiry_data_row_block};
        
        $publish_public_file = stringtobool($data->{publish_public_file}) if exists $data->{publish_public_file};        
        
        return $result;

    }
    return 0;

}

1;
