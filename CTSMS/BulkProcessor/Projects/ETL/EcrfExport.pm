package CTSMS::BulkProcessor::Projects::ETL::EcrfExport;
use strict;

## no critic
use utf8;

use CTSMS::BulkProcessor::Globals qw(
    $system_name
    $system_version
    $system_instance_label
    $local_fqdn

    $ctsmsrestapi_username
    $ctsmsrestapi_password
);

use CTSMS::BulkProcessor::Projects::ETL::EcrfSettings qw(
    $output_path

    $ecrf_data_trial_id

    $ecrf_data_api_listentries_page_size
    $ecrf_data_api_ecrfs_page_size
    $ecrf_data_api_values_page_size

    $ecrf_data_api_ecrffields_page_size
    $ecrf_data_api_probandlistentrytagvalues_page_size

    %colname_abbreviation
    ecrf_data_include_ecrffield
    $col_per_selection_set_value
    $selection_set_value_separator

    $skip_errors
    $timezone

    $dbtool

    $show_page_progress
    $listentrytag_map_mode

    get_proband_columns
    get_probandlistentry_columns

);
#$ecrf_data_listentrytags
#$ecrf_data_row_block

use CTSMS::BulkProcessor::Projects::ETL::EcrfExporter::Settings qw(
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

use CTSMS::BulkProcessor::Projects::ETL::Job qw(
    update_job
);

use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
    processing_debug
);
use CTSMS::BulkProcessor::LogError qw(
    rowprocessingwarn
    rowprocessingerror
    runerror
);

use CTSMS::BulkProcessor::SqlConnectors::SQLiteDB qw();
use CTSMS::BulkProcessor::SqlConnectors::CSVDB qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job qw(
    $PROCESSING_JOB_STATUS
    $FAILED_JOB_STATUS
    $OK_JOB_STATUS
);

use CTSMS::BulkProcessor::Projects::ETL::Ecrf qw(
    get_ecrf_map
    get_horizontal_cols
    get_probandlistentrytag_map
    get_probandlistentrytag_colname
);

use CTSMS::BulkProcessor::Projects::ETL::EcrfConnectorPool qw(
    get_sqlite_db
    get_csv_db
    destroy_all_dbs
);

use CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataVertical qw();
use CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal qw();

use CTSMS::BulkProcessor::Projects::ETL::ExcelExport qw();

use CTSMS::BulkProcessor::Array qw(array_to_map);

use CTSMS::BulkProcessor::Utils qw(booltostring timestampdigits run shell_args);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    export_ecrf_data_vertical
    export_ecrf_data_horizontal

    publish_ecrf_data_sqlite
    publish_ecrf_data_horizontal_csv
    publish_ecrf_data_xls
    publish_ecrf_data_pdf
    publish_ecrf_data_pdfs

    publish_audit_trail_xls
    publish_ecrf_journal_xls
    publish_ecrfs_xls

    publish_proband_list
);

my $pdfextension = '.pdf';
my $pdfmimetype = 'application/pdf';

my $group_visit_token_separator = ';';

sub publish_ecrf_data_pdf {

    my ($upload_files) = @_;
    my $filename = sprintf($ecrf_data_export_pdf_filename,timestampdigits(), $pdfextension);
    my $outputfile = $output_path . $filename;


    my @dbtoolargs = ($dbtool,
                           '-eep',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    my ($result,$msg) = _run_dbtool(@dbtoolargs);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'PDF/'),
        $outputfile,$filename,$pdfmimetype) : undef),
        $outputfile,$filename,$pdfmimetype) if $result;
    return undef;

}

sub publish_ecrf_data_pdfs {

    my ($upload_files) = @_;
    my $context = { upload_files => $upload_files, };
    my $result = _init_ecrf_data_pdfs_context($context);

    $result = _export_items($context) if $result;

    return ($result,$context->{warning_count},$context->{uploads});

}

sub publish_audit_trail_xls {

    my ($upload_files) = @_;
    my $filename = sprintf($audit_trail_export_xls_filename,timestampdigits(), $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsextension);
    my $outputfile = $output_path . $filename;


    my @dbtoolargs = ($dbtool,
                           '-eat',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    my ($result,$msg) = _run_dbtool(@dbtoolargs);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype) : undef),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype) if $result;
    return undef;

}

