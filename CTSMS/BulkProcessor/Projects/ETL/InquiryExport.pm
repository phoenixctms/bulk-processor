package CTSMS::BulkProcessor::Projects::ETL::InquiryExport;
use strict;

## no critic

use Tie::IxHash;

use CTSMS::BulkProcessor::Globals qw(
    $system_name
    $system_version
    $system_instance_label
    $local_fqdn

    $ctsmsrestapi_username
    $ctsmsrestapi_password
);

use CTSMS::BulkProcessor::Projects::ETL::InquirySettings qw(
    $output_path

    $active
    $active_signup

    $inquiry_data_truncate_table
    $inquiry_data_ignore_duplicates
    $inquiry_data_trial_id

    $inquiry_data_api_probands_page_size
    $inquiry_data_api_inquiries_page_size
    $inquiry_data_api_values_page_size

    %colname_abbreviation
    inquiry_data_include_inquiry
    $col_per_selection_set_value
    $selection_set_value_separator

    $inquiry_data_export_upload_folder
    $inquiry_data_export_sqlite_filename
    $inquiry_data_export_horizontal_csv_filename
    $inquiry_data_export_xls_filename
    $inquiry_data_export_xlsx

    $inquiry_data_export_pdfs_filename

    $skip_errors

    get_proband_columns
    update_job
);

use CTSMS::BulkProcessor::Projects::ETL::InquiryExporter::Settings qw(
    $inquiry_data_row_block
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
);

use CTSMS::BulkProcessor::SqlConnectors::SQLiteDB qw();
use CTSMS::BulkProcessor::SqlConnectors::CSVDB qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job qw(
    $PROCESSING_JOB_STATUS
    $FAILED_JOB_STATUS
    $OK_JOB_STATUS
);

use CTSMS::BulkProcessor::Projects::ETL::InquiryConnectorPool qw(
    get_sqlite_db
    get_csv_db
    destroy_all_dbs
);

use CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataVertical qw();
use CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataHorizontal qw();

use CTSMS::BulkProcessor::Projects::ETL::ExcelExport qw();

use CTSMS::BulkProcessor::Array qw(array_to_map);

use CTSMS::BulkProcessor::Utils qw(booltostring timestampdigits );

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    export_inquiry_data_vertical
    export_inquiry_data_horizontal

    publish_inquiry_data_sqlite
    publish_inquiry_data_horizontal_csv
    publish_inquiry_data_xls
    publish_inquiry_data_pdfs
);

my $show_page_progress = 0;
my $max_colname_length_warn = 64;

my $pdfextension = '.pdf';
my $pdfmimetype = 'application/pdf';

sub publish_inquiry_data_pdfs {

    my ($upload_files) = @_;
    my $context = { upload_files => $upload_files, };
    my $result = _init_inquiry_data_pdfs_context($context);

    $result = _export_items($context) if $result;

    return ($result,$context->{warning_count},$context->{uploads});

}

sub publish_inquiry_data_sqlite {

    my ($upload_files) = @_;
    my $db = &get_sqlite_db();
    my $dbfilename = $db->{dbfilename};
    destroy_all_dbs();

    my $filename = sprintf($inquiry_data_export_sqlite_filename,timestampdigits(), $CTSMS::BulkProcessor::SqlConnectors::SQLiteDB::dbextension);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'SQLite/'),
        $dbfilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::SQLiteDB::mimetype) : undef),
        $dbfilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::SQLiteDB::mimetype);

}

sub publish_inquiry_data_horizontal_csv {

    my ($upload_files) = @_;
    my $db = &get_csv_db();
    my $tablefilename = $db->_gettablefilename(CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataHorizontal::gettablename());
    destroy_all_dbs();

    my $filename = sprintf($inquiry_data_export_horizontal_csv_filename,timestampdigits(), $CTSMS::BulkProcessor::SqlConnectors::CSVDB::csvextension);

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'CSV/'),
        $tablefilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::CSVDB::mimetype) : undef),
        $tablefilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::CSVDB::mimetype);

}

sub publish_inquiry_data_xls {

    my ($upload_files) = @_;
    my @modules = ();
    push(@modules,'CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataHorizontal');
    push(@modules,'CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataVertical');
    my $filename = sprintf($inquiry_data_export_xls_filename,timestampdigits(), ($inquiry_data_export_xlsx ? $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsxextension : $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsextension));
    my $outputfile = $output_path . $filename;

    my $result = CTSMS::BulkProcessor::Projects::ETL::ExcelExport::write_workbook($outputfile,$inquiry_data_export_xlsx,@modules);
    destroy_all_dbs();

    return (($upload_files ? CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,($inquiry_data_export_xlsx ? $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsxmimetype : $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype)) : undef),
        $outputfile,$filename,($inquiry_data_export_xlsx ? $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsxmimetype : $CTSMS::BulkProcessor::Projects::ETL::ExcelExport::xlsmimetype)) if $result;
    return undef;

}

