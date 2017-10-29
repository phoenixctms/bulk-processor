package CTSMS::BulkProcessor::Projects::ETL::EcrfExport;
use strict;

## no critic

#use threads::shared qw();

use Tie::IxHash;

use JSON qw();

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
    
    $ecrf_data_truncate_table
    $ecrf_data_ignore_duplicates
    $ecrf_data_trial_id
    
    $ecrf_data_api_listentries_page_size
    $ecrf_data_api_ecrfs_page_size
    $ecrf_data_api_values_page_size
    $ecrf_data_row_block
    $ecrf_data_api_tagvalues_page_size
    $ecrf_data_api_ecrffields_page_size    
    $ecrf_data_listentrytags
    
    %export_colname_abbreviation
    ecrf_data_include_ecrffield

    $skip_errors
    
    $ecrf_data_export_upload_folder
    $ecrf_data_export_sqlite_filename
    $ecrf_data_export_horizontal_csv_filename
    $ecrf_data_export_xls_filename
    $ecrf_data_export_xlsx
    
    $audit_trail_export_xls_filename
    $ecrf_journal_export_xls_filename
    $ecrfs_export_xls_filename
    
    $dbtool
    $ecrf_data_export_pdf_filename
    
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
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File qw();

use CTSMS::BulkProcessor::Projects::ETL::EcrfConnectorPool qw(
    get_sqlite_db
    get_csv_db
    destroy_all_dbs
);

use CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataVertical qw();
use CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal qw();

use CTSMS::BulkProcessor::Projects::ETL::EcrfExcel qw();

use CTSMS::BulkProcessor::Array qw(array_to_map);
#use CTSMS::BulkProcessor::Utils qw(threadid);
use CTSMS::BulkProcessor::Utils qw(booltostring timestampdigits run shell_args);

#use CTSMS::BulkProcessor::Utils qw(excel_to_date);
#excel_to_timestamp

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    export_ecrf_data_vertical
    export_ecrf_data_horizontal
    
    publish_ecrf_data_sqlite
    publish_ecrf_data_horizontal_csv
    publish_ecrf_data_xls
    publish_ecrf_data_pdf
    
    publish_audit_trail_xls
    publish_ecrf_journal_xls
    publish_ecrfs_xls
);

my $show_page_retreive_progress = 0;
my $max_colname_length_warn = 64;

my $pdfextension = '.pdf';
my $pdfmimetype = 'application/pdf';

sub publish_ecrf_data_pdf {

    my $filename = sprintf($ecrf_data_export_pdf_filename,timestampdigits(), $pdfextension);
    my $outputfile = $output_path . $filename;    

    #-eep "D:\ctsms\ecrf.pdf" -f -u "somebody" -p "password" -id 5949677
    my @dbtoolargs = ($dbtool,
                           '-eep',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    runerror('dbtool executable not defined',getlogger(__PACKAGE__)) unless $dbtool;
    my ($result,$msg) = run(shell_args(@dbtoolargs)); #suppress output, to hide password
    runerror("$dbtool failed",getlogger(__PACKAGE__)) unless $result;
    _info(undef,"$dbtool executed");
  
    return (CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'PDF/'),
        $outputfile,$filename,$pdfmimetype),$outputfile) if $result;
    return undef;
    
}

sub publish_audit_trail_xls {

    my $filename = sprintf($audit_trail_export_xls_filename,timestampdigits(), $CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsextension);
    my $outputfile = $output_path . $filename;    

    #-eep "D:\ctsms\ecrf.pdf" -f -u "somebody" -p "password" -id 5949677
    my @dbtoolargs = ($dbtool,
                           '-eat',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    runerror('dbtool executable not defined',getlogger(__PACKAGE__)) unless $dbtool;
    my ($result,$msg) = run(shell_args(@dbtoolargs)); #suppress output, to hide password
    runerror("$dbtool failed",getlogger(__PACKAGE__)) unless $result;
    _info(undef,"$dbtool executed");
  
    return (CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsmimetype),$outputfile) if $result;
    return undef;
    
}

