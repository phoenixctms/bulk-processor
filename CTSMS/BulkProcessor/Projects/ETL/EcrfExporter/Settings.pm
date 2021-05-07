package CTSMS::BulkProcessor::Projects::ETL::EcrfExporter::Settings;
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

#use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings

    $defaultsettings
    $defaultconfig

    $force

    $ecrf_data_truncate_table
    $ecrf_data_ignore_duplicates

    $ecrf_data_export_upload_folder
    $ecrf_data_export_sqlite_filename
    $ecrf_data_export_horizontal_csv_filename
    $ecrf_data_export_xls_filename
    $ecrf_data_export_xlsx

    $audit_trail_export_xls_filename
    $ecrf_journal_export_xls_filename
    $ecrfs_export_xls_filename

    $ecrf_data_export_pdf_filename
    $ecrf_data_export_pdfs_filename

    $proband_list_filename
    $ecrf_data_row_block
);

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $force = 0;

our $ecrf_data_truncate_table = 1;
our $ecrf_data_ignore_duplicates = 0;

our $ecrf_data_export_upload_folder = '';
our $ecrf_data_export_sqlite_filename = '%s%s';
our $ecrf_data_export_horizontal_csv_filename = '%s%s';
our $ecrf_data_export_xls_filename = '%s%s';
our $ecrf_data_export_xlsx = 0;

our $audit_trail_export_xls_filename = "%s%s";
our $ecrf_journal_export_xls_filename = "%s%s";
our $ecrfs_export_xls_filename = "%s%s";

our $ecrf_data_export_pdf_filename = '%s%s';
our $ecrf_data_export_pdfs_filename = '%s_%s%s';

our $proband_list_filename = '%s_%s%s';

our $ecrf_data_row_block = 100;

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;

        $ecrf_data_truncate_table = $data->{ecrf_data_truncate_table} if exists $data->{ecrf_data_truncate_table};
        $ecrf_data_ignore_duplicates = $data->{ecrf_data_ignore_duplicates} if exists $data->{ecrf_data_ignore_duplicates};

        $ecrf_data_export_upload_folder = $data->{ecrf_data_export_upload_folder} if exists $data->{ecrf_data_export_upload_folder};

        $ecrf_data_export_sqlite_filename = $data->{ecrf_data_export_sqlite_filename} if exists $data->{ecrf_data_export_sqlite_filename};
        $ecrf_data_export_horizontal_csv_filename = $data->{ecrf_data_export_horizontal_csv_filename} if exists $data->{ecrf_data_export_horizontal_csv_filename};
        $ecrf_data_export_xls_filename = $data->{ecrf_data_export_xls_filename} if exists $data->{ecrf_data_export_xls_filename};
        $ecrf_data_export_xlsx = $data->{ecrf_data_export_xlsx} if exists $data->{ecrf_data_export_xlsx};

        $ecrf_data_export_pdf_filename = $data->{ecrf_data_export_pdf_filename} if exists $data->{ecrf_data_export_pdf_filename};
        $ecrf_data_export_pdfs_filename = $data->{ecrf_data_export_pdfs_filename} if exists $data->{ecrf_data_export_pdfs_filename};

        $proband_list_filename = $data->{proband_list_filename} if exists $data->{proband_list_filename};

        $audit_trail_export_xls_filename = $data->{audit_trail_export_xls_filename} if exists $data->{audit_trail_export_xls_filename};
        $ecrf_journal_export_xls_filename = $data->{ecrf_journal_export_xls_filename} if exists $data->{ecrf_journal_export_xls_filename};
        $ecrfs_export_xls_filename = $data->{ecrfs_export_xls_filename} if exists $data->{ecrfs_export_xls_filename};

        $ecrf_data_row_block = $data->{ecrf_data_row_block} if exists $data->{ecrf_data_row_block};

        return $result;

    }
    return 0;

}

1;
