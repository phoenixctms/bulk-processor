package CTSMS::BulkProcessor::Projects::ETL::Remoc::Import;
use strict;

## no critic

#use threads::shared qw();

use Spreadsheet::Reader::ExcelXML qw();
#qw(:just_raw_data);

use File::Basename qw();
use File::Find qw();

use CTSMS::BulkProcessor::Projects::ETL::Settings qw(
    $input_path
    $skip_errors

);
use CTSMS::BulkProcessor::Projects::ETL::Remoc::Settings qw(
    
    $dialysis_substitution_volume_ignore_duplicates
    $dialysis_substitution_volume_truncate_table
    $dialysis_substitution_volume_header_row
    $dialysis_substitution_volume_sheet_name
    $dialysis_substitution_volume_custom_formats
    $dialysis_substitution_volume_row_block
    $dialysis_substitution_volume_file_pattern
    $dialysis_substitution_volume_file
    $dialysis_substitution_volume_api_file_page_size
    
    $dialysis_substitution_volume_ecrf_id


);
use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
    processing_debug
    fileprocessingstarted
    fileprocessingdone
);
use CTSMS::BulkProcessor::LogError qw(
    fileprocessingwarn
    fileprocessingerror
);

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File qw();

use CTSMS::BulkProcessor::Projects::ETL::ProjectConnectorPool qw(
    get_sqlite_db
    destroy_all_dbs
);

use CTSMS::BulkProcessor::Projects::ETL::Remoc::Dao::DialysisSubstitutionVolume qw();

#use CTSMS::BulkProcessor::Array qw(removeduplicates);
#use CTSMS::BulkProcessor::Utils qw(threadid);

#use CTSMS::BulkProcessor::Utils qw(excel_to_date);
#excel_to_timestamp

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    import_dialysis_substitution_volume
);

my $show_page_retreive_progress = 1;

sub import_dialysis_substitution_volume {

    my $context = {};
    my $result = _init_dialysis_substitution_volume_context($context);
    #$result &= CTSMS::BulkProcessor::Projects::Migration::IPGallery::Dao::import::FeatureOptionSetItem::create_table(0);

    $result = CTSMS::BulkProcessor::Projects::ETL::Remoc::Dao::DialysisSubstitutionVolume::create_table($dialysis_substitution_volume_truncate_table) if $result;
    
    $result = _import_files($context) if $result;
    undef $context->{db};
    destroy_all_dbs();
    return ($result,$context->{warning_count},$context->{file_list});

}

sub _import_files {
    my ($context) = @_;
    my $result = 1;
    if (defined $context->{file}) {
        if (-d $context->{file}) {
            File::Find::find({ wanted => sub {
                
                $context->{filename} = $File::Find::name;
                if (-f $context->{filename} and (not defined $context->{file_pattern} or (File::Basename::basename($context->{filename}) =~ /$context->{file_pattern}/))) {
                    push(@{$context->{file_list}},$context->{filename});
                    if (&{$context->{import_code}}($context)) {
                        push(@{$context->{file_list}},$context->{filename});
                    } else {
                        $result = 0;
                    }
                }
            
            }, follow => 1 }, $context->{file});
        } else {
            $context->{filename} = $context->{file};
            if (&{$context->{import_code}}($context)) {
                push(@{$context->{file_list}},$context->{filename});
            } else {
                $result = 0;
            }
        }
    } else {
        while (my $apifile = &{$context->{api_get_files_code}}($context)) {
            $context->{filename} = $input_path . $apifile->{fileName};
            _info($context,"downloading '$apifile->{fileName}'");            
            my $lwp_response;
            eval {
                #my $head = CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::get_item($apifile->{id});
                $lwp_response = CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::download($apifile->{id});
            };
            if ($@) {
                _warn_or_error($context, "unable to retrieve file id $apifile->{id}: " . $@);
                next;
            }            
            my $out;
            unless (open($out, '>', $context->{filename})) {
                _warn_or_error($context, "Unable to open: $!");
                $result = 0;
                next;
            }
            binmode($out);
            print $out $lwp_response->content;
            close($out);
            if (&{$context->{import_code}}($context)) {
                push(@{$context->{file_list}},$context->{filename});
            } else {
                $result = 0;
            }
        }
    }
    
    return $result;
}