sub publish_ecrf_journal_xls {

    my $filename = sprintf($ecrf_journal_export_xls_filename,timestampdigits(), $CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsextension);
    my $outputfile = $output_path . $filename;    

    #-eep "D:\ctsms\ecrf.pdf" -f -u "somebody" -p "password" -id 5949677
    my @dbtoolargs = ($dbtool,
                           '-eej',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    runerror('dbtool executable not defined',getlogger(__PACKAGE__)) unless $dbtool;
    my ($result,$msg) = run(shell_args(@dbtoolargs)); #suppress output, to hide password
    runerror("$dbtool failed",getlogger(__PACKAGE__)) unless $result;
    _info(undef,"$dbtool executed");
  
    return (CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsmimetype),$outputfile) if $result;
    return undef;
    
}

sub publish_ecrfs_xls {

    my $filename = sprintf($ecrfs_export_xls_filename,timestampdigits(), $CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsextension);
    my $outputfile = $output_path . $filename;    

    #-eep "D:\ctsms\ecrf.pdf" -f -u "somebody" -p "password" -id 5949677
    my @dbtoolargs = ($dbtool,
                           '-ee',
                           $outputfile,
                           '-u',
                           $ctsmsrestapi_username,
                           '-p',
                           $ctsmsrestapi_password,
                           '-id',
                           $ecrf_data_trial_id);
    runerror('dbtool executable not defined',getlogger(__PACKAGE__)) unless $dbtool;
    my ($result,$msg) = run(shell_args(@dbtoolargs)); #suppress output, to hide password
    runerror("$dbtool failed",getlogger(__PACKAGE__)) unless $result;
    _info(undef,"$dbtool executed");
  
    return (CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,$CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsmimetype),$outputfile) if $result;
    return undef;
    
}

sub publish_ecrf_data_sqlite {

    my $db = &get_sqlite_db();
    my $dbfilename = $db->{dbfilename};
    destroy_all_dbs();
    
    my $filename = sprintf($ecrf_data_export_sqlite_filename,timestampdigits(), $CTSMS::BulkProcessor::SqlConnectors::SQLiteDB::dbextension);
    
    return (CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'SQLite/'),
        $dbfilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::SQLiteDB::mimetype),$dbfilename);
    
}

sub publish_ecrf_data_horizontal_csv {

    my $db = &get_csv_db();
    my $tablefilename = $db->_gettablefilename(CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal::gettablename());
    destroy_all_dbs();
    
    my $filename = sprintf($ecrf_data_export_horizontal_csv_filename,timestampdigits(), $CTSMS::BulkProcessor::SqlConnectors::CSVDB::csvextension);
    
    return (CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'CSV/'),
        $tablefilename,$filename,$CTSMS::BulkProcessor::SqlConnectors::CSVDB::mimetype),$tablefilename);

}

sub publish_ecrf_data_xls {

    my @modules = ();
    push(@modules,'CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal');    
    push(@modules,'CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataVertical');
    my $filename = sprintf($ecrf_data_export_xls_filename,timestampdigits(), ($ecrf_data_export_xlsx ? $CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsxextension : $CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsextension));
    my $outputfile = $output_path . $filename;
        
    my $result = CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::write_workbook($outputfile,$ecrf_data_export_xlsx,@modules);
    
    return (CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(_get_file_in($filename,'Excel/'),
        $outputfile,$filename,($ecrf_data_export_xlsx ? $CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsxmimetype : $CTSMS::BulkProcessor::Projects::ETL::EcrfExcel::xlsmimetype)),$outputfile) if $result;
    return undef;

}

sub _get_file_in {
    my ($title,$subfolder) = @_;
    $subfolder //= '';
    return {
        "active" => JSON::true,
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
    $result = CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataVertical::create_table($ecrf_data_truncate_table,$context->{ecrffieldmaxselectionsetvaluecount},$ecrf_data_listentrytags) if $result;
    #$result &= CTSMS::BulkProcessor::Projects::Migration::IPGallery::Dao::import::FeatureOptionSetItem::create_table(0);
  
    
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
            my $sf = {};
            #$sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
            my $first = $context->{api_listentries_page_num} * $ecrf_data_api_listentries_page_size;
            _info($context,"retrieving proband list entries page: " . $first . '-' . ($first + $ecrf_data_api_listentries_page_size) . ' of ' . (defined $context->{api_listentries_page_total_count} ? $context->{api_listentries_page_total_count} : '?'),not $show_page_retreive_progress);
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
                if ((scalar keys %$ecrf_data_listentrytags) > 0) {
                    ($context->{tagvalues}, my $nameL10nKeys, my $items) = array_to_map(_get_probandlistentrytagvalues($context),sub { my $item = shift; return $item->{tag}->{field}->{nameL10nKey}; },undef,'last');
                } else {
                    $context->{tagvalues} = {};
                }
             } else {
                return undef;    
            }
        }        

