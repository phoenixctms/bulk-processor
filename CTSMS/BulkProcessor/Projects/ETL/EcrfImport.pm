package CTSMS::BulkProcessor::Projects::ETL::EcrfImport;
use strict;

## no critic

use threads qw(yield);
use threads::shared qw();

use utf8;
use Encode qw();

use Tie::IxHash;
use File::Basename qw();

use CTSMS::BulkProcessor::Globals qw(
    $ctsmsrestapi_username
);

use CTSMS::BulkProcessor::FileProcessors::CSVFile qw();
use CTSMS::BulkProcessor::FileProcessors::XlsFileSimple qw();
use CTSMS::BulkProcessor::FileProcessors::XlsxFileSimple qw();

use CTSMS::BulkProcessor::Projects::ETL::EcrfSettings qw(
    $skip_errors
    $timezone
    $ecrf_data_trial_id

    %colname_abbreviation
    $selection_set_value_separator


    $ecrf_proband_alias_column_name
    $ecrf_proband_category_column_name
    $ecrf_proband_department_column_name
    $ecrf_proband_gender_column_name

    get_proband_columns
);

use CTSMS::BulkProcessor::Projects::ETL::EcrfImporter::Settings qw(
    $update_listentrytag_values
    $append_selection_set_values
    $clear_sections
    $clear_all_sections

    $ecrf_import_filename

    $import_ecrf_data_horizontal_multithreading
    $import_ecrf_data_horizontal_numofthreads
    $import_ecrf_data_horizontal_blocksize

    $ecrf_values_col_block
    $listentrytag_values_col_block
    
    $ecrf_name_column_name
    $ecrf_visit_column_name
    
    get_ecrf_columns
);
#$ecrf_department_nameL10nKey
#$ecrf_proband_alias_format
#$ecrf_proband_alias_column_index

use CTSMS::BulkProcessor::Projects::ETL::Job qw(
    update_job
    @job_file
);

use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
    processing_debug
);
use CTSMS::BulkProcessor::LogError qw(
    rowprocessingerror
    rowprocessingwarn
);

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValue qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Department qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::user::UserService::User qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::InputFieldType qw(
    $CHECKBOX
    $DATE
    $TIME
    $TIMESTAMP

    $INTEGER
    $FLOAT

    $SKETCH

    $AUTOCOMPLETE
);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Sex qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job qw(
    $PROCESSING_JOB_STATUS
    $FAILED_JOB_STATUS
    $OK_JOB_STATUS
);

use CTSMS::BulkProcessor::Projects::ETL::Ecrf qw(
    get_ecrf_map
    get_horizontal_cols
    get_probandlistentrytag_map
    get_section_blank
);

use CTSMS::BulkProcessor::Array qw(array_to_map contains);
use CTSMS::BulkProcessor::Utils qw(threadid stringtobool trim excel_to_date chopstring zerofill);

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi_last_error
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    import_ecrf_data_horizontal
);

my @header_row :shared = ();
my $header_rownum :shared = 0;
#my $probandlistentrymaxposition :shared = 0;
my $registration :shared;
my $warning_count :shared = 0;
my $value_count :shared = 0;

my $comment_char = '#';
my $rownum_digits = 3;

my @csvxextension = ('.csv', '.txt');
my @xlsextension = ('.xls');
my @xlsxextension = ('.xlsx');
#join('|',map { quotemeta($_) . '$'; } map { ($_, uc($_)); } (@csvxextension,@xlsextension,@xlsxextension))
my $rfileextensions = '\\.[a-zA-Z0-9_.-]+$';

sub _get_input_filename {

    my ($filename_opt,$filename_config) = @_;
    my $filename = $job_file[0];
    if (length($filename_opt)) {
        $filename = $filename_opt;
    } elsif (length($filename_config)) {
        $filename = $filename_config;
    }
    return $filename;

}

sub _get_importer {

    my $context = shift;
    my $file = shift;
    rowprocessingerror($context->{tid},'no file specified',getlogger(__PACKAGE__)) unless length($file);
    my ($filename, $filedir, $filesuffix) = File::Basename::fileparse($file, $rfileextensions);
    return CTSMS::BulkProcessor::FileProcessors::CSVFile->new(@_) if contains($filesuffix,\@csvxextension,1); # CSVDB does not support multithread
    return CTSMS::BulkProcessor::FileProcessors::XlsFileSimple->new(@_) if contains($filesuffix,\@xlsextension,1);
    return CTSMS::BulkProcessor::FileProcessors::XlsxFileSimple->new(@_) if contains($filesuffix,\@xlsxextension,1);
    rowprocessingerror($context->{tid},"unsupported input file type '$filesuffix'",getlogger(__PACKAGE__));

}

sub import_ecrf_data_horizontal {

    my ($file) = @_;

    {
        lock $warning_count;
        $warning_count = 0;
        lock $value_count;
        $value_count = 0;
    }

    my $static_context = {};
    my $result = _init_context($static_context);

    $file = _get_input_filename($file,$ecrf_import_filename);
    
    if ($result) {
        my $importer = _get_importer($static_context,$file,
            numofthreads => $import_ecrf_data_horizontal_numofthreads,
            blocksize => $import_ecrf_data_horizontal_blocksize);
        foreach my $sheet_name ($importer->get_sheet_names($file)) {
            $result &= $importer->process(
                file => $file,
                static_context => $static_context,
                sheet_name => $sheet_name,
                process_code => sub {
                    my ($context,$rows,$row_offset) = @_;
                    $context->{row_offset} = $row_offset;
                    my $rownum = $row_offset;
                    foreach my $row (@$rows) {
                        $rownum++;
                        #next unless $rownum == 1 or $rownum >= 47;
                        next unless (scalar @$row);
                        next unless (scalar grep { length(trim($_)) > 0; } @$row);
                        next if substr(trim($row->[0]),0,length($comment_char)) eq $comment_char;
                        update_job($PROCESSING_JOB_STATUS,$rownum,$row_offset + $import_ecrf_data_horizontal_blocksize);
                        next unless _set_ecrf_data_horizontal_context($context,$row,$rownum);
                        #next unless id == $context->{proband}->{id};
                        _load_ecrf_status($context);
                        next unless _clear_ecrf($context);
                        next unless _set_ecrf_values_horizontal($context);
                    }
        
                    return 1;
                },
                init_process_context_code => sub {
                    my ($context)= @_;
                    $context->{error_count} = 0;
                    $context->{warning_count} = 0;
                },
                uninit_process_context_code => sub {
                    my ($context)= @_;
                    {
                        lock $warning_count;
                        $warning_count += $context->{warning_count};
                    }
        
                },
                multithreading => $import_ecrf_data_horizontal_multithreading,
            );
            lock $header_rownum;
            @header_row = ();
            $header_rownum = 0;
        }
    }

    return ($result,$warning_count,$value_count);

}