sub publish_ecrf_journal_xls {

    my ($upload_files) = @_;
    my $filename = sprintf($ecrf_journal_export_xls_filename,timestampdigits(), $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsextension);
    my $outputfile = $output_path . $filename;


    my @dbtoolargs = ($dbtool,
                           '-eej',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    my ($result,$msg) = _run_dbtool(@dbtoolargs);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype) : undef),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype) if $result;
    return undef;

}

sub publish_ecrfs_xls {

    my ($upload_files) = @_;
    my $filename = sprintf($ecrfs_export_xls_filename,timestampdigits(), $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsextension);
    my $outputfile = $output_path . $filename;


    my @dbtoolargs = ($dbtool,
                           '-ee',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    my ($result,$msg) = _run_dbtool(@dbtoolargs);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype) : undef),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype) if $result;
    return undef;

}

sub publish_proband_list {

    my ($log_level,$upload_files) = @_;
    $log_level //= '';
    my $filename = sprintf($proband_list_filename,(length($log_level) ? lc($log_level) : 'full_subject_list'),timestampdigits(), $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsextension);
    my $outputfile = $output_path . $filename;


    my @dbtoolargs = ($dbtool,
                           '-epl',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    if (length($log_level)) {
        push(@dbtoolargs,'-ll',uc($log_level));
    }
    my ($result,$msg) = _run_dbtool(@dbtoolargs);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,''),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype) : undef),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype) if $result;
    return undef;

}

sub publish_ecrf_data_sqlite {

    my ($upload_files) = @_;
    my $db = &get_sqlite_db();
    my $dbfilename = $db->{dbfilename};
    destroy_all_dbs();

    my $filename = sprintf($ecrf_data_export_sqlite_filename,timestampdigits(), $CTSMS::BulkProcessor::SqlConnectors::SQLiteDB::dbextension);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'SQLite/'),
        $dbfilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::SQLiteDB::mimetype) : undef),
        $dbfilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::SQLiteDB::mimetype);

}

sub publish_ecrf_data_horizontal_csv {

    my ($upload_files) = @_;
    my $db = &get_csv_db();
    my $tablefilename = $db->_gettablefilename(CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal::gettablename());
    destroy_all_dbs();

    my $filename = sprintf($ecrf_data_export_horizontal_csv_filename,timestampdigits(), $CTSMS::BulkProcessor::SqlConnectors::CSVDB::csvextension);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'CSV/'),
        $tablefilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::CSVDB::mimetype) : undef),
        $tablefilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::CSVDB::mimetype);

}

sub publish_ecrf_data_xls {

    my ($upload_files) = @_;
    my @modules = ();
    push(@modules,'CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal');
    push(@modules,'CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataVertical');
    my $filename = sprintf($ecrf_data_export_xls_filename,timestampdigits(), ($ecrf_data_export_xlsx ? $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsxextension : $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsextension));
    my $outputfile = $output_path . $filename;

    my $result = CTSMS::BulkProcessor::Projects::ETL::ExcelExport::write_workbook($outputfile,$ecrf_data_export_xlsx,@modules);
    destroy_all_dbs();

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,($ecrf_data_export_xlsx ? $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsxmimetype : $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype)) : undef),
        $outputfile,$filename,($ecrf_data_export_xlsx ? $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsxmimetype : $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype)) if $result;
    return undef;

}

sub _get_file_in {
    my ($title,$subfolder) = @_;
    $subfolder //= '';
    return {
        "active" => \1,
        "comment" => $system_name . ' ' . $system_version . ' (' . $system_instance_label . ') [' . $local_fqdn . ']',
        "trialId" => $ecrf_data_trial_id,
        "module" => $CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::TRIAL_FILE_MODULE,
        "logicalPath" => $ecrf_data_export_upload_folder  . $subfolder,
        "title" => $title,
    };
}

sub export_ecrf_data_vertical {

    my $context = {};
    my $result = _init_ecrf_data_vertical_context($context);

    # create tables:
    $result = CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataVertical::create_table($ecrf_data_truncate_table,$context->{ecrffieldmaxselectionsetvaluecount},$context->{listentrytag_map}) if $result;

    $result = _export_items($context) if $result;
    undef $context->{db};
    destroy_all_dbs();
    return ($result,$context->{warning_count});

}