NEXT_ECRF:
        if (not defined $context->{api_ecrfs_page_total_count} or ($context->{api_ecrfs_page_num} * $ecrf_data_api_ecrfs_page_size < $context->{api_ecrfs_page_total_count} and (scalar @{$context->{api_ecrfs_page}}) == 0)) {
            my $p = { page_size => $ecrf_data_api_ecrfs_page_size , page_num => $context->{api_ecrfs_page_num} + 1, total_count => undef };
            my $sf = {};
            #$sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
            my $first = $context->{api_ecrfs_page_num} * $ecrf_data_api_ecrfs_page_size;
            _info($context,"retrieving eCRFs page: " . $first . '-' . ($first + $ecrf_data_api_ecrfs_page_size) . ' of ' . (defined $context->{api_ecrfs_page_total_count} ? $context->{api_ecrfs_page_total_count} : '?'),not $show_page_retreive_progress);
            $context->{api_ecrfs_page} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf::get_trial_list($context->{ecrf_data_trial}->{id}, 1, $p, $sf);
            $context->{api_ecrfs_page_total_count} = $p->{total_count};                
            $context->{api_ecrfs_page_num} += 1;
        }
        if (not defined $context->{ecrf}) {
            $context->{ecrf} = shift @{$context->{api_ecrfs_page}};
            if (defined $context->{ecrf}) {
                $context->{api_values_page_total_count} = undef;
                $context->{api_values_page_num} = 0; #roll over
                $context->{ecrf_status} = eval { CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry::get_item($context->{listentry}->{id},$context->{ecrf}->{id}) };
                _info($context,"proband ID $context->{listentry}->{proband}->{id}: eCRF '$context->{ecrf}->{title}': $context->{ecrf_status}->{status}->{name}");
            } else {
                $context->{listentry} = undef;
                $context->{ecrf_status} = undef;
                goto NEXT_LISTENTRY;
            }
        }
        
        if (not defined $context->{api_values_page_total_count} or ($context->{api_values_page_num} * $ecrf_data_api_values_page_size < $context->{api_values_page_total_count} and (scalar @{$context->{api_values_page}}) == 0)) {
            my $p = { page_size => $ecrf_data_api_values_page_size , page_num => $context->{api_values_page_num} + 1, total_count => undef };
            my $sf = {};
            #$sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
            my $first = $context->{api_values_page_num} * $ecrf_data_api_values_page_size;
            _info($context,"retrieving eCRF values page: " . $first . '-' . ($first + $ecrf_data_api_values_page_size) . ' of ' . (defined $context->{api_values_page_total_count} ? $context->{api_values_page_total_count} : '?'),not $show_page_retreive_progress);
            $context->{api_values_page} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::get_ecrffieldvalues($context->{listentry}->{id},$context->{ecrf}->{id},0, $p, $sf, { _value => 1, _selectionValueMap => 1 })->{rows};
            $context->{api_values_page_total_count} = $p->{total_count};
            $context->{api_values_page_num} += 1;
        }
        my $value = shift @{$context->{api_values_page}};
        if (defined $value) {
            return $value;
        } else {
            $context->{ecrf} = undef;
            goto NEXT_ECRF;
        }

    };
    return $result;
}