sub _init_context {

    my ($context) = @_;

    my $result = 1;

    $context->{tid} = threadid();

    $context->{ecrf_data_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($ecrf_data_trial_id);
    if (not $context->{ecrf_data_trial}->{status}->{ecrfValueInputEnabled}) {
        rowprocessingerror($context->{tid},"eCRFs are locked for this trial (trial status: $context->{ecrf_data_trial}->{status}->{name})",getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    } elsif ($context->{ecrf_data_trial}->locked) {
        rowprocessingerror($context->{tid},"trial is locked",getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }

    my ($keys,$values);

    eval {
        my ($person, $animal) = (undef, undef);
        $person = 1 if $context->{ecrf_data_trial}->{type}->{person};
        $animal = 1 unless $context->{ecrf_data_trial}->{type}->{person};
        ($context->{proband_category_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory::get_items($person, $animal),
            sub { my $item = shift; return $item->{nameL10nKey}; }, sub { my $item = shift; return $item; }, 'last');
        #$context->{proband_category} = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory::get_preset_item(0,1);
    };
    if ($@ or not keys %{$context->{proband_category_map}}) {
        rowprocessingerror($context->{tid},'error loading proband categories',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }

    eval {
        ($context->{department_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Department::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; }, sub { my $item = shift; return $item; },'last');
        #$context->{department} = $deparmtent_map->{$ecrf_department_nameL10nKey} if $ecrf_department_nameL10nKey;
    };
    if ($@ or not keys %{$context->{department_map}}) {
        rowprocessingerror($context->{tid},'error loading departments',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }

    eval {
        ($context->{criteriontie_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
        ($context->{criterionrestriction_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
        ($context->{criterionproperty_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty::get_items(
            $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule::PROBAND_DB),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
    };
    if ($@) {
        rowprocessingerror($context->{tid},'error loading criteria building blocks',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }

    my $users;
    eval {
        (my $user_criterionproperty_map, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty::get_items(
            $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule::USER_DB),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
        $users = CTSMS::BulkProcessor::RestRequests::ctsms::user::UserService::User::search({
            module => $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule::USER_DB,
            criterions => [{
                position => 1,
                #tieId => undef,
                restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
                propertyId => $user_criterionproperty_map->{'user.name'},
                stringValue => $ctsmsrestapi_username,
            }],
        });
    };
    if ($@ or (scalar @$users) != 1) {
        rowprocessingerror($context->{tid},'error loading user',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    } else {
        $context->{ctsmsrestapi_user} = $users->[0];
    }

    $context->{all_listentrytag_map} = get_probandlistentrytag_map($context);
    $context->{listentrytag_map} = { %{$context->{all_listentrytag_map}} };

    $context->{ecrf_map} = get_ecrf_map($context,1);
    $context->{all_columns} = get_horizontal_cols($context, 10 ** ($colname_abbreviation{index_digits} // 2) - 1);

    ($context->{all_column_map}, $keys, $values) = array_to_map($context->{all_columns},
        sub { my $item = shift; return $item->{colname}; },undef,'first');
    
    $context->{visit_map} = { map { defined $_->{visit} ? ($_->{visit}->{id} => $_->{visit}) : (); } @$values };

    return $result;
}

#sub _set_ecrf_data_vertical_context {
#
#    my ($context,$row,$rownum) = @_;
#
#    $context->{rownum} = $rownum;
#
#    $context->{proband} = undef;
#    $context->{probandlistentry} = undef;
#
#    my $result = 1;
#
#    if (_init_vertical_record($context,$row)) {
#        $result = _register_proband($context);
#    } else {
#        $result = 0;
#    }
#
#    return $result;
#
#}

sub _set_ecrf_data_horizontal_context {

    my ($context,$row,$rownum) = @_;

    $context->{rownum} = $rownum;

    $context->{proband} = undef;
    $context->{probandlistentry} = undef;

    my $result = 1;

    if (_init_horizontal_record($context,$row)) {
        $result = _register_proband($context);
    } else {
        $result = 0;
    }

    return $result;

}

#sub _init_vertical_record {
#
#}

sub _init_horizontal_record {

    my ($context,$row) = @_;
    while (1) {
        yield();
        lock $header_rownum;
        last if ($header_rownum > 0 or $context->{row_offset} == 0);
    }
    my %header = ();
    my @headerrow = ();
    my $initialized = 0;
    if ($header_rownum > 0) {
        $context->{record} = {};
        my $i = 0;
        foreach my $val (@$row) {
            if (length(trim($header_row[$i]))) {
                $context->{record}->{$header_row[$i]} = $val;
                push(@headerrow,$header_row[$i]);
            }
            $i++;
        }
        $initialized = 1;
    } else {
        $context->{record} = undef;
        foreach my $colname (@$row) {
            if (length(trim($colname))) {
                if (exists $header{$colname}) {
                    #alias/list entry tag/ecrf column name conflict
                    _error($context,"column '$colname' specified more than once in header row");
                } else {
                    $header{$colname} = 1;
                    push(@headerrow,$colname);
                }
            }
            push(@header_row,$colname);
        }
        _info($context,"header row with " . (scalar @headerrow) . " columns - " . chopstring(join(', ', @headerrow)));
        lock $header_rownum;
        $header_rownum = $context->{rownum};
    }
    
    if ($initialized) {
        my ($keys, $values);
        my $columns_changed = 0;
        my @ecrfvisit = ();
        if (length($ecrf_name_column_name)
            and exists $context->{record}->{$ecrf_name_column_name}) {
            _error($context,"empty ecrf name") unless length($context->{record}->{$ecrf_name_column_name});
            my @ecrfs = grep { $_->{id} eq $context->{record}->{$ecrf_name_column_name}
                   or $_->{name} eq $context->{record}->{$ecrf_name_column_name}; } map { $_->{ecrf}; } values %{$context->{ecrf_map}};
            _error($context,"unknown ecrf name/id '" . $context->{record}->{$ecrf_name_column_name} . "'") unless scalar @ecrfs;
            my $ecrf = shift @ecrfs;
            unless (defined $context->{ecrf} and $ecrf->{id} == $context->{ecrf}->{id}) {
                $columns_changed = 1;
            }
            $context->{ecrf} = $ecrf;
            push(@ecrfvisit,$context->{ecrf}->{name});
        } else {
            $columns_changed = 1 if defined $context->{ecrf};
            undef $context->{ecrf};
        }
        if (length($ecrf_visit_column_name)
            and exists $context->{record}->{$ecrf_visit_column_name}
            and length($context->{record}->{$ecrf_visit_column_name})) {
            my @visits = grep { $_->{id} eq $context->{record}->{$ecrf_visit_column_name}
                   or $_->{token} eq $context->{record}->{$ecrf_visit_column_name}; } (defined $context->{ecrf} ? @{$context->{ecrf}->{visits}} : (values %{$context->{visit_map}}));
            _error($context,"unknown visit token/id '" . $context->{record}->{$ecrf_visit_column_name} . "'" .
                (defined $context->{ecrf} ? " for eCRF '$context->{ecrf}->{name}'" : '')) unless scalar @visits;
            my $visit = shift @visits;
            unless (defined $context->{visit} and $visit->{id} == $context->{visit}->{id}) {
                $columns_changed = 1;
            }
            $context->{visit} = $visit;
            push(@ecrfvisit,$context->{visit}->{token});
        } else {
            $columns_changed = 1 if defined $context->{visit};
            undef $context->{visit};
        }
        
        _info($context,"mapping columns for " . join('@',@ecrfvisit)) if scalar @ecrfvisit;
        
        if ($columns_changed) {
            $context->{listentrytag_map} = { %{$context->{all_listentrytag_map}} };
            $context->{all_columns} = get_horizontal_cols($context, 10 ** ($colname_abbreviation{index_digits} // 2) - 1);
            ($context->{all_column_map}, $keys, $values) = array_to_map($context->{all_columns},
                sub { my $item = shift; return $item->{colname}; },undef,'first');
            undef $context->{columns};
        }
            
        unless ($context->{columns}) {
            %header = map { $_ => 1; } @headerrow; # if $initialized;
            
            my @columns = grep { exists $header{$_->{colname}}; } @{$context->{all_columns}}; # do not clone columns
    
            my %disabled_ecrf_map = ();
            my %disabled_ecrffield_map = ();
            my %sketch_inputfield_map = ();
            $context->{columns} = [];
            my $message;
            foreach my $column (@columns) {
                next if exists $disabled_ecrf_map{$column->{ecrffield}->{ecrf}->{id}};
                next if exists $disabled_ecrffield_map{$column->{ecrffield}->{id}};
                next if exists $sketch_inputfield_map{$column->{ecrffield}->{field}->{id}};
                if ($column->{ecrffield}->{ecrf}->{disabled}) {
                    $message = "skipping disabled eCRF: $column->{ecrffield}->{ecrf}->{uniqueName}";
                    $disabled_ecrf_map{$column->{ecrffield}->{ecrf}->{id}} = $column->{ecrffield}->{ecrf};
                } elsif ($column->{ecrffield}->{disabled}) {
                    $message = "skipping disabled eCRF field: $column->{ecrffield}->{uniqueName}";
                    $disabled_ecrffield_map{$column->{ecrffield}->{id}} = $column->{ecrffield};
                } elsif ($column->{ecrffield}->{field}->{fieldType}->{type} eq $SKETCH) {
                    $message = "skipping sketch input field: $column->{ecrffield}->{field}->{name}";
                    $sketch_inputfield_map{$column->{ecrffield}->{field}->{id}} = $column->{ecrffield}->{field};
                } else {
                    $message = "column '$column->{colname}' mapped to $column->{ecrffield}->{uniqueName}";
                    push(@{$context->{columns}},$column);
                }
                _info($context,$message,1); # unless $initialized;
            }
    
            $message = (scalar @{$context->{columns}}) . ' columns mapped';
            _info($context,$message); # unless $initialized; # print in first thread only
            #processing_debug($context->{tid},$message,getlogger(__PACKAGE__)) if $initialized;
    
            _error($context,"no columns mapped") unless scalar @{$context->{columns}};
    
            #not $initialized and
            if (my @unknown_colnames = grep { not exists $context->{all_column_map}->{$_}
                   and not exists $context->{listentrytag_map}->{$_}
                   and not contains($_,[ get_proband_columns() ])
                   and not contains($_,[ get_ecrf_columns() ])
                   and $_ ne 'proband_id'
                   #and not contains($_,[ get_probandlistentry_columns() ]) # updating these is not implemented (yet)
                   ; } @headerrow) {
                map { _info($context,"ignoring column '$_'",1); } @unknown_colnames;
                _warn($context,"ignoring " . (scalar @unknown_colnames) . " columns - " . chopstring(join(', ', @unknown_colnames)));
            }
    
            ($context->{column_map}, $keys, $values) = array_to_map($context->{columns},
                sub { my $item = shift; return $item->{colname}; },undef,'first');
    
            delete @{$context->{listentrytag_map}}{grep { not exists $context->{listentrytag_map}->{$_}; } @headerrow};
    
        }
    }

    return $initialized;

}

sub _set_ecrf_values_horizontal {

    my ($context) = @_;

    my $result = 1;

    undef $context->{section_maxindex_map};
    undef $context->{in};
    $context->{skip_columns} = {};
    $context->{last_ecrf} = undef;
    $context->{last_visit} = undef;
    $context->{last_section} = undef;
    $context->{last_series} = undef;
    $context->{last_index} = undef;

    $context->{ecrf_value_stats} = {
        total => 0,
        created => 0,
        updated => 0,
    };

    my $last_ecrf;
    my $last_visit;
    my $last_section;
    my $last_series;
    my $last_index;

    my $last_ecrf_label;
    my $last_ecrf_section_label;

    foreach my $colname (map { $_->{colname}; } @{$context->{columns}}) {

        #unless ($context->{all_column_map}->{$colname}->{ecrffield}->{field}->{nameL10nKey} eq 'field name'
        #    and $context->{all_column_map}->{$colname}->{ecrffield}->{ecrf}->{name} eq 'ecrf name'
        #    and $context->{all_column_map}->{$colname}->{ecrffield}->{section} eq 'section') {
        #    next;
        #}

        $result &= _append_ecrffieldvalue_in($context,$colname,$context->{record}->{$colname});


        # save on next eCRF or visit or section or section index:
        if (defined $last_ecrf and (
                $last_ecrf->{id} != $context->{last_ecrf}->{id}
                or ($last_visit ? $last_visit->{id} : '') ne ($context->{last_visit} ? $context->{last_visit}->{id} : '')
                or ($last_section // '') ne ($context->{last_section} // '')
                or ($last_index // '') ne ($context->{last_index} // '')
            )) {
            my $last_in = pop(@{$context->{in}});
            $result &= _save_ecrf_values($context,$last_ecrf_section_label);
            push(@{$context->{in}},$last_in) if $last_in;
            _log_ecrf_values_count($context,$last_ecrf_label) if ($last_ecrf->{id} != $context->{last_ecrf}->{id})
        }
        # save next chunk if full unless it's a new index section:
        if ($ecrf_values_col_block > 0
            and (scalar @{$context->{in}}) >= $ecrf_values_col_block
            and (not $context->{last_series} or
                 $context->{last_index} <= (_get_ecrf_section_maxindex($context) // -1))) {
            $result &= _save_ecrf_values($context);
        }
        $last_ecrf = $context->{last_ecrf};
        $last_visit = $context->{last_visit};
        $last_section = $context->{last_section};
        $last_series = $context->{last_series};
        $last_index = $context->{last_index};
        $last_ecrf_label = _get_last_ecrf_label($context,0);
        $last_ecrf_section_label = _get_last_ecrf_label($context,1);
    }

    $result &= _save_ecrf_values($context);

    _log_ecrf_values_count($context,$last_ecrf_label);

    return $result;

}

sub _clear_ecrf {

    my ($context) = @_;

    my $result = 1;
    my $listentry_id = $context->{probandlistentry}->{id};

    $context->{clear_map} = {};

    if (not $context->{listentry_created}
        and ($clear_sections or $clear_all_sections)
        and not exists $context->{clear_map}->{$listentry_id}) {
        my $columns = [];
        $columns = $context->{all_columns} if $clear_all_sections;
        $columns = $context->{columns} if $clear_sections;
        my $removed_value_count = 0;

        $context->{clear_map}->{$listentry_id} = {};
        foreach my $column (@$columns) {
            #$context->{clear_map}->{$listentry_id} //= {};

            next unless _get_ecrffieldvalue_editable($context,$column->{colname});

            my $ecrf_id = $column->{ecrffield}->{ecrf}->{id};
            $context->{clear_map}->{$listentry_id}->{$ecrf_id} //= {};
            my $section_map = $context->{clear_map}->{$listentry_id}->{$ecrf_id};

            my $visit_id = undef;
            $visit_id = $column->{visit}->{id} if $column->{visit};
            if (defined $visit_id) {
                $context->{clear_map}->{$listentry_id}->{$ecrf_id}->{$visit_id} //= {};
                $section_map = $context->{clear_map}->{$listentry_id}->{$ecrf_id}->{$visit_id};
                next if ($context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}->{$visit_id}->{status}
                    and $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}->{$visit_id}->{status}->{valueLockdown});
            } else {
                next if ($context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}->{status}
                    and $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}->{status}->{valueLockdown});
            }

            my $section = ($column->{ecrffield}->{section} // '');
            unless (exists $section_map->{$section}) {
                my $values;
                my $section_label = "eCRF '$column->{ecrffield}->{ecrf}->{name}" . (defined $column->{visit} ? '@' . $column->{visit}->{token} : '') . "' section '" . $section . "'";
                eval {
                    $values = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValue::clear($listentry_id, $ecrf_id, $visit_id, $section);
                };
                if ($@) {
                    _warn_or_error($context,"error deleting $section_label values: " . $@);
                    $result = 0;
                } else {
                    _info($context,"$section_label values deleted",1);
                }
                $section_map->{$section} = $values;
                $removed_value_count += scalar @$values;
            }
        }
        _info($context,"$removed_value_count eCRF values deleted");
    }
    return $result;

}

sub _load_ecrf_status {

    my ($context) = @_;

    my $listentry_id = $context->{probandlistentry}->{id};

    $context->{ecrfstatus_map} = {};

    if (not exists $context->{ecrfstatus_map}->{$listentry_id}) {
        my $columns = $context->{columns};
        $columns = $context->{all_columns} if $clear_all_sections;
        $context->{ecrfstatus_map}->{$listentry_id} = {};
        #my %stats = ();
        my $ecrf_count = 0;
        my $locked_status_count = 0;
        foreach my $column (@$columns) {
            #$context->{ecrfstatus_map}->{$listentry_id} //= {};

            my $ecrf_id = $column->{ecrffield}->{ecrf}->{id};
            my $visit_id = undef;
            $visit_id = $column->{visit}->{id} if $column->{visit};

            my $log = 0;
            my $status;
            if (defined $visit_id) {
                $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id} //= {};
                unless (exists $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}->{$visit_id}) {
                    if ($context->{listentry_created}) {
                        $status = undef;
                    } else {
                        $status = eval { CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry::get_item($listentry_id,$ecrf_id,$visit_id); };
                    }
                    $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}->{$visit_id} = $status;
                    $log = 1;
                    #$stats{$status ? $status->{status}->{name} : '<new>'} += 1;
                    $ecrf_count += 1;
                    $locked_status_count += 1 if ($status and $status->{status}->{valueLockdown});
                }
            } else {
                unless (exists $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}) {
                    if ($context->{listentry_created}) {
                        $status = undef;
                    } else {
                        $status = eval { CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry::get_item($listentry_id,$ecrf_id,undef); };
                    }
                    $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id} = $status;
                    $log = 1;
                    #$stats{$status ? $status->{status}->{name} : '<new>'} += 1;
                    $ecrf_count += 1;
                    $locked_status_count += 1 if ($status and $status->{status}->{valueLockdown});
                }
            }
            _info($context,'proband ' . $context->{probandlistentry}->{proband}->alias() . " eCRF '$column->{ecrffield}->{ecrf}->{name}" .
                (defined $column->{visit} ? '@' . $column->{visit}->{token} : '') . "' status: " . ($status->{status} ? $status->{status}->{name} : '<new>'),1) if $log;
        }
        _info($context,"$ecrf_count eCRFs ($locked_status_count locked)");
    }

}

sub _register_proband {

    my ($context) = @_;

    my $result = 1;

    $context->{listentry_created} = 0;
    $context->{criterions} = [];
    my $alias;
    my $id;
    my %record = %{$context->{record}};
    if (length($ecrf_proband_alias_column_name) 
        and exists $context->{record}->{$ecrf_proband_alias_column_name}
        and length($context->{record}->{$ecrf_proband_alias_column_name})) {
        $alias = $context->{record}->{$ecrf_proband_alias_column_name};
    }
    if (exists $context->{record}->{proband_id}
        and length($context->{record}->{proband_id})) {
        # use proband_id column if specified and not empty:
        $id = $context->{record}->{proband_id};
        $result = _append_probandid_criterion($context,$id);
        delete $record{proband_id};
    } elsif (defined $alias) {
        $result = _append_probandalias_criterion($context,$alias);
        delete $record{$alias};
    } elsif (scalar keys %{$context->{listentrytag_map}}) {
        # otherwise use proband list entry tags if specified:
        my $blank = 1;
        foreach my $tag_col (keys %{$context->{listentrytag_map}}) {
            if (_append_listentrytag_criterion($context,$tag_col)) {
                push(@{$context->{criterions}},{
                    position => ((scalar @{$context->{criterions}}) + 1),
                    tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::INTERSECT},
                });
            }
            $blank &= (length($context->{record}->{$tag_col}) > 0 ? 0 : 1);
            delete $record{$tag_col};
        }
        if ($blank) {
            $result = 0;
        } else {
            pop(@{$context->{criterions}});
        }
    #} else {
    #    ## otherwise use first column as alias:
    #    ##$alias = $context->{record}->{$header_row[$ecrf_proband_alias_column_index]};
    #    ##$result = _append_probandalias_criterion($context,$alias);
    #    _warn_or_error($context,XX"error loading proband: " . $@);
    #    $result = 0;
    }

    unless (scalar grep { length(trim($_)) > 0; } values %record) {
        $result = 0; #no ecrf data to save
    }
    
    if ($result) {
        if (scalar @{$context->{criterions}}) { # requires at least one proband list attribute of supported field type ...
            lock $registration;
            my $probands = undef;
            my $set_listentrytag_values = 0;
            my $proband_created = 0;
            eval {
                $probands = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::search({
                    module => $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule::PROBAND_DB,
                    criterions => $context->{criterions},
                });
            };
            if ($@) {
                _warn_or_error($context,"error loading proband: " . $@);
                $result = 0;
            } elsif ((scalar @$probands) == 0) {
                if (defined $id) {
                    _warn_or_error($context,"cannot find proband id " . $id);
                    $result = 0;
                } elsif (defined $alias) {
                    eval {
                         $context->{proband} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::add_item(_get_proband_in($context,$alias));
                    };
                    if ($@) {
                        _warn_or_error($context,"error creating proband: " . $@);
                        $result = 0;
                    } else {
                        _info($context,"proband " . $context->{proband}->alias . " created");
                        $proband_created = 1;
                    }
                } else {
                    if (defined $context->{ecrf}) {
                        _warn_or_error($context,"cannot create proband with proband list entry when eCRF is specified for the data row");
                        $result = 0;
                    } elsif (defined $context->{visit}) {
                        _warn_or_error($context,"cannot create proband with proband list entry when visit is specified for the data row");
                        $result = 0;
                    } else {
                        eval {
                            #lock $probandlistentrymaxposition;
                            $context->{probandlistentry} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::add_item(
                                _get_probandlistentry_in($context),undef,1);
                        };
                        if ($@) {
                            _warn_or_error($context,"error creating proband with proband list entry: " . $@);
                            $result = 0;
                        } else {
                            $context->{proband} = $context->{probandlistentry}->{proband};
                            _info($context,"proband " . $context->{proband}->alias . " with proband list entry position $context->{probandlistentry}->{position} created");
                            $proband_created = 1;
                            $context->{listentry_created} = 1;
                        }
                    }
                }
                $set_listentrytag_values = 1;
            } elsif ((scalar @$probands) > 1) {
                _warn_or_error($context,"more than one proband found");
                $result = 0;
            } else {
                $context->{proband} = $probands->[0];
                if (defined $alias and (not defined $context->{proband}->{alias} or $alias ne $context->{proband}->{alias})) {
                    _warn_or_error($context,"differring proband id $context->{proband}->{id} alias");
                    #$result = 0;
                } else {
                    _info($context,"proband " . $context->{proband}->alias . " found");
                }
                $set_listentrytag_values = $update_listentrytag_values if (defined $id or defined $alias);
            }

            if ($context->{proband} and $context->{proband}->locked) {
                _info($context,"proband is locked");
                return 0;
            }

            if (defined $context->{proband} and not defined $context->{probandlistentry}) {

                my $probandlistentries = undef;
                eval {
                    $probandlistentries = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::get_trial_list($ecrf_data_trial_id,
                        undef,$context->{proband}->{id},1);
                };
                if (my $err = $@) {
                    _rollback_proband($context) if $proband_created;
                    _warn_or_error($context,"error loading proband list entry: " . $err);
                    $result = 0;
                } elsif ((scalar @$probandlistentries) == 0) {
                    eval {
                        #lock $probandlistentrymaxposition;
                        $context->{probandlistentry} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::add_item(
                            _get_probandlistentry_in($context));
                    };
                    if (my $err = $@) {
                        _rollback_proband($context) if $proband_created;
                        _warn_or_error($context,"error creating proband list entry: " . $err);
                        $result = 0;
                    } else {
                        _info($context,"proband list entry (position $context->{probandlistentry}->{position}) created");
                        $context->{listentry_created} = 1;
                    }
                } elsif ((scalar @$probandlistentries) > 1) {
                    _rollback_proband($context) if $proband_created;
                    _warn_or_error($context,"more than one proband list entry found");
                    $result = 0;
                } else {
                    $context->{probandlistentry} = $probandlistentries->[0];
                    _info($context,"proband list entry (position $context->{probandlistentry}->{position}) found");
                }

            }

            if ($set_listentrytag_values
                and defined $context->{probandlistentry}
                and scalar keys %{$context->{listentrytag_map}}) {
                eval {
                    _set_listentrytag_values($context);
                };
                if (my $err = $@) {
                    _rollback_proband($context) if $proband_created;
                    _warn_or_error($context,$err);
                    $result = 0;
                }
            }

            if ($context->{probandlistentry}
                and $context->{probandlistentry}->{lastStatus}
                and not $context->{probandlistentry}->{lastStatus}->{status}->{ecrfValueInputEnabled}) {
                _info($context,"proband list entry is locked (proband list entry status: $context->{probandlistentry}->{lastStatus}->{status}->{name})");
                $result = 0;
            }

        } else {
            _warn_or_error($context,"no criterion to load proband");
            $result = 0;
        }
    }

    return $result;
}

sub _rollback_proband {

    my ($context) = @_;
    lock $registration;
    eval {
        #lock $probandlistentrymaxposition;
        $context->{proband} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::delete_item($context->{proband}->{id},1,undef);
    };
    if ($@) {
        _warn($context,"rollback - error deleting created proband " . $context->{proband}->alias . ": " . $@);
    } else {
        _info($context,"rollback - created proband " . $context->{proband}->alias . " deleted");
    }
    undef $context->{proband};
    undef $context->{probandlistentry};

}

sub _get_proband_in {
    my ($context,$alias) = @_;

    my $category;
    if (length($ecrf_proband_category_column_name)
        and exists $context->{record}->{$ecrf_proband_category_column_name}) {
        my $value = $context->{record}->{$ecrf_proband_category_column_name};
        if (length($value)) {
            if (exists $context->{proband_category_map}->{$value}) {
                $category = $context->{proband_category_map}->{$value};
            } else {
                die("unknown proband category '$value'");
            }
        }
    }
    $category = shift @{[ grep { $_->{preset} and not $_->{signup}; } values %{$context->{proband_category_map}} ]} unless $category;

    my $department;
    if (length($ecrf_proband_department_column_name)
        and exists $context->{record}->{$ecrf_proband_department_column_name}) {
        my $value = $context->{record}->{$ecrf_proband_department_column_name};
        if (length($value)) {
            if (exists $context->{department_map}->{$value}) {
                $department = $context->{department_map}->{$value};
            } else {
                die("unknown proband department '$value'");
            }
        }
    }
    $department = $context->{ctsmsrestapi_user}->{department} unless $department;

    my $gender;
    if (length($ecrf_proband_gender_column_name)
        and exists $context->{record}->{$ecrf_proband_gender_column_name}) {
        $gender = $context->{record}->{$ecrf_proband_gender_column_name};
    }
    $gender = $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Sex::NOT_KNOWN unless length($gender);

    my %in = (
        "categoryId" => $category->{id},
        "person" => ($context->{ecrf_data_trial}->{type}->{person} ? \1 : \0),
        "blinded" => \1,
        "departmentId" => $department->{id},
        "gender" => $gender,
        "alias" => $alias,
    );
    #if (EXPR) {
    #    $in{comment} = xxx
    #}

    return \%in;

}

sub _get_probandlistentry_in {
    my ($context) = @_;
    #lock $probandlistentrymaxposition;
    my $probandlistentrymaxposition = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_probandlistentrymaxposition($ecrf_data_trial_id);
    $probandlistentrymaxposition = 0 unless length($probandlistentrymaxposition);
    return {
        "position" => ($probandlistentrymaxposition + 1),
        "probandId" => $context->{proband}->{id},
        "trialId" => $context->{ecrf_data_trial}->{id},
    };
}

sub _get_ecrffieldvalue_editable {
    my ($context,$colname) = @_;
    my $listentry_id = $context->{probandlistentry}->{id};

    my $column;
    $column = $context->{column_map}->{$colname} if $colname;

    return 0 unless $column;

    my $ecrffield = $column->{ecrffield};
    my $ecrffield_id = $ecrffield->{id};
    my $ecrf_id = $ecrffield->{ecrf}->{id};
    my $visit_id = undef;
    $visit_id = $column->{visit}->{id} if $column->{visit};
    my $index = $column->{index};

    my $status;
    if (defined $visit_id) {
        $status = $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}->{$visit_id}->{status};
    } else {
        $status = $context->{ecrfstatus_map}->{$listentry_id}->{$ecrf_id}->{status};
    }

    if ($status and $status->{valueLockdown}) {
        _info($context,"skipping $ecrffield->{uniqueName} (eCRF status: $status->{name})",1);
        return 0;
    } else {
        return 1;
    }

    #if (not $editable
    #    and $out
    #    and $out->{}) {
    #    #code
    #}

}

sub _get_ecrf_section_maxindex {
    my ($context) = @_;

    $context->{section_maxindex_map} //= {};

    return undef unless $context->{last_series};

    my $listentry_id = $context->{probandlistentry}->{id};

    my $ecrf_id = $context->{last_ecrf}->{id};
    $context->{section_maxindex_map}->{$listentry_id}->{$ecrf_id} //= {};
    my $section_map = $context->{section_maxindex_map}->{$listentry_id}->{$ecrf_id};

    my $visit_id = undef;
    $visit_id = $context->{last_visit}->{id} if $context->{last_visit};
    if (defined $visit_id) {
        $context->{section_maxindex_map}->{$listentry_id}->{$ecrf_id}->{$visit_id} //= {};
        $section_map = $context->{section_maxindex_map}->{$listentry_id}->{$ecrf_id}->{$visit_id};
    }

    my $section = ($context->{last_section} // '');
    unless (exists $section_map->{$section}) {
        my $section_label = "eCRF '$context->{last_ecrf}->{name}" . (defined $context->{last_visit} ? '@' . $context->{last_visit}->{token} : '') . "' section '" . $section . "'";
        my $maxindex;
        eval {
            $maxindex = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::get_getecrffieldvaluessectionmaxindex($listentry_id, $ecrf_id, $visit_id, $section);
        };
        $maxindex = undef unless length($maxindex);
        if ($@) {
            _warn_or_error($context,"error loading $section_label max index: " . $@);
        } else {
            _info($context,"$section_label max index: " . (defined $maxindex ? $maxindex : '<new>'),1);
        }
        $section_map->{$section} = $maxindex;
    }

    return $section_map->{$section};
}


sub _get_ecrffieldvalue_in {
    my ($context,$colname,$value,$contains_code) = @_;

    return (undef,1) unless defined $value;
    
    my $listentry_id = $context->{probandlistentry}->{id};

    my $column;
    $column = $context->{column_map}->{$colname} if $colname;

    
    if ($column) {

        my $ecrffield = $column->{ecrffield};
        
        return (undef, 1) if exists $context->{skip_columns}->{$colname};
        return (undef, 1) if $ecrffield->{series} and get_section_blank($context,$column);
        return (undef, 1) unless _get_ecrffieldvalue_editable($context,$colname);

        my $ecrffield_id = $ecrffield->{id};
        my $visit_id = undef;
        $visit_id = $column->{visit}->{id} if $column->{visit};
        my $index = $column->{index};

        my %in = (
            ecrfFieldId => $ecrffield_id,
            visitId => $visit_id,
            index => $index,
            listEntryId => $listentry_id,
        );
        my $old_value = undef;
        unless ($clear_sections or $clear_all_sections) {
            eval {
                $old_value = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::get_item($listentry_id, $visit_id, $ecrffield_id, $index)->{rows}->[0];
            };
            if ($@) {
                my $error_code = get_ctsms_restapi_last_error();
                if (contains($error_code, [ qw(ecrf_field_value_index_gap ecrf_field_value_index_not_zero) ])) {
                    _info($context,"error loading old eCRF field value: " . $@,1);
                } else {
                    _warn($context,"error loading old eCRF field value: " . $@);
                    return (undef,0);
                }
            } elsif (defined $old_value) {
                if ($old_value->{id}) {
                    $in{id} = $old_value->{id};
                    $in{version} = $old_value->{version};
                } else {
                    # just a preset value ...
                }
            }
        }
        #return (undef, 1) unless _get_ecrffieldvalue_editable($context,$colname,$old_value);
        $value = _mark_utf8($value);
        my $field_type = $ecrffield->{field}->{fieldType}->{type};
        if ($ecrffield->{field}->is_select() and $field_type ne $SKETCH) {
            if (exists $column->{colnames}) {
                foreach (@{$column->{colnames}}) {
                    if (exists $context->{column_map}->{$_}) {
                        $column = $context->{column_map}->{$_};
                        $value = $context->{record}->{$_};
                        $context->{skip_columns}->{$_} = 1;
                        if (stringtobool($value)) {
                            $in{selectionValueIds} //= [];
                            push(@{$in{selectionValueIds}},$column->{selection_set_value}->{id});
                        }
                    } elsif ($append_selection_set_values
                             and defined $old_value
                             and not $ecrffield->{field}->is_select_one()) {
                        $column = $context->{all_column_map}->{$_};
                        if (grep { $column->{selection_set_value}->{id} == $_->{id}; } @{$old_value->{selectionValues}}) {
                            $in{selectionValueIds} //= [];
                            push(@{$in{selectionValueIds}},$column->{selection_set_value}->{id});
                        }
                    }

                }
            } else {
                eval {
                    $in{selectionValueIds} = _get_selection_set_value_ids($context,$ecrffield->{field},$value,$contains_code,$selection_set_value_separator);
                };
                if ($@) {
                    _warn_or_error($context,$@);
                    return (undef,0);
                }
            }
        } elsif ($field_type eq $AUTOCOMPLETE) {
            $in{textValue} = (length($value) ? $value : undef);
        } elsif ($ecrffield->{field}->is_text()) {
            $in{textValue} = (length($value) ? $value : '');
        } elsif ($field_type eq $CHECKBOX) {
            $in{booleanValue} = (stringtobool($value) ? \1 : \0);
        } elsif ($field_type eq $DATE) {
            $in{dateValue} = _valid_excel_to_date($value);
            #$in{dateValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $TIME) {
            $in{timeValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $TIMESTAMP) {
            $in{timestampValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $INTEGER) {
            $in{longValue} = ((length($value) and not _is_unknown_value($value)) ? $value : undef);
        } elsif ($field_type eq $FLOAT) {
            $in{floatValue} = ((length($value) and not _is_unknown_value($value)) ? _sanitize_decimal($value) : undef);
        } else {
            _warn_or_error($context,"unsupported eCRF field type '$field_type' ($ecrffield->{field}->{name})");
            return (undef,0);
        }
        return (\%in,1);
    } else {
        _warn_or_error($context,"unknown eCRF field column '$colname'");
        return (undef,0);
    }
}

sub _append_ecrffieldvalue_in {
    my $context = shift;
    my $colname = shift;
    $context->{in} = [] unless $context->{in};
    my ($in,$result) = _get_ecrffieldvalue_in($context, $colname, @_);
    if ($in) {
        push(@{$context->{in}},$in);
        if ($result) {
            my $column = $context->{column_map}->{$colname};
            $context->{last_ecrf} = $column->{ecrffield}->{ecrf};
            $context->{last_visit} = $column->{visit};
            $context->{last_section} = $column->{ecrffield}->{section};
            $context->{last_series} = $column->{ecrffield}->{series};
            $context->{last_index} = $column->{index};
        }
    }
    return $result;
}

sub _get_listentrytagvalue_in {
    my ($context,$colname,$value,$contains_code) = @_;

    return undef unless defined $value;

    my $listentry_id = $context->{probandlistentry}->{id};

    my $listentrytag;
    $listentrytag = $context->{listentrytag_map}->{$colname} if $colname;

    if ($listentrytag) {
        #return (undef, 1) if exists $context->{skip_columns}->{$colname};

        my $listentrytag_id = $listentrytag->{id};

        my %in = (
            tagId => $listentrytag_id,
            listEntryId => $listentry_id,
        );
        my $old_value = undef;
        eval {
            $old_value = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues::get_item($listentry_id, $listentrytag_id)->{rows}->[0];
        };
        if ($@) {
            #_info($context,"error loading old proband list attribute field value: " . $@,1);
            die("error loading old proband list attribute field value: " . $@);
        } elsif (defined $old_value) {
            $in{id} = $old_value->{id};
            $in{version} = $old_value->{version};
        }

        $value = _mark_utf8($value);
        my $field_type = $listentrytag->{field}->{fieldType}->{type};
        if ($listentrytag->{field}->is_select() and $field_type ne $SKETCH) {
            $in{selectionValueIds} = _get_selection_set_value_ids($context,$listentrytag->{field},$value,$contains_code);
        } elsif ($field_type eq $AUTOCOMPLETE) {
            $in{textValue} = (length($value) ? $value : undef);
        } elsif ($listentrytag->{field}->is_text()) {
            $in{textValue} = (length($value) ? $value : '');
        } elsif ($field_type eq $CHECKBOX) {
            $in{booleanValue} = (stringtobool($value) ? \1 : \0);
        } elsif ($field_type eq $DATE) {
            $in{dateValue} = _valid_excel_to_date($value);
            #$in{dateValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $TIME) {
            $in{timeValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $TIMESTAMP) {
            $in{timestampValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $INTEGER) {
            $in{longValue} = ((length($value) and not _is_unknown_value($value)) ? $value : undef);
        } elsif ($field_type eq $FLOAT) {
            $in{floatValue} = ((length($value) and not _is_unknown_value($value)) ? _sanitize_decimal($value) : undef);
        } else {
            die("unsupported proband list attribute field type '$field_type' ($listentrytag->{field}->{name})");
        }
        return \%in;
    } else {
        die("unknown proband list attribute field column '$colname'");
    }
}

sub _set_listentrytag_values {

    my ($context) = @_;

    undef $context->{in};

    foreach my $tag_col (keys %{$context->{listentrytag_map}}) {
        _append_listentrytagvalue_in($context,$tag_col,$context->{record}->{$tag_col});
        if ($listentrytag_values_col_block > 0
            and (scalar @{$context->{in}}) >= $listentrytag_values_col_block) {
            _save_listentrytag_values($context);
        }
    }

    _save_listentrytag_values($context);

    #return $result;

}

sub _append_listentrytagvalue_in {
    my $context = shift;
    my $colname = shift;
    $context->{in} = [] unless $context->{in};
    my $in = _get_listentrytagvalue_in($context, $colname, @_);
    push(@{$context->{in}},$in) if $in;
}

sub _get_selection_set_value_ids {

    my ($context,$field,$value,$contains_code,$separator) = @_;
    $contains_code //= sub {
        my ($selectionSetValue,$values) = @_;
        return _contains($selectionSetValue->{value},$values);
    };
    $separator //= ',';
    if (ref $value) {
        unless ('ARRAY' eq ref $value) {
            die((ref $value) . " value for $field->{name}");
        }
    } else {
        if (length($value)) {
            $value = [ split(quotemeta($separator),$value) ];
        } else {
            $value = undef;
        }
    }
    $value //= [];
    $value = [ map { trim($_); } grep { length($_) and not _is_unknown_value($_); } @$value ];
    my $selectionValueIds = [ map { $_->{id}; } grep { &$contains_code($_,$value); } @{$field->{selectionSetValues}} ];
    unless ((scalar @{$selectionValueIds}) == (scalar @$value)) {
        die("unknown value(s) '" . join(',',@$value) . "' for $field->{name}");
    }
    return $selectionValueIds;

}

sub _append_probandalias_criterion {
    my ($context,$alias) = @_;
    if (length($alias)) {
        push(@{$context->{criterions}},{
            position => 1,
            #tieId => undef,
            restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
            propertyId => $context->{criterionproperty_map}->{'proband.personParticulars.alias'},
            stringValue => _mark_utf8($alias),
        });
        push(@{$context->{criterions}},{
            position => 2,
            tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
            restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
            propertyId => $context->{criterionproperty_map}->{'proband.deferredDelete'},
            booleanValue => \0,
        });
        # if there is a department column, search for alias by department ...
        if (length($ecrf_proband_department_column_name)
            and exists $context->{record}->{$ecrf_proband_department_column_name}) {
            my $value = $context->{record}->{$ecrf_proband_department_column_name};
            if (length($value)) {
                if (exists $context->{department_map}->{$value}) {
                    my $department = $context->{department_map}->{$value};
                    push(@{$context->{criterions}},{
                        position => 3,
                        tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
                        restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
                        propertyId => $context->{criterionproperty_map}->{'proband.department.id'},
                        longValue => $department->{id},
                    });
                } else {
                    _warn_or_error($context,"unknown proband department '$value'");
                    return 0;
                }
            } else {
                _warn_or_error($context,"empty proband site");
                return 0;
            }
        }
        return 1;
    } else {
        _warn_or_error($context,"empty proband alias");
        return 0;
    }
}

sub _append_probandid_criterion {
    my ($context,$id) = @_;
    if (length($id)) {
        push(@{$context->{criterions}},{
            position => 1,
            #tieId => undef,
            restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
            propertyId => $context->{criterionproperty_map}->{'proband.id'},
            longValue => $id,
        });
        return 1;
    } else {
        _warn_or_error($context,"empty proband id");
        return 0;
    }
}

sub _append_listentrytag_criterion {

    my ($context,$colname) = @_;
    my $listentry_tag = $context->{listentrytag_map}->{$colname};
    my $field_type = $listentry_tag->{field}->{fieldType}->{type};
    my $value = $context->{record}->{$colname};
    return 0 unless defined $value;
    my @criterions = ();
    push(@criterions,{
        position => ((scalar @{$context->{criterions}}) + 1),
        #tieId => undef,
        restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
        propertyId => $context->{criterionproperty_map}->{'proband.trialParticipations.tagValues.tag.id'},
        longValue => $listentry_tag->{id},
    });
    my %criterion = (
        position => ((scalar @{$context->{criterions}}) + 2),
        tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
        propertyId => $context->{criterionproperty_map}->{$listentry_tag->{field}->criterion_property('proband.trialParticipations.tagValues.value.')},
    );
    $value = _mark_utf8($value);
    if ($listentry_tag->{field}->is_select_one()) {
        $criterion{restrictionId} = $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ};
        $criterion{stringValue} = $value;
    } elsif ($listentry_tag->{field}->is_text()) {
        $criterion{restrictionId} = $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ};
        $criterion{stringValue} = $value;
    } elsif ($field_type eq $CHECKBOX) {
        $criterion{restrictionId} = $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ};
        $criterion{booleanValue} = (stringtobool($value) ? \1 : \0);
    } elsif ($field_type eq $DATE) {
        $criterion{restrictionId} = $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ};
        $criterion{dateValue} = $value;
    } elsif ($field_type eq $INTEGER) {
        $criterion{restrictionId} = $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ};
        $criterion{longValue} = ((length($value) and not _is_unknown_value($value)) ? $value : undef);
    } elsif ($field_type eq $FLOAT) {
        $criterion{restrictionId} = $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ};
        $criterion{floatValue} = ((length($value) and not _is_unknown_value($value)) ? _sanitize_decimal($value) : undef);
    } else {
        _warn_or_error($context,"unsupported proband list attribute field type '$field_type' ($listentry_tag->{field}->{name})");
        return 0;
    }
    push(@criterions,\%criterion);
    push(@criterions,{
        position => ((scalar @{$context->{criterions}}) + 3),
        tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
        restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
        propertyId => $context->{criterionproperty_map}->{'proband.deferredDelete'},
        booleanValue => \0,
    });
    push(@{$context->{criterions}},@criterions);
    return 1;

}

sub _get_last_ecrf_label {

    my ($context,$append_section) = @_;
    my $ecrf_label;
    if ($context->{last_ecrf}) {
        $ecrf_label = "eCRF '$context->{last_ecrf}->{name}" . ($context->{last_visit} ? '@' . $context->{last_visit}->{token} : '') . "'";
        $ecrf_label .= " section '" . ($context->{last_section} // '') . "'" if $append_section;
        $ecrf_label .= (defined $context->{last_index} ? ' index ' . $context->{last_index} : '') if $append_section;
    }
    return $ecrf_label;

}

sub _log_ecrf_values_count {

    my ($context,$ecrf_label) = @_;
    $ecrf_label //= _get_last_ecrf_label($context);
    _info($context,(length($ecrf_label) ? "$ecrf_label - " : '') . $context->{ecrf_value_stats}->{total} . " eCRF values (" . $context->{ecrf_value_stats}->{created} . " created, " . $context->{ecrf_value_stats}->{updated} . " updated)");
    lock $value_count;
    $value_count += $context->{ecrf_value_stats}->{total};
    $context->{ecrf_value_stats} = {
        total => 0,
        created => 0,
        updated => 0,
    };

}

sub _save_ecrf_values {

    my ($context,$ecrf_section_label) = @_;
    my $result = 1;
    return $result unless scalar @{$context->{in}};
    my $out;
    eval {
        $out = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::set_ecrffieldvalues($context->{in},undef,$timezone);
    };
    my $stats = _get_values_stats($context,$out,sub {
            my $in_row = shift;
            return ($in_row->{listEntryId} . '-' . $in_row->{ecrfFieldId} . '-' . ($in_row->{visitId} // '') . '-' . ($in_row->{index} // ''));
        },sub {
            my $out_row = shift;
            return ($out_row->{listEntry}->{id} . '-' . $out_row->{ecrfField}->{id} . '-' . ($out_row->{visit} ? $out_row->{visit}->{id} : '') . '-' . ($out_row->{index} // ''));
        });
    $context->{in} = [];
    $ecrf_section_label //= _get_last_ecrf_label($context,1);
    if ($@) {
        _warn_or_error($context,"$ecrf_section_label - error saving eCRF values: " . $@);
        $result = 0;
    } else {
        map { _info($context,$_->{ecrfField}->{uniqueName} . ' saved',1); } @{$out->{rows}};
        _info($context,"$ecrf_section_label - " . (scalar @{$out->{rows}}) . " eCRF values (" . $stats->{created} . " created, " . $stats->{updated} . " updated)",1);
        map { $context->{ecrf_value_stats}->{$_} += $stats->{$_}; } keys %$stats;
    }
    return $result;

}

sub _get_values_stats {
    my ($context,$out,$get_in_hash,$get_out_hash) = @_;
    my %stats = (
        total => 0,
        created => 0,
        updated => 0,
    );
    if ($out) {
        my ($in_version_map, $keys, $values) = array_to_map([ grep { exists $_->{id} and defined $_->{id}; } @{$context->{in}} ],
            sub { my $item = shift; return $get_in_hash->($item); }, sub { my $item = shift; return $item->{version}; }, 'last');
        foreach my $out_row (@{$out->{rows}}) {
            my $hash = $get_out_hash->($out_row);
            $stats{total} += 1;
            $stats{created} += 1 if not exists $in_version_map->{$hash};
            $stats{updated} += 1 if (exists $in_version_map->{$hash} and $out_row->{version} > $in_version_map->{$hash});
        }
    }
    return \%stats;
}

sub _save_listentrytag_values {

    my ($context) = @_;
    #my $result = 1;
    return unless scalar @{$context->{in}};
    my $out;
    eval {
        $out = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues::set_probandlistentrytagvalues($context->{in},undef,$timezone);
    };
    my $stats = _get_values_stats($context,$out,sub {
            my $in_row = shift;
            return ($in_row->{listEntryId} . '-' . $in_row->{tagId});
        },sub {
            my $out_row = shift;
            return ($out_row->{listEntry}->{id} . '-' . $out_row->{tag}->{id});
        });
    $context->{in} = [];
    if ($@) {
        die("error saving proband list attribute values: " . $@);
        #$result = 0;
    } else {
        _info($context,(scalar @{$out->{rows}}) . " proband list attribute values (" . $stats->{created} . " created, " . $stats->{updated} . " updated)");
        #_info($context,(scalar @{$out->{rows}}) . " proband list attribute values (");
        #$context->{value_count} += scalar @{$out->{rows}};
    }
    #return $result;

}

sub _contains {
    my ($item,$array_ptr,$case_insensitive) = @_;
    return contains($item,$array_ptr,$case_insensitive) unless ref $item;
    foreach (@$item) {
        if (contains($_,$array_ptr,$case_insensitive)) {
            return 1;
        }
    }
    return 0;
}

sub _is_unknown_value {
    my $string = shift;
    #if ($string =~ /^[?x]+$/ or
    if ($string eq '#VALUE!') {
        return 1;
    }
    return 0;
}

sub _sanitize_decimal {

    my ($decimal) = @_;

    $decimal =~ s/\s+//g;
    $decimal =~ s/[,.]/./;
    return $decimal;

}

sub _valid_excel_to_date {
    my $excel_date = trim(shift);
    my $date;
    eval {
        $date = excel_to_date($excel_date) if ($excel_date =~ /^\d+$/ and $excel_date > 3);
        $date .= ' 00:00:00' if $date;
    };
    return $date;
}

sub _mark_utf8 {
    my $byte_string = shift;
    my $ustring = $byte_string;
    eval {
        $ustring = Encode::decode('UTF-8',$byte_string,Encode::FB_CROAK);
    };
    return $ustring;
    #or die "Could not decode string: $@";
    #return Encode::decode("UTF-8", shift);
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
    rowprocessingerror($context->{tid},_get_log_label($context) . $message,getlogger(__PACKAGE__));

}

sub _warn {

    my ($context,$message) = @_;
    $context->{warning_count} = $context->{warning_count} + 1;
    rowprocessingwarn($context->{tid},_get_log_label($context) . $message,getlogger(__PACKAGE__));

}

sub _info {

    my ($context,$message,$debug) = @_;
    if ($debug) {
        processing_debug($context->{tid},_get_log_label($context) . $message,getlogger(__PACKAGE__));
    } else {
        processing_info($context->{tid},_get_log_label($context) . $message,getlogger(__PACKAGE__));
    }
}

sub _get_log_label {

    my ($context) = @_;
    my $label = "(line " . zerofill($context->{rownum},$rownum_digits);
    $label .= "/proband " . $context->{proband}->alias if $context->{proband};
    $label .= ") ";
    return $label;

}

1;