sub _export_items {
    my ($context) = @_;
    my $result = 1;

    my @rows = ();
    while (my $item = &{$context->{api_get_items_code}}($context)) {

        my $row = &{$context->{item_to_row_code}}($context,$item);
        push(@rows,$row) if defined $row;
        if ((scalar @rows) >= $context->{items_row_block}) {
            update_job($PROCESSING_JOB_STATUS);
            $result &= &{$context->{export_code}}($context,\@rows);
            @rows = ();
        }

    }

    $result &= &{$context->{export_code}}($context,\@rows);

    return $result;
}

sub _init_ecrf_data_vertical_context {
    my ($context) = @_;

    my $result = 1;
    $context->{ecrf_data_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($ecrf_data_trial_id);
    $context->{listentrytag_map} = get_probandlistentrytag_map($context);

    $context->{ecrffieldmaxselectionsetvaluecount} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_ecrffieldmaxselectionsetvaluecount($context->{ecrf_data_trial}->{id});
    _info($context,"max number of selection set values: $context->{ecrffieldmaxselectionsetvaluecount}",0);

    $context->{error_count} = 0;
    $context->{warning_count} = 0;
    $context->{db} = &get_sqlite_db();

    $context->{api_listentries_page} = [];
    $context->{api_listentries_page_num} = 0;
    $context->{api_listentries_page_total_count} = undef;

    $context->{api_ecrfs_page} = [];
    $context->{api_ecrfs_page_num} = 0;
    $context->{api_ecrfs_page_total_count} = undef;

    $context->{api_values_page} = [];
    $context->{api_values_page_num} = 0;
    $context->{api_values_page_total_count} = undef;

    $context->{ecrf} = undef;
    $context->{visit} = undef;
    $context->{visits} = [];
    $context->{listentry} = undef;
    $context->{ecrf_status} = undef;

    $context->{items_row_block} = $ecrf_data_row_block;
    $context->{item_to_row_code} = \&_ecrf_data_vertical_items_to_row;
    $context->{export_code} = \&_insert_ecrf_data_vertical_rows;
    $context->{api_get_items_code} = sub {
        my ($context) = @_;

NEXT_LISTENTRY:
        if (not defined $context->{api_listentries_page_total_count} or ($context->{api_listentries_page_num} * $ecrf_data_api_listentries_page_size < $context->{api_listentries_page_total_count} and (scalar @{$context->{api_listentries_page}}) == 0)) {
            my $p = { page_size => $ecrf_data_api_listentries_page_size , page_num => $context->{api_listentries_page_num} + 1, total_count => undef };
            my $sf = { sort_by => 'position', sort_dir => 'asc', };

            my $first = $context->{api_listentries_page_num} * $ecrf_data_api_listentries_page_size;
            _info($context,"fetch proband list entries page: " . $first . '-' . ($first + $ecrf_data_api_listentries_page_size) . ' of ' . (defined $context->{api_listentries_page_total_count} ? $context->{api_listentries_page_total_count} : '?'),not $show_page_progress);
            $context->{api_listentries_page} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::get_trial_list($context->{ecrf_data_trial}->{id}, undef, undef, 1, $p, $sf);
            $context->{api_listentries_page_total_count} = $p->{total_count};
            $context->{api_listentries_page_num} += 1;
        }
        if (not defined $context->{listentry}) {
            $context->{listentry} = shift @{$context->{api_listentries_page}};
            if (defined $context->{listentry}) {
                $context->{api_ecrfs_page_total_count} = undef;
                $context->{api_ecrfs_page_num} = 0; #roll over
                #tag values
                ($context->{tagvalues}, my $tag_cols, my $tag_vals) = array_to_map(_get_probandlistentrytagvalues($context),sub { my $item = shift; return get_probandlistentrytag_colname($item->{tag}); },undef,$listentrytag_map_mode);
             } else {
                return undef;
            }
        }

NEXT_ECRF:
        if (not defined $context->{api_ecrfs_page_total_count} or ($context->{api_ecrfs_page_num} * $ecrf_data_api_ecrfs_page_size < $context->{api_ecrfs_page_total_count} and (scalar @{$context->{api_ecrfs_page}}) == 0)) {
            my $p = { page_size => $ecrf_data_api_ecrfs_page_size , page_num => $context->{api_ecrfs_page_num} + 1, total_count => undef };
            my $sf = {};

            my $first = $context->{api_ecrfs_page_num} * $ecrf_data_api_ecrfs_page_size;
            _info($context,"fetch eCRFs page: " . $first . '-' . ($first + $ecrf_data_api_ecrfs_page_size) . ' of ' . (defined $context->{api_ecrfs_page_total_count} ? $context->{api_ecrfs_page_total_count} : '?'),not $show_page_progress);
            $context->{api_ecrfs_page} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf::get_trial_list($context->{ecrf_data_trial}->{id}, 1, $p, $sf);
            $context->{api_ecrfs_page_total_count} = $p->{total_count};
            $context->{api_ecrfs_page_num} += 1;
        }
        if (not defined $context->{ecrf}) {
            $context->{ecrf} = shift @{$context->{api_ecrfs_page}};
            if (defined $context->{ecrf}) {
                my @visits = @{$context->{ecrf}->{visits} // []};
                push(@visits,{ id => undef, }) unless scalar @visits;
                $context->{visits} = \@visits;
                $context->{visit} = undef;
            } else {
                $context->{listentry} = undef;
                $context->{ecrf_status} = undef;
                $context->{visits} = [];
                $context->{visit} = undef;
                goto NEXT_LISTENTRY;
            }
        }

NEXT_VISIT:
        if (not defined $context->{visit}) {
            $context->{visit} = shift @{$context->{visits}};
            if (defined $context->{visit}) {
                $context->{api_values_page_total_count} = undef;
                $context->{api_values_page_num} = 0; #roll over
                $context->{ecrf_status} = eval { CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry::get_item($context->{listentry}->{id},$context->{ecrf}->{id},$context->{visit}->{id}) };
                _info($context,'proband ' . $context->{listentry}->{proband}->alias() . ": eCRF '$context->{ecrf}->{name}" .
                      (defined $context->{visit}->{id} ? '@' . $context->{visit}->{token} : '') . "': " . ($context->{ecrf_status} ? $context->{ecrf_status}->{status}->{name} : '<new>'));
            } else {
                $context->{ecrf} = undef;
                $context->{ecrf_status} = undef;
                goto NEXT_ECRF;
            }
        }

        if (not defined $context->{api_values_page_total_count} or ($context->{api_values_page_num} * $ecrf_data_api_values_page_size < $context->{api_values_page_total_count} and (scalar @{$context->{api_values_page}}) == 0)) {
            my $p = { page_size => $ecrf_data_api_values_page_size , page_num => $context->{api_values_page_num} + 1, total_count => undef };
            my $sf = {}; #sorted by default

            my $first = $context->{api_values_page_num} * $ecrf_data_api_values_page_size;
            _info($context,"fetch eCRF values page: " . $first . '-' . ($first + $ecrf_data_api_values_page_size) . ' of ' . (defined $context->{api_values_page_total_count} ? $context->{api_values_page_total_count} : '?'),not $show_page_progress);
            $context->{api_values_page} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::get_ecrffieldvalues($context->{listentry}->{id},$context->{ecrf}->{id},$context->{visit}->{id},0, $timezone, $p, $sf, { _value => 1, _selectionValueMap => 1 })->{rows};
            $context->{api_values_page_total_count} = $p->{total_count};
            $context->{api_values_page_num} += 1;
        }
        my $value = shift @{$context->{api_values_page}};
        if (defined $value) {
            return $value;
        } else {
            $context->{visit} = undef;
            goto NEXT_VISIT;
        }

    };
    return $result;
}

sub _ecrf_data_vertical_items_to_row {
    my ($context,$item) = @_;
    return undef unless ecrf_data_include_ecrffield($item->{ecrfField});
    my @row = ();
    push(@row,$item->{listEntry}->{proband}->{id});
    push(@row,get_proband_columns($item->{listEntry}->{proband}));

    foreach my $tag_col (keys %{$context->{listentrytag_map}}) {
        push(@row, $context->{tagvalues}->{$tag_col}->{_value});
    }

    push(@row,get_probandlistentry_columns($item->{listentry}));

    push(@row,$context->{ecrf_status} ? $context->{ecrf_status}->{status}->{nameL10nKey} : undef);
    push(@row,$item->{ecrfField}->{ecrf}->{name});
    push(@row,$item->{ecrfField}->{ecrf}->{revision});
    push(@row,$item->{ecrfField}->{ecrf}->{externalId});
    push(@row,$item->{ecrfField}->{ecrf}->{id});
    if (defined $item->{ecrfField}->{ecrf}->{visits} and scalar @{$item->{ecrfField}->{ecrf}->{visits}} > 0) {
        push(@row, join($group_visit_token_separator, map { $_->{token}; } @{$item->{ecrfField}->{ecrf}->{visits}}));
    } else {
        push(@row, undef);
    }
    if (defined $item->{ecrfField}->{ecrf}->{groups} and scalar @{$item->{ecrfField}->{ecrf}->{groups}} > 0) {
        push(@row, join($group_visit_token_separator, map { $_->{token}; } @{$item->{ecrfField}->{ecrf}->{groups}}));
    } else {
        push(@row, undef);
    }
    push(@row,$item->{visit} ? $item->{visit}->{token} : undef);
    push(@row,$item->{ecrfField}->{section});
    push(@row,$item->{ecrfField}->{id});
    push(@row,$item->{ecrfField}->{position});
    push(@row,$item->{ecrfField}->{titleL10nKey});
    push(@row,$item->{ecrfField}->{externalId});
    push(@row,$item->{ecrfField}->{field}->{nameL10nKey});
    push(@row,$item->{ecrfField}->{field}->{titleL10nKey});
    push(@row,$item->{ecrfField}->{field}->{externalId});
    push(@row,$item->{ecrfField}->{field}->{id});
    push(@row,$item->{ecrfField}->{field}->{fieldType}->{nameL10nKey});
    push(@row,booltostring($item->{ecrfField}->{optional}));
    push(@row,booltostring($item->{ecrfField}->{series}));
    push(@row,$item->{index});
    push(@row,join(',',CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_colnames(
        ecrffield => $item->{ecrfField}, visit => $item->{visit}, index => $item->{index},
        col_per_selection_set_value => $col_per_selection_set_value, %colname_abbreviation,
    )));

    push(@row,$item->{version});
    push(@row,$item->{modifiedUser}->{userName});
    push(@row,$item->{modifiedTimestamp});
    if ($item->created and $item->{ecrfField}->{field}->is_select()) {
        push(@row,join($selection_set_value_separator,map { local $_ = $_; $_->{value}; } @{$item->{selectionValues}}));
    } else {
        push(@row,$item->{_value});
    }
    push(@row,booltostring($item->{booleanValue}));
    push(@row,$item->{textValue});
    push(@row,$item->{longValue});
    push(@row,$item->{floatValue});
    push(@row,$item->{dateValue} // $item->{timeValue} // $item->{timestampValue});

    my @selectionSetValues = @{$item->{ecrfField}->{field}->{selectionSetValues} // []};
    foreach my $selectionSetValue (@selectionSetValues) {
        if ($item->created and exists $item->{_selectionValueMap}->{$selectionSetValue->{id}}) {
            push(@row,$item->{_selectionValueMap}->{$selectionSetValue->{id}}->{value});
        } else {
            push(@row,undef);
        }
    }
    for (my $i = scalar @selectionSetValues; $i < $context->{ecrffieldmaxselectionsetvaluecount}; $i++) {
        push(@row,undef);
    }

    return \@row;
}

sub _insert_ecrf_data_vertical_rows {
    my ($context,$ecrf_data_rows) = @_;
    my $result = 1;
    if ((scalar @$ecrf_data_rows) > 0) {
        eval {
            $context->{db}->db_do_begin(CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataVertical::getinsertstatement($ecrf_data_ignore_duplicates));
            $context->{db}->db_do_rowblock($ecrf_data_rows);
            $context->{db}->db_finish();
        };
        my $err = $@;
        if ($err) {
            eval {
                $context->{db}->db_finish(1);
            };
            _warn_or_error($context,$err);
            $result = 0;
        } else {
            _info($context,(scalar @$ecrf_data_rows) . " row(s) exported");
        }
    }
    return $result;
}

sub export_ecrf_data_horizontal {

    my $context = {};
    my $result = _init_ecrf_data_horizontal_context($context);

    # create tables:
    $result = CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal::create_table($ecrf_data_truncate_table,
        [ map { $_->{colname}; } @{$context->{columns}} ],$context->{listentrytag_map}) if $result;

    $result = _export_items($context) if $result;
    undef $context->{db};
    destroy_all_dbs();
    return ($result,$context->{warning_count});

}

sub _init_ecrf_data_pdfs_context {
    my ($context) = @_;

    my $result = 1;
    $context->{ecrf_data_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($ecrf_data_trial_id);
    $context->{listentrytag_map} = get_probandlistentrytag_map($context);

    $context->{error_count} = 0;
    $context->{warning_count} = 0;

    $context->{api_listentries_page} = [];
    $context->{api_listentries_page_num} = 0;
    $context->{api_listentries_page_total_count} = undef;


    $context->{timestamp_digits} = timestampdigits();
    $context->{uploads} = [];
    $context->{items_row_block} = 1;
    $context->{item_to_row_code} = sub {
        my ($context,$lwp_response) = @_;
        _info($context,'proband ' . $context->{listentry}->{proband}->alias() . ' eCRF casebook pdf rendered');
        return $lwp_response;
    };
    $context->{export_code} = sub {
        my ($context,$lwp_response) = @_;
        $lwp_response = $lwp_response->[0] if $lwp_response;

        if ($lwp_response and defined $lwp_response->content_ref) {
            my $filename = sprintf($ecrf_data_export_pdfs_filename,$context->{listentry}->{proband}->{id},$context->{timestamp_digits}, $pdfextension);

            my $out;
            $out = CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'PDF/' . $context->{timestamp_digits} . '/'),
                $lwp_response->content_ref,$filename,$pdfmimetype) if $context->{upload_files};
            if ($out) {
                push(@{$context->{uploads}}, [ $out,undef,$filename,$pdfmimetype ] );
                return 1;
            } else {
                return not $context->{upload_files};
            }
        }
        return 0;
    };
    $context->{api_get_items_code} = sub {
        my ($context) = @_;

        if ((scalar @{$context->{api_listentries_page}}) == 0) {
            my $p = { page_size => $ecrf_data_api_listentries_page_size , page_num => $context->{api_listentries_page_num} + 1, total_count => undef };
            my $sf = { sort_by => 'position', sort_dir => 'asc', };

            my $first = $context->{api_listentries_page_num} * $ecrf_data_api_listentries_page_size;
            _info($context,"fetch proband list entries page: " . $first . '-' . ($first + $ecrf_data_api_listentries_page_size) . ' of ' . (defined $context->{api_listentries_page_total_count} ? $context->{api_listentries_page_total_count} : '?'),not $show_page_progress);
            $context->{api_listentries_page} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::get_trial_list($context->{ecrf_data_trial}->{id}, undef, undef, 1, $p, $sf);
            $context->{api_listentries_page_total_count} = $p->{total_count};
            $context->{api_listentries_page_num} += 1;
        }
        $context->{listentry} = shift @{$context->{api_listentries_page}};
        if (defined $context->{listentry}) {
            #tag values
            ($context->{tagvalues}, my $tag_cols, my $tag_vals) = array_to_map(_get_probandlistentrytagvalues($context),sub { my $item = shift; return get_probandlistentrytag_colname($item->{tag}); },undef,$listentrytag_map_mode);
            return CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry::render_ecrf($context->{listentry}->{id}, undef, undef);
        }
        return undef;

    };
    return $result;
}

sub _init_ecrf_data_horizontal_context {
    my ($context) = @_;

    my $result = 1;
    $context->{ecrf_data_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($ecrf_data_trial_id);
    $context->{listentrytag_map} = get_probandlistentrytag_map($context);

    $context->{ecrf_map} = get_ecrf_map($context,0);
    $context->{columns} = get_horizontal_cols($context, undef);

    $context->{error_count} = 0;
    $context->{warning_count} = 0;
    $context->{db} = &get_csv_db();

    $context->{api_listentries_page} = [];
    $context->{api_listentries_page_num} = 0;
    $context->{api_listentries_page_total_count} = undef;

    $context->{items_row_block} = 1;
    $context->{item_to_row_code} = \&_ecrf_data_horizontal_items_to_row;
    $context->{export_code} = \&_insert_ecrf_data_horizontal_rows;
    $context->{api_get_items_code} = sub {
        my ($context) = @_;

        if ((scalar @{$context->{api_listentries_page}}) == 0) {
            my $p = { page_size => $ecrf_data_api_listentries_page_size , page_num => $context->{api_listentries_page_num} + 1, total_count => undef };
            my $sf = { sort_by => 'position', sort_dir => 'asc', };

            my $first = $context->{api_listentries_page_num} * $ecrf_data_api_listentries_page_size;
            _info($context,"fetch proband list entries page: " . $first . '-' . ($first + $ecrf_data_api_listentries_page_size) . ' of ' . (defined $context->{api_listentries_page_total_count} ? $context->{api_listentries_page_total_count} : '?'),not $show_page_progress);
            $context->{api_listentries_page} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::get_trial_list($context->{ecrf_data_trial}->{id}, undef, undef, 1, $p, $sf);
            $context->{api_listentries_page_total_count} = $p->{total_count};
            $context->{api_listentries_page_num} += 1;
        }
        $context->{listentry} = shift @{$context->{api_listentries_page}};
        if (defined $context->{listentry}) {
            #return [] unless $context->{listentry}->{proband}->{id} == id;
            #tag values
            ($context->{tagvalues}, my $tag_cols, my $tag_vals) = array_to_map(_get_probandlistentrytagvalues($context),sub { my $item = shift; return get_probandlistentrytag_colname($item->{tag}); },undef,$listentrytag_map_mode);
            return _get_ecrffieldvalues($context);
        }
        return undef;

    };
    return $result;
}

sub _ecrf_data_horizontal_items_to_row {
    my ($context,$items) = @_;

    my @row = ();
    push(@row,$context->{listentry}->{proband}->{id});
    push(@row,get_proband_columns($context->{listentry}->{proband}));
    foreach my $tag_col (keys %{$context->{listentrytag_map}}) {
        push(@row, $context->{tagvalues}->{$tag_col}->{_value});
    }

    push(@row,get_probandlistentry_columns($context->{listentry}));

    my %value_map = ();
    foreach my $item (@$items) {
        if ($item->{ecrfField}->{field}->is_select()) {
            if ($col_per_selection_set_value) {
                if ($item->created) {
                    foreach my $colname (CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_colnames(
                            ecrffield => $item->{ecrfField}, visit => $item->{visit}, index => $item->{index},
                            selectionValues => $item->{selectionValues},
                            col_per_selection_set_value => 1,
                            %colname_abbreviation,)) {
                        $value_map{$colname} = booltostring(1);
                    }
                    foreach my $colname (CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_colnames(
                            ecrffield => $item->{ecrfField}, visit => $item->{visit}, index => $item->{index},
                            col_per_selection_set_value => 1,
                            %colname_abbreviation,)) {
                        $value_map{$colname} = booltostring(0) if not exists $value_map{$colname};
                    }
                } else {
                    foreach my $colname (CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_colnames(
                            ecrffield => $item->{ecrfField}, visit => $item->{visit}, index => $item->{index},
                            col_per_selection_set_value => 1,
                            %colname_abbreviation,)) {
                        $value_map{$colname} = undef;
                    }
                }
            } else {
                my ($colname) = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_colnames(
                    ecrffield => $item->{ecrfField}, visit => $item->{visit}, index => $item->{index},
                    selectionValues => $item->{selectionValues},
                    col_per_selection_set_value => 0,
                    %colname_abbreviation,);
                if ($item->created) {
                    $value_map{$colname} = join($selection_set_value_separator,map { local $_ = $_; $_->{value}; } @{$item->{selectionValues}});
                } else {
                    $value_map{$colname} = $item->{_value};
                }
            }
        } else {
            my ($colname) = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_colnames(
                ecrffield => $item->{ecrfField}, visit => $item->{visit}, index => $item->{index},
                %colname_abbreviation,);
            $value_map{$colname} = $item->{_value};
        }
    }

    foreach my $colname (map { $_->{colname}; } @{$context->{columns}}) {
        push(@row,(exists $value_map{$colname} ? $value_map{$colname} : undef));
    }

    return \@row;
}


sub _insert_ecrf_data_horizontal_rows {
    my ($context,$ecrf_data_rows) = @_;
    my $result = 1;
    if ((scalar @$ecrf_data_rows) > 0) {
        eval {
            $context->{db}->db_do_begin(CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal::getinsertstatement($ecrf_data_ignore_duplicates));
            $context->{db}->db_do_rowblock($ecrf_data_rows);
            $context->{db}->db_finish();
        };
        my $err = $@;
        if ($err) {
            eval {
                $context->{db}->db_finish(1);
            };
            _warn_or_error($context,$err);
            $result = 0;
        } else {
            _info($context,(scalar @$ecrf_data_rows) . " row(s) exported");
        }
    }
    return $result;
}

sub _get_probandlistentrytagvalues {
    my ($context,$all) = @_;
    my $api_listentrytagvalues_page = [];
    my $api_listentrytagvalues_page_num = 0;
    my $api_listentrytagvalues_page_total_count;
    my @listentrytagvalues;
    while (1) {
        if ((scalar @$api_listentrytagvalues_page) == 0) {
            my $p = { page_size => $ecrf_data_api_probandlistentrytagvalues_page_size , page_num => $api_listentrytagvalues_page_num + 1, total_count => undef };
            my $sf = {}; #sorted by default

            my $first = $api_listentrytagvalues_page_num * $ecrf_data_api_probandlistentrytagvalues_page_size;
            _info($context,"fetch proband list attribute values page: " . $first . '-' . ($first + $ecrf_data_api_probandlistentrytagvalues_page_size) . ' of ' . (defined $api_listentrytagvalues_page_total_count ? $api_listentrytagvalues_page_total_count : '?'),not $show_page_progress);
            $api_listentrytagvalues_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues::get_probandlistentrytagvalues($context->{listentry}->{id}, 0, 0, $timezone, $p, $sf, { _value => 1 })->{rows};
            $api_listentrytagvalues_page_total_count = $p->{total_count};
            $api_listentrytagvalues_page_num += 1;
        }
        my $listentrytagvalue = shift @$api_listentrytagvalues_page;
        last unless $listentrytagvalue;
        push(@listentrytagvalues,$listentrytagvalue) if ($all or $listentrytagvalue->{tag}->{ecrfValue});
    }
    return \@listentrytagvalues;
}

sub _get_ecrffieldvalues {
    my ($context) = @_;
    my @values;
    foreach my $ecrfid (keys %{$context->{ecrf_map}}) {
        $context->{ecrf} = $context->{ecrf_map}->{$ecrfid}->{ecrf};
        my @visits = @{$context->{ecrf}->{visits} // []};
        push(@visits,{ id => undef, }) unless scalar @visits;
        foreach my $visit (@visits) {
            my $api_values_page = [];
            my $api_values_page_num = 0;
            my $api_values_page_total_count;
            if ($visit->{id}) {
                $context->{visit} = $visit;
            } else {
                $context->{visit} = undef;
            }
            $context->{ecrf_status} = eval { CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry::get_item($context->{listentry}->{id},$ecrfid,$visit->{id}) };
            _info($context,'proband ' . $context->{listentry}->{proband}->alias() . ": eCRF '$context->{ecrf}->{name}" .
                  (defined $visit->{id} ? '@' . $visit->{token} : '') . "': " . ($context->{ecrf_status} ? $context->{ecrf_status}->{status}->{name} : '<new>'));
            while (1) {
                if ((scalar @$api_values_page) == 0) {
                    my $p = { page_size => $ecrf_data_api_values_page_size , page_num => $api_values_page_num + 1, total_count => undef };
                    my $sf = {}; #sorted by default

                    my $first = $api_values_page_num * $ecrf_data_api_values_page_size;
                    _info($context,"fetch eCRF values page: " . $first . '-' . ($first + $ecrf_data_api_values_page_size) . ' of ' . (defined $api_values_page_total_count ? $api_values_page_total_count : '?'),not $show_page_progress);
                    $api_values_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::get_ecrffieldvalues($context->{listentry}->{id},$ecrfid,$visit->{id},0, $timezone, $p, $sf, { _value => 1, _selectionValueMap => 1 })->{rows};
                    $api_values_page_total_count = $p->{total_count};
                    $api_values_page_num += 1;
                }
                my $value = shift @$api_values_page;
                last unless $value;
                push(@values,$value);
            }
        }
    }
    return \@values;
}

sub _run_dbtool {
    runerror('dbtool not defined',getlogger(__PACKAGE__)) unless $dbtool;
    runerror('dbtool not found/executable',getlogger(__PACKAGE__)) unless -X $dbtool;
    my ($result,$msg) = run(shell_args(@_)); #suppress output, to hide password
    runerror("$dbtool failed",getlogger(__PACKAGE__)) unless $result;
    _info(undef,"$dbtool executed");
    return ($result,$msg);
}

sub _warn_or_error {
    my ($context,$message) = @_;
    if ($skip_errors) {
        _warn($context,$message);
    } else {
        _error($context,$message);
    }
}

sub _error {

    my ($context,$message) = @_;
    $context->{error_count} = $context->{error_count} + 1;
    rowprocessingerror(undef,$message,getlogger(__PACKAGE__));

}

sub _warn {

    my ($context,$message) = @_;
    $context->{warning_count} = $context->{warning_count} + 1;
    rowprocessingwarn(undef,$message,getlogger(__PACKAGE__));

}

sub _info {

    my ($context,$message,$debug) = @_;
    if ($debug) {
        processing_debug(undef,$message,getlogger(__PACKAGE__));
    } else {
        processing_info(undef,$message,getlogger(__PACKAGE__));
    }
}

1;