sub _ecrf_data_vertical_items_to_row {
    my ($context,$item) = @_;
    return undef unless ecrf_data_include_ecrffield($item->{ecrfField});
    my @row = ();
    push(@row,$item->{listEntry}->{proband}->{id}); #'proband_id',
    foreach my $tag_col (sort keys %$ecrf_data_listentrytags) {
        push(@row, $context->{tagvalues}->{$ecrf_data_listentrytags->{$tag_col}}->{_value});
    }
    push(@row,$item->{listEntry}->{group} ? $item->{listEntry}->{group}->{token} : undef); #'subject_group',
    push(@row,$item->{listEntry}->{lastStatus} ? $item->{listEntry}->{lastStatus}->{status}->{nameL10nKey} : undef); #'enrollment_status',
    push(@row,$context->{ecrf_status} ? $context->{ecrf_status}->{status}->{nameL10nKey} : undef); #'ecrf_status',
    push(@row,$item->{ecrfField}->{ecrf}->{name}); #'ecrf_name',
    push(@row,$item->{ecrfField}->{ecrf}->{id}); #'ecrf_id',
    push(@row,$item->{ecrfField}->{ecrf}->{visit} ? $item->{ecrfField}->{ecrf}->{visit}->{token} : undef); #'ecrf_visit',
    push(@row,$item->{ecrfField}->{ecrf}->{group} ? $item->{ecrfField}->{ecrf}->{group}->{token} : undef); #'ecrf_subject_group',
    push(@row,$item->{ecrfField}->{ecrf}->{position}); #'ecrf_position',
    push(@row,$item->{ecrfField}->{section}); #'ecrf_section',
    push(@row,$item->{ecrfField}->{id}); #'ecrf_field_id',
    push(@row,$item->{ecrfField}->{position}); #'ecrf_field_position',
    push(@row,$item->{ecrfField}->{field}->{nameL10nKey}); #'input_field_name',
    push(@row,$item->{ecrfField}->{field}->{titleL10nKey}); #'input_field_title',
    push(@row,$item->{ecrfField}->{field}->{id}); #'input_field_id',
    push(@row,$item->{ecrfField}->{field}->{fieldType}->{nameL10nKey}); #'input_field_type',
    push(@row,booltostring($item->{ecrfField}->{optional})); #'ecrf_field_optional',
    push(@row,booltostring($item->{ecrfField}->{series})); #'ecrf_field_series',
    push(@row,$item->{index}); #'series_index',
    push(@row,join(',',CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_export_colnames(
        ecrffield => $item->{ecrfField}, index => $item->{index}, %export_colname_abbreviation,
    )));
    push(@row,$item->{version}); #'value_version',
    push(@row,$item->{modifiedUser}->{userName}); #'value_user',
    push(@row,$item->{modifiedTimestamp}); #'value_timestamp',
    push(@row,$item->{_value}); #'value',
    push(@row,booltostring($item->{booleanValue})); #'value_boolean',
    push(@row,$item->{textValue}); #'value_text',
    push(@row,$item->{longValue}); #'value_integer',
    push(@row,$item->{floatValue}); #'value_decimal',
    push(@row,$item->{dateValue} // $item->{timeValue} // $item->{timestampValue}); #'value_date',
    #my @selectionValues = @{$item->{selectionValues} // []};
    #foreach my $i (1..$context->{ecrffieldmaxselectionsetvaluecount}) {
    #    my $selectionValue = shift @selectionValues;
    #    if ($selectionValue) {
    #        $item->{_selectionValueMap}->{}
    #    }
    #    push(@row,$selectionValue ? $selectionValue->{value} : undef);
    #}
    
    my @selectionSetValues = @{$item->{ecrfField}->{field}->{selectionSetValues} // []};
    foreach my $selectionSetValue (@selectionSetValues) {
        if (exists $item->{_selectionValueMap}->{$selectionSetValue->{id}}) {
            push(@row,$item->{_selectionValueMap}->{$selectionSetValue->{id}}->{value});
        } else {
            push(@row,undef);
        }
    }
    for (my $i = scalar @selectionSetValues; $i < ($context->{ecrffieldmaxselectionsetvaluecount} // 0); $i++) {
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
    $result = CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal::create_table($ecrf_data_truncate_table,$context->{columns},$ecrf_data_listentrytags) if $result;
  
    
    $result = _export_items($context) if $result;
    undef $context->{db};
    destroy_all_dbs();
    return ($result,$context->{warning_count});

}

sub _init_ecrf_data_horizontal_context {
    my ($context) = @_;

    my $result = 1;
    $context->{ecrf_data_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($ecrf_data_trial_id);
    
    $context->{ecrfmap} = _get_ecrfmap($context);
    $context->{columns} = _get_horizontal_cols($context);
    
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
            my $sf = {};
            #$sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
            my $first = $context->{api_listentries_page_num} * $ecrf_data_api_listentries_page_size;
            _info($context,"retrieving proband list entries page: " . $first . '-' . ($first + $ecrf_data_api_listentries_page_size) . ' of ' . (defined $context->{api_listentries_page_total_count} ? $context->{api_listentries_page_total_count} : '?'),not $show_page_retreive_progress);
            $context->{api_listentries_page} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::get_trial_list($context->{ecrf_data_trial}->{id}, undef, undef, 1, $p, $sf);
            $context->{api_listentries_page_total_count} = $p->{total_count};
            $context->{api_listentries_page_num} += 1;
        }
        $context->{listentry} = shift @{$context->{api_listentries_page}};
        if (defined $context->{listentry}) {
            #tag values
            if ((scalar keys %$ecrf_data_listentrytags) > 0) {
                ($context->{tagvalues}, my $nameL10nKeys, my $items) = array_to_map(_get_probandlistentrytagvalues($context),sub { my $item = shift; return $item->{tag}->{field}->{nameL10nKey}; },undef,'last');
            } else {
                $context->{tagvalues} = {};
            }
            return _get_ecrffieldvalues($context);
        }
        return undef;

    };
    return $result;
}

sub _ecrf_data_horizontal_items_to_row {
    my ($context,$items) = @_;
    
    my @row = ();
    push(@row,$context->{listentry}->{proband}->{id}); #'proband_id',
    foreach my $tag_col (sort keys %$ecrf_data_listentrytags) {
        push(@row, $context->{tagvalues}->{$ecrf_data_listentrytags->{$tag_col}}->{_value});
    }
    push(@row,$context->{listentry}->{group} ? $context->{listentry}->{group}->{token} : undef); #'subject_group',
    push(@row,$context->{listentry}->{lastStatus} ? $context->{listentry}->{lastStatus}->{status}->{nameL10nKey} : undef); #'enrollment_status',
    
    my %valuemap = ();
    foreach my $item (@$items) {
        my $select = undef;
        foreach my $colname (CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_export_colnames(
                ecrffield => $item->{ecrfField}, index => $item->{index},
                selectionValues => $item->{selectionValues},
                %export_colname_abbreviation,)) {
            $select = $item->{ecrfField}->{field}->is_select() unless defined $select;
            if ($select) {
                $valuemap{$colname} = booltostring(1);
            } else {
                $valuemap{$colname} = $item->{_value};
            }
        }
        if ($select) {
            foreach my $colname (CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_export_colnames(
                    ecrffield => $item->{ecrfField}, index => $item->{index},
                    %export_colname_abbreviation,)) {
                if (not exists $valuemap{$colname}) {
                    $valuemap{$colname} = booltostring(0);
                }
            }
        }
    }
    
    foreach my $colname (@{$context->{columns}}) {
        push(@row,(exists $valuemap{$colname} ? $valuemap{$colname} : undef));
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

sub _get_horizontal_cols {
    my ($context) = @_;
    my @columns = ();
    my $ecrfmap = $context->{ecrfmap};
    foreach my $ecrfid (keys %$ecrfmap) {
        foreach my $section (keys %{$ecrfmap->{$ecrfid}->{sections}}) {
            my $section_info = $ecrfmap->{$ecrfid}->{sections}->{$section};
            my $maxindex = ($section_info->{series} ? $section_info->{maxindex} // 0 : 0);
            foreach my $index (0..$maxindex) {
                foreach my $ecrffield (@{$section_info->{fields}}) {
                    push(@columns,CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_export_colnames(
                        ecrffield => $ecrffield, index => $index, %export_colname_abbreviation,
                    ));
                }
            }
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

sub _get_ecrfmap {
    my ($context) = @_;
    my %ecrfmap = ();
    tie(%ecrfmap, 'Tie::IxHash',
    );
    array_to_map(_get_ecrffields($context),sub {
        my $item = shift;
        return $item->{ecrf}->{id};
    },undef,'group',\%ecrfmap);
    foreach my $ecrfid (keys %ecrfmap) {
        my %sectionmap = ();
        tie(%sectionmap, 'Tie::IxHash',
        );        
        array_to_map($ecrfmap{$ecrfid},sub {
            my $item = shift;
            return $item->{section};
        },undef,'group',\%sectionmap);
        my $ecrf = undef;
        foreach my $section (keys %sectionmap) {
            my $series = $sectionmap{$section}->[0]->{series};
            $ecrf = $sectionmap{$section}->[0]->{ecrf} unless defined $ecrf;
            $sectionmap{$section} = {
                series => $series,
                #ecrf => $ecrf,
                maxindex => ($series ? CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf::get_getecrffieldvaluessectionmaxindex($ecrfid, $section) : undef),
                fields => $sectionmap{$section},
            };
        }
        $ecrfmap{$ecrfid} = { ecrf => $ecrf, sections => \%sectionmap };
    }
    return \%ecrfmap;
}

sub _get_ecrffields {
    my ($context) = @_;
    my $api_ecrffields_page = [];
    my $api_ecrffields_page_num = 0;
    my $api_ecrffields_page_total_count;
    my @ecrffields;
    while (1) {
        if ((scalar @$api_ecrffields_page) == 0) {
            my $p = { page_size => $ecrf_data_api_ecrffields_page_size , page_num => $api_ecrffields_page_num + 1, total_count => undef };
            my $sf = {};
            #$sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
            my $first = $api_ecrffields_page_num * $ecrf_data_api_ecrffields_page_size;
            _info($context,"retrieving eCRF fields page: " . $first . '-' . ($first + $ecrf_data_api_ecrffields_page_size) . ' of ' . (defined $api_ecrffields_page_total_count ? $api_ecrffields_page_total_count : '?'),not $show_page_retreive_progress);
            $api_ecrffields_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_trial_list($context->{ecrf_data_trial}->{id}, undef,1, $p, $sf, { _selectionSetValueMap => 1 });
            $api_ecrffields_page_total_count = $p->{total_count};
            $api_ecrffields_page_num += 1;
        }
        my $ecrffield = shift @$api_ecrffields_page;
        last unless $ecrffield;
        push(@ecrffields,$ecrffield) if ecrf_data_include_ecrffield($ecrffield);
    }
    return \@ecrffields;
}

sub _get_ecrffieldvalues {
    my ($context) = @_;
    my @values;
    foreach my $ecrfid (keys %{$context->{ecrfmap}}) {
        my $api_values_page = [];
        my $api_values_page_num = 0;
        my $api_values_page_total_count;
        $context->{ecrf} = $context->{ecrfmap}->{$ecrfid}->{ecrf};
        $context->{ecrf_status} = eval { CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry::get_item($context->{listentry}->{id},$ecrfid) };
        _info($context,"proband ID $context->{listentry}->{proband}->{id}: eCRF '$context->{ecrf}->{title}': $context->{ecrf_status}->{status}->{name}");
        while (1) {
            if ((scalar @$api_values_page) == 0) {
                my $p = { page_size => $ecrf_data_api_values_page_size , page_num => $api_values_page_num + 1, total_count => undef };
                my $sf = {};
                #$sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
                my $first = $api_values_page_num * $ecrf_data_api_values_page_size;
                _info($context,"retrieving eCRF values page: " . $first . '-' . ($first + $ecrf_data_api_values_page_size) . ' of ' . (defined $api_values_page_total_count ? $api_values_page_total_count : '?'),not $show_page_retreive_progress);
                $api_values_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::get_ecrffieldvalues($context->{listentry}->{id},$ecrfid,0, $p, $sf, { _value => 1, _selectionValueMap => 1 })->{rows};
                $api_values_page_total_count = $p->{total_count};
                $api_values_page_num += 1;
            }
            my $value = shift @$api_values_page;
            last unless $value;
            push(@values,$value);
        }
    }
    return \@values;
}

sub _get_probandlistentrytagvalues {
    my ($context) = @_;
    my $api_listentrytagvalues_page = [];
    my $api_listentrytagvalues_page_num = 0;
    my $api_listentrytagvalues_page_total_count;
    my @listentrytagvalues;
    while (1) {
        if ((scalar @$api_listentrytagvalues_page) == 0) {
            my $p = { page_size => $ecrf_data_api_tagvalues_page_size , page_num => $api_listentrytagvalues_page_num + 1, total_count => undef };
            my $sf = {};
            #$sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
            my $first = $api_listentrytagvalues_page_num * $ecrf_data_api_tagvalues_page_size;
            _info($context,"retrieving proband list entry tag values page: " . $first . '-' . ($first + $ecrf_data_api_tagvalues_page_size) . ' of ' . (defined $api_listentrytagvalues_page_total_count ? $api_listentrytagvalues_page_total_count : '?'),not $show_page_retreive_progress);
            $api_listentrytagvalues_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues::get_probandlistentrytagvalues($context->{listentry}->{id}, 0, 0, $p, $sf, { _value => 1 })->{rows};
            $api_listentrytagvalues_page_total_count = $p->{total_count};
            $api_listentrytagvalues_page_num += 1;
        }
        my $listentrytagvalue = shift @$api_listentrytagvalues_page;
        last unless $listentrytagvalue;
        push(@listentrytagvalues,$listentrytagvalue);
    }
    return \@listentrytagvalues;
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