sub _init_dialysis_substitution_volume_context {
    my ($context) = @_;
    
    my $result = 1;
    $context->{dialysis_substitution_volume_ecrf} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf::get_item($dialysis_substitution_volume_ecrf_id);
    
    $context->{file_list} = [];
    $context->{error_count} = 0;
    $context->{warning_count} = 0;
    $context->{db} = &get_sqlite_db(); 
    $context->{file} = $dialysis_substitution_volume_file;
    $context->{file_pattern} = $dialysis_substitution_volume_file_pattern;
    $context->{import_code} = \&_import_dialysis_substitution_volume_file;
    $context->{api_file_page} = [];
    $context->{api_file_page_num} = 0;
    $context->{api_file_page_total_count} = undef;
    $context->{api_get_files_code} = sub {
        my ($context) = @_;
        if ((scalar @{$context->{api_file_page}}) == 0) {
            #$dialysis_substitution_volume_file_pattern;
            my $p = { page_size => $dialysis_substitution_volume_api_file_page_size , page_num => $context->{api_file_page_num} + 1, total_count => undef };
            my $sf = {};
            $sf->{fileName} = $dialysis_substitution_volume_file_pattern if defined $dialysis_substitution_volume_file_pattern;
            my $first = $context->{api_file_page_num} * $dialysis_substitution_volume_api_file_page_size;
            _info($context,"retrieving file list: " . $first . '-' . ($first + $dialysis_substitution_volume_api_file_page_size) . ' of ' . (defined $context->{api_file_page_total_count} ? $context->{api_file_page_total_count} : '?'),not $show_page_retreive_progress);
            $context->{api_file_page} = CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::get_trialfiles($context->{dialysis_substitution_volume_ecrf}->{trial}->{id}, $p, $sf);
            $context->{api_file_page_total_count} = $p->{total_count};
            $context->{api_file_page_num} += 1;
        }
        return shift @{$context->{api_file_page}};
    };
    return $result;
}

sub _import_dialysis_substitution_volume_file {
    my ($context) = @_;

    fileprocessingstarted($context->{filename},getlogger(__PACKAGE__));
    my $workbook = Spreadsheet::Reader::ExcelXML->new(
        file => $context->{filename},
        #group_return_type => 'value',
        count_from_zero => 0,
        values_only => 1,
        empty_is_end => 1,
        group_return_type => ('HASH' eq ref $dialysis_substitution_volume_custom_formats ? 'value' : 'xml_value'),
        from_the_edge => 0,
        empty_return_type => 'undef_string',
        spaces_are_empty => 1,
        merge_data => 0,
        column_formats => 0,
    );
    if (not $workbook->file_opened) {
        _warn_or_error($context,$workbook->error());
    } else {
        my $worksheet = $workbook->worksheet($dialysis_substitution_volume_sheet_name);
        if (not defined $worksheet) {
            _warn_or_error($context,$workbook->error());
        } else {
            my $result = 1;
            _info($context,"worksheet '" . $worksheet->get_name() . "' opened");
            $worksheet->set_custom_formats($dialysis_substitution_volume_custom_formats) if 'HASH' eq ref $dialysis_substitution_volume_custom_formats;
            #$worksheet->set_custom_formats({
            #    2 =>'yyyy-mm-dd',
            #});
            $worksheet->set_headers($dialysis_substitution_volume_header_row) if defined $dialysis_substitution_volume_header_row;
            if ($worksheet->header_row_set()) {
                $worksheet->go_to_or_past_row($worksheet->get_excel_position($worksheet->get_last_header_row()));
            }
            my $filename = File::Basename::basename($context->{filename});
            my $row_id = 0;
            my $value;
            my @rows = ();
            while (1) {
                $value = $worksheet->fetchrow_arrayref;
                last if (not $value or 'EOF' eq $value);
                $row_id++;
                unshift(@$value,$row_id);
                unshift(@$value,$filename);
                $#$value = $CTSMS::BulkProcessor::Projects::ETL::Remoc::Dao::DialysisSubstitutionVolume::expected_fieldnames_count - 1;
                push(@rows,$value);
                #if ($skip_errors or (scalar @rows) >= $dialysis_substitution_volume_row_block) {
                if ((scalar @rows) >= $dialysis_substitution_volume_row_block) {
                    $result &= _insert_dialysis_substitution_volume_rows($context,\@rows);
                    @rows = ();
                }
            }
            $result &= _insert_dialysis_substitution_volume_rows($context,\@rows);
            fileprocessingdone($context->{filename},getlogger(__PACKAGE__));
            return $result;
        }
    }
    return 0;

}

sub _insert_dialysis_substitution_volume_rows {
    my ($context,$dialysis_substitution_volume_rows) = @_;
    my $result = 1;
    if ((scalar @$dialysis_substitution_volume_rows) > 0) {
        eval {
            $context->{db}->db_do_begin(CTSMS::BulkProcessor::Projects::ETL::Remoc::Dao::DialysisSubstitutionVolume::getinsertstatement($dialysis_substitution_volume_ignore_duplicates));
            $context->{db}->db_do_rowblock($dialysis_substitution_volume_rows);
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
            _info($context,(scalar @$dialysis_substitution_volume_rows) . " row(s) imported");
        }
    }
    return $result;
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
    fileprocessingerror($context->{filename},$message,getlogger(__PACKAGE__));

}

sub _warn {

    my ($context,$message) = @_;
    $context->{warning_count} = $context->{warning_count} + 1;
    fileprocessingwarn($context->{filename},$message,getlogger(__PACKAGE__));

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