sub _get_file_in {
    my ($title,$subfolder) = @_;
    $subfolder //= '';
    return {
        "active" => \1,
        "comment" => $system_name . ' ' . $system_version . ' (' . $system_instance_label . ') [' . $local_fqdn . ']',
        "trialId" => $inquiry_data_trial_id,
        "module" => $CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::TRIAL_FILE_MODULE,
        "logicalPath" => $inquiry_data_export_upload_folder  . $subfolder,
        "title" => $title,
    };
}

sub export_inquiry_data_vertical {

    my $context = {};
    my $result = _init_inquiry_data_vertical_context($context);

    # create tables:
    $result = CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataVertical::create_table($inquiry_data_truncate_table,$context->{inquirymaxselectionsetvaluecount}) if $result;

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

sub _init_inquiry_data_vertical_context {
    my ($context) = @_;

    my $result = 1;
    $context->{inquiry_data_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($inquiry_data_trial_id);

    $context->{inquirymaxselectionsetvaluecount} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_inquirymaxselectionsetvaluecount($context->{inquiry_data_trial}->{id});
    _info($context,"max number of selection set values: $context->{inquirymaxselectionsetvaluecount}",0);

    $context->{error_count} = 0;
    $context->{warning_count} = 0;
    $context->{db} = &get_sqlite_db();

    $context->{api_probands_page} = [];
    $context->{api_probands_page_num} = 0;
    $context->{api_probands_page_total_count} = undef;

    $context->{api_values_page} = [];
    $context->{api_values_page_num} = 0;
    $context->{api_values_page_total_count} = undef;

    $context->{proband} = undef;

    $context->{items_row_block} = $inquiry_data_row_block;
    $context->{item_to_row_code} = \&_inquiry_data_vertical_items_to_row;
    $context->{export_code} = \&_insert_inquiry_data_vertical_rows;
    $context->{api_get_items_code} = sub {
        my ($context) = @_;

NEXT_PROBAND:
        if (not defined $context->{api_probands_page_total_count} or ($context->{api_probands_page_num} * $inquiry_data_api_probands_page_size < $context->{api_probands_page_total_count} and (scalar @{$context->{api_probands_page}}) == 0)) {
            my $p = { page_size => $inquiry_data_api_probands_page_size, page_num => $context->{api_probands_page_num} + 1, total_count => undef };
            my $sf = { sort_by => 'id', sort_dir => 'asc', };

            my $first = $context->{api_probands_page_num} * $inquiry_data_api_probands_page_size;
            _info($context,"fetch probands page: " . $first . '-' . ($first + $inquiry_data_api_probands_page_size) . ' of ' . (defined $context->{api_probands_page_total_count} ? $context->{api_probands_page_total_count} : '?'),not $show_page_progress);
            $context->{api_probands_page} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::get_inquiry_proband_list($context->{inquiry_data_trial}->{id}, $active, $active_signup, $p, $sf);
            $context->{api_probands_page_total_count} = $p->{total_count};
            $context->{api_probands_page_num} += 1;
        }
        if (not defined $context->{proband}) {
            $context->{proband} = shift @{$context->{api_probands_page}};
            if (defined $context->{proband}) {
                $context->{api_values_page_total_count} = undef;
                $context->{api_values_page_num} = 0; #roll over
             } else {
                return undef;
            }
        }

        if (not defined $context->{api_values_page_total_count} or ($context->{api_values_page_num} * $inquiry_data_api_values_page_size < $context->{api_values_page_total_count} and (scalar @{$context->{api_values_page}}) == 0)) {
            my $p = { page_size => $inquiry_data_api_values_page_size , page_num => $context->{api_values_page_num} + 1, total_count => undef };
            my $sf = {}; #sorted by default

            my $first = $context->{api_values_page_num} * $inquiry_data_api_values_page_size;
            _info($context,"fetch inquiry values page: " . $first . '-' . ($first + $inquiry_data_api_values_page_size) . ' of ' . (defined $context->{api_values_page_total_count} ? $context->{api_values_page_total_count} : '?'),not $show_page_progress);
            $context->{api_values_page} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::get_inquiryvalues($context->{proband}->{id},$context->{inquiry_data_trial}->{id},$active,$active_signup,1,0, $p, $sf, { _value => 1, _selectionValueMap => 1 })->{rows};
            $context->{api_values_page_total_count} = $p->{total_count};
            $context->{api_values_page_num} += 1;
        }
        my $value = shift @{$context->{api_values_page}};
        if (defined $value) {
            return $value;
        } else {
            $context->{proband} = undef;
            goto NEXT_PROBAND;
        }

    };
    return $result;
}

sub _inquiry_data_vertical_items_to_row {
    my ($context,$item) = @_;
    return undef unless inquiry_data_include_inquiry($item->{inquiry});
    my @row = ();
    push(@row,$item->{proband}->{id});
    push(@row,get_proband_columns($item->{proband}));

    push(@row,$item->{inquiry}->{category});
    push(@row,$item->{inquiry}->{id});
    push(@row,$item->{inquiry}->{position});
    push(@row,$item->{inquiry}->{titleL10nKey});
    push(@row,$item->{inquiry}->{externalId});
    push(@row,$item->{inquiry}->{field}->{nameL10nKey});
    push(@row,$item->{inquiry}->{field}->{titleL10nKey});
    push(@row,$item->{inquiry}->{field}->{externalId});
    push(@row,$item->{inquiry}->{field}->{id});
    push(@row,$item->{inquiry}->{field}->{fieldType}->{nameL10nKey});
    push(@row,booltostring($item->{inquiry}->{optional}));

    push(@row,join(',',CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_colnames(
        inquiry => $item->{inquiry},

        col_per_selection_set_value => $col_per_selection_set_value,
        %colname_abbreviation,
    )));

    push(@row,$item->{version});
    push(@row,$item->{modifiedUser}->{userName});
    push(@row,$item->{modifiedTimestamp});
    if ($item->{inquiry}->{field}->is_select()) {
        push(@row,join($selection_set_value_separator,map { local $_ = $_; $_->{value}; } @{$item->{selectionValues}}));
    } else {
        push(@row,$item->{_value});
    }
    push(@row,booltostring($item->{booleanValue}));
    push(@row,$item->{textValue});
    push(@row,$item->{longValue});
    push(@row,$item->{floatValue});
    push(@row,$item->{dateValue} // $item->{timeValue} // $item->{timestampValue});

    my @selectionSetValues = @{$item->{inquiry}->{field}->{selectionSetValues} // []};
    foreach my $selectionSetValue (@selectionSetValues) {
        if (exists $item->{_selectionValueMap}->{$selectionSetValue->{id}}) {
            push(@row,$item->{_selectionValueMap}->{$selectionSetValue->{id}}->{value});
        } else {
            push(@row,undef);
        }
    }
    for (my $i = scalar @selectionSetValues; $i < $context->{inquirymaxselectionsetvaluecount}; $i++) {
        push(@row,undef);
    }

    return \@row;
}

sub _insert_inquiry_data_vertical_rows {
    my ($context,$inquiry_data_rows) = @_;
    my $result = 1;
    if ((scalar @$inquiry_data_rows) > 0) {
        eval {
            $context->{db}->db_do_begin(CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataVertical::getinsertstatement($inquiry_data_ignore_duplicates));
            $context->{db}->db_do_rowblock($inquiry_data_rows);
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
            _info($context,(scalar @$inquiry_data_rows) . " row(s) exported");
        }
    }
    return $result;
}

sub export_inquiry_data_horizontal {

    my $context = {};
    my $result = _init_inquiry_data_horizontal_context($context);

    # create tables:
    $result = CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataHorizontal::create_table($inquiry_data_truncate_table,$context->{columns}) if $result;


    $result = _export_items($context) if $result;
    undef $context->{db};
    destroy_all_dbs();
    return ($result,$context->{warning_count});

}

sub _init_inquiry_data_pdfs_context {
    my ($context) = @_;

    my $result = 1;
    $context->{inquiry_data_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($inquiry_data_trial_id);

    $context->{error_count} = 0;
    $context->{warning_count} = 0;

    $context->{api_probands_page} = [];
    $context->{api_probands_page_num} = 0;
    $context->{api_probands_page_total_count} = undef;

    $context->{timestamp_digits} = timestampdigits();
    $context->{uploads} = [];
    $context->{items_row_block} = 1;
    $context->{item_to_row_code} = sub {
        my ($context,$lwp_response) = @_;
        _info($context,'proband ' . $context->{proband}->alias() . ' inquiry form pdf rendered');
        return $lwp_response;
    };
    $context->{export_code} = sub {
        my ($context,$lwp_response) = @_;
        $lwp_response = $lwp_response->[0] if $lwp_response;

        if ($lwp_response and defined $lwp_response->content_ref) {
            my $filename = sprintf($inquiry_data_export_pdfs_filename,$context->{proband}->{id},$context->{timestamp_digits}, $pdfextension);

            my $out;
            $out = CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'PDF/' . $context->{timestamp_digits} . '/'), #'PDF/' . $context->{proband}->{id} . '/'
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

        if ((scalar @{$context->{api_probands_page}}) == 0) {
            my $p = { page_size => $inquiry_data_api_probands_page_size , page_num => $context->{api_probands_page_num} + 1, total_count => undef };
            my $sf = { sort_by => 'id', sort_dir => 'asc', };
            #$sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
            my $first = $context->{api_probands_page_num} * $inquiry_data_api_probands_page_size;
            _info($context,"fetch probands page: " . $first . '-' . ($first + $inquiry_data_api_probands_page_size) . ' of ' . (defined $context->{api_probands_page_total_count} ? $context->{api_probands_page_total_count} : '?'),not $show_page_progress);
            $context->{api_probands_page} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::get_inquiry_proband_list($context->{inquiry_data_trial}->{id}, $active, $active_signup, $p, $sf);
            $context->{api_probands_page_total_count} = $p->{total_count};
            $context->{api_probands_page_num} += 1;
        }
        $context->{proband} = shift @{$context->{api_probands_page}};
        if (defined $context->{proband}) {
            return CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::render_inquiries(
                $context->{proband}->{id},
                $context->{inquiry_data_trial}->{id},
                $active,
                $active_signup,
                0,

            );
        }
        return undef;

    };
    return $result;
}

sub _init_inquiry_data_horizontal_context {
    my ($context) = @_;

    my $result = 1;
    $context->{inquiry_data_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($inquiry_data_trial_id);

    $context->{category_map} = _get_category_map($context);
    $context->{columns} = _get_horizontal_cols($context);

    $context->{error_count} = 0;
    $context->{warning_count} = 0;
    $context->{db} = &get_csv_db();

    $context->{api_probands_page} = [];
    $context->{api_probands_page_num} = 0;
    $context->{api_probands_page_total_count} = undef;

    $context->{items_row_block} = 1;
    $context->{item_to_row_code} = \&_inquiry_data_horizontal_items_to_row;
    $context->{export_code} = \&_insert_inquiry_data_horizontal_rows;
    $context->{api_get_items_code} = sub {
        my ($context) = @_;

        if ((scalar @{$context->{api_probands_page}}) == 0) {
            my $p = { page_size => $inquiry_data_api_probands_page_size , page_num => $context->{api_probands_page_num} + 1, total_count => undef };
            my $sf = { sort_by => 'id', sort_dir => 'asc', };

            my $first = $context->{api_probands_page_num} * $inquiry_data_api_probands_page_size;
            _info($context,"fetch probands page: " . $first . '-' . ($first + $inquiry_data_api_probands_page_size) . ' of ' . (defined $context->{api_probands_page_total_count} ? $context->{api_probands_page_total_count} : '?'),not $show_page_progress);
            $context->{api_probands_page} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::get_inquiry_proband_list($context->{inquiry_data_trial}->{id}, $active, $active_signup, $p, $sf);
            $context->{api_probands_page_total_count} = $p->{total_count};
            $context->{api_probands_page_num} += 1;
        }
        $context->{proband} = shift @{$context->{api_probands_page}};
        if (defined $context->{proband}) {
            return _get_inquiryvalues($context);
        }
        return undef;

    };
    return $result;
}

sub _inquiry_data_horizontal_items_to_row {
    my ($context,$items) = @_;

    my @row = ();
    push(@row,$context->{proband}->{id});
    push(@row,get_proband_columns($context->{proband}));

    my %value_map = ();
    foreach my $item (@$items) {
        if ($item->{inquiry}->{field}->is_select()) {
            if ($col_per_selection_set_value) {
                foreach my $colname (CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_colnames(
                        inquiry => $item->{inquiry},
                        selectionValues => $item->{selectionValues},
                        col_per_selection_set_value => 1,
                        %colname_abbreviation,)) {
                    $value_map{$colname} = booltostring(1);
                }
                foreach my $colname (CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_colnames(
                        inquiry => $item->{inquiry},
                        col_per_selection_set_value => 1,
                        %colname_abbreviation,)) {
                    $value_map{$colname} = booltostring(0) if not exists $value_map{$colname};
                }
            } else {
                my ($colname) = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_colnames(
                    inquiry => $item->{inquiry},
                    selectionValues => $item->{selectionValues},
                    col_per_selection_set_value => 0,
                    %colname_abbreviation,);
                $value_map{$colname} = join($selection_set_value_separator,map { local $_ = $_; $_->{value}; } @{$item->{selectionValues}});
            }
        } else {
            my ($colname) = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_colnames(
                inquiry => $item->{inquiry}, %colname_abbreviation,);
            $value_map{$colname} = $item->{_value};
        }
    }

    foreach my $colname (@{$context->{columns}}) {
        push(@row,(exists $value_map{$colname} ? $value_map{$colname} : undef));
    }

    return \@row;
}


sub _insert_inquiry_data_horizontal_rows {
    my ($context,$inquiry_data_rows) = @_;
    my $result = 1;
    if ((scalar @$inquiry_data_rows) > 0) {
        eval {
            $context->{db}->db_do_begin(CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataHorizontal::getinsertstatement($inquiry_data_ignore_duplicates));
            $context->{db}->db_do_rowblock($inquiry_data_rows);
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
            _info($context,(scalar @$inquiry_data_rows) . " row(s) exported");
        }
    }
    return $result;
}

sub _get_horizontal_cols {
    my ($context) = @_;
    my @columns = ();
    foreach my $category (keys %{$context->{category_map}}) {
        foreach my $inquiry (@{$context->{category_map}->{$category}}) {
            push(@columns,CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_colnames(
                inquiry => $inquiry,

                col_per_selection_set_value => $col_per_selection_set_value,
                %colname_abbreviation,
            ));
        }
    }

    my $max_colname_length = 0;
    my %dupe_map = ();
    foreach my $colname (@columns) {
        my $length = length($colname);
        _warn($context,"$colname length: $length") if $length > $max_colname_length_warn;
        $max_colname_length = length($colname) if $length > $max_colname_length;
        _warn($context,"duplicate column name: $colname") if exists $dupe_map{$colname};
        $dupe_map{$colname} = 1;
    }
    _info($context,(scalar @columns) . " columns, max column name length: $max_colname_length",0);
    return \@columns;
}

sub _get_category_map {
    my ($context) = @_;

        my %category_map = ();
        tie(%category_map, 'Tie::IxHash',
        );
        array_to_map(_get_inquiries($context),sub {
            my $item = shift;
            return $item->{category};
        },undef,'group',\%category_map);
        return \%category_map;

}

sub _get_inquiries {
    my ($context) = @_;
    my $api_inquiries_page = [];
    my $api_inquiries_page_num = 0;
    my $api_inquiries_page_total_count;
    my @inquiries;
    while (1) {
        if ((scalar @$api_inquiries_page) == 0) {
            my $p = { page_size => $inquiry_data_api_inquiries_page_size , page_num => $api_inquiries_page_num + 1, total_count => undef };
            my $sf = {};

            my $first = $api_inquiries_page_num * $inquiry_data_api_inquiries_page_size;
            _info($context,"fetch inquiries page: " . $first . '-' . ($first + $inquiry_data_api_inquiries_page_size) . ' of ' . (defined $api_inquiries_page_total_count ? $api_inquiries_page_total_count : '?'),not $show_page_progress);
            $api_inquiries_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_trial_list($context->{inquiry_data_trial}->{id}, $active, $active_signup, 1, $p, $sf, { _selectionSetValueMap => 1 });
            $api_inquiries_page_total_count = $p->{total_count};
            $api_inquiries_page_num += 1;
        }
        my $inquiry = shift @$api_inquiries_page;
        last unless $inquiry;
        push(@inquiries,$inquiry) if inquiry_data_include_inquiry($inquiry);
    }
    return \@inquiries;
}

sub _get_inquiryvalues {
    my ($context) = @_;
    my @values;

    my $api_values_page = [];
    my $api_values_page_num = 0;
    my $api_values_page_total_count;

    while (1) {
        if ((scalar @$api_values_page) == 0) {
            my $p = { page_size => $inquiry_data_api_values_page_size , page_num => $api_values_page_num + 1, total_count => undef };
            my $sf = {}; #sorted by default

            my $first = $api_values_page_num * $inquiry_data_api_values_page_size;
            _info($context,"fetch inquiry values page: " . $first . '-' . ($first + $inquiry_data_api_values_page_size) . ' of ' . (defined $api_values_page_total_count ? $api_values_page_total_count : '?'),not $show_page_progress);
            $api_values_page = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::get_inquiryvalues($context->{proband}->{id},$context->{inquiry_data_trial}->{id},$active,$active_signup, 1, 0, $p, $sf, { _value => 1, _selectionValueMap => 1 })->{rows};
            $api_values_page_total_count = $p->{total_count};
            $api_values_page_num += 1;
        }
        my $value = shift @$api_values_page;
        last unless $value;
        push(@values,$value);
    }

    return \@values;
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
