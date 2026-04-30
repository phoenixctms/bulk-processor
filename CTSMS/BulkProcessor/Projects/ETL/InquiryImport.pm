package CTSMS::BulkProcessor::Projects::ETL::InquiryImport;
use strict;

## no critic

use threads qw(yield);
use threads::shared qw();

use CTSMS::BulkProcessor::Projects::ETL::InquirySettings qw(
    $skip_errors
    $timezone
    $inquiry_trial_id

    %colname_abbreviation
    $selection_set_value_separator


    $inquiry_proband_alias_column_name
    $inquiry_proband_category_column_name
    $inquiry_proband_department_column_name
    $inquiry_proband_gender_column_name

    get_proband_columns
);

use CTSMS::BulkProcessor::Projects::ETL::InquiryImporter::Settings qw(
    $append_selection_set_values
    $clear_categories
    $clear_all_categories

    $inquiry_import_filename

    $import_inquiry_data_horizontal_multithreading
    $import_inquiry_data_horizontal_numofthreads
    $import_inquiry_data_horizontal_blocksize

    $inquiry_values_col_block
    
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
    rowprocessingerror
    rowprocessingwarn
);

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValue qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction qw();

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


use CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job qw(
    $PROCESSING_JOB_STATUS
    $FAILED_JOB_STATUS
    $OK_JOB_STATUS
);

use CTSMS::BulkProcessor::Projects::ETL::Inquiry qw(
    get_horizontal_cols
    get_category_map

);

use CTSMS::BulkProcessor::Projects::ETL::Import qw(
    get_input_filename
    get_importer

    mark_utf8
    sanitize_decimal
    
    valid_excel_to_date
    get_selection_set_value_ids
    is_unknown_value
    
    append_probandalias_criterion
    append_probandid_criterion
    
    get_values_stats
    
    get_proband_in
    
    init_context
    get_log_label
);

use CTSMS::BulkProcessor::Array qw(array_to_map contains);
use CTSMS::BulkProcessor::Utils qw( stringtobool trim chopstring );

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi_last_error
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    import_inquiry_data_horizontal
);

my @header_row :shared = ();
my $header_rownum :shared = 0;
my $registration :shared;
my $warning_count :shared = 0;
my $value_count :shared = 0;

my $comment_char = '#';

sub import_inquiry_data_horizontal {

    my ($file) = @_;

    {
        lock $warning_count;
        $warning_count = 0;
        lock $value_count;
        $value_count = 0;
    }

    my $static_context = {};
    my $result = _init_context($static_context);

    $file = get_input_filename($file,$inquiry_import_filename);
    
    if ($result) {
        my $importer = get_importer($static_context,$file,
            numofthreads => $import_inquiry_data_horizontal_numofthreads,
            blocksize => $import_inquiry_data_horizontal_blocksize);
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
                        update_job($PROCESSING_JOB_STATUS,$rownum,$row_offset + $import_inquiry_data_horizontal_blocksize);
                        next unless _set_inquiry_data_horizontal_context($context,$row,$rownum);
                        next unless _clear_inquiries($context);
                        next unless _set_inquiry_values_horizontal($context);
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
                multithreading => $import_inquiry_data_horizontal_multithreading,
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

    $context->{skip_errors} = $skip_errors;
    my $result = init_context($context);

    $context->{inquiry_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($inquiry_trial_id);
    if (not $context->{inquiry_trial}->{status}->{inquiryValueInputEnabled}) {
        rowprocessingerror($context->{tid},"inquiry input is disabled for this trial (trial status: $context->{inquiry_trial}->{status}->{name})",getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    } elsif ($context->{inquiry_trial}->locked) {
        rowprocessingerror($context->{tid},"trial is locked",getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }
    
    my ($keys,$values);

    eval {
        my ($person, $animal) = (undef, undef);
        $person = 1 if $context->{inquiry_trial}->{type}->{person};
        $animal = 1 unless $context->{inquiry_trial}->{type}->{person};
        ($context->{proband_category_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory::get_items($person, $animal),
            sub { my $item = shift; return $item->{nameL10nKey}; }, sub { my $item = shift; return $item; }, 'last');
        #$context->{proband_category} = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory::get_preset_item(0,1);
    };
    if ($@ or not keys %{$context->{proband_category_map}}) {
        rowprocessingerror($context->{tid},'error loading proband categories',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }
    
    $context->{category_map} = get_category_map($context);
    $context->{all_columns} = get_horizontal_cols($context, 1);

    ($context->{all_column_map}, $keys, $values) = array_to_map($context->{all_columns},
        sub { my $item = shift; return $item->{colname}; },undef,'first');

    return $result;
    
}

sub _set_inquiry_data_horizontal_context {

    my ($context,$row,$rownum) = @_;

    $context->{rownum} = $rownum;

    $context->{proband} = undef;

    my $result = 1;

    if (_init_horizontal_record($context,$row)) {
        $result = _register_proband($context);
    } else {
        $result = 0;
    }

    return $result;

}

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
        #my $columns_changed = 0;
        #my @ecrfvisit = ();

        #if ($columns_changed) {
        #    #$context->{listentrytag_map} = { %{$context->{all_listentrytag_map}} };
        #    $context->{all_columns} = get_horizontal_cols($context, 1);
        #    ($context->{all_column_map}, $keys, $values) = array_to_map($context->{all_columns},
        #        sub { my $item = shift; return $item->{colname}; },undef,'first');
        #    undef $context->{columns};
        #}
            
        unless ($context->{columns}) {
            %header = map { $_ => 1; } @headerrow; # if $initialized;
            
            my @columns = grep { exists $header{$_->{colname}}; } @{$context->{all_columns}}; # do not clone columns
    
            my %disabled_inquiry_map = ();
            my %sketch_inputfield_map = ();
            $context->{columns} = [];
            my $message;
            foreach my $column (@columns) {
                next if exists $disabled_inquiry_map{$column->{inquiry}->{id}};
                next if exists $sketch_inputfield_map{$column->{inquiry}->{field}->{id}};
                if ($column->{inquiry}->{disabled}) {
                    $message = "skipping disabled inquiry: $column->{inquiry}->{uniqueName}";
                    $disabled_inquiry_map{$column->{inquiry}->{id}} = $column->{inquiry};
                } elsif ($column->{inquiry}->{field}->{fieldType}->{type} eq $SKETCH) {
                    $message = "skipping sketch input field: $column->{inquiry}->{field}->{name}";
                    $sketch_inputfield_map{$column->{inquiry}->{field}->{id}} = $column->{inquiry}->{field};
                } else {
                    $message = "column '$column->{colname}' mapped to $column->{inquiry}->{uniqueName}";
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
                   and not contains($_,[ get_proband_columns() ])
                   and $_ ne 'proband_id'
                   ; } @headerrow) {
                map { _info($context,"ignoring column '$_'",1); } @unknown_colnames;
                _warn($context,"ignoring " . (scalar @unknown_colnames) . " columns - " . chopstring(join(', ', @unknown_colnames)));
            }
    
            ($context->{column_map}, $keys, $values) = array_to_map($context->{columns},
                sub { my $item = shift; return $item->{colname}; },undef,'first');
    
        }
    }

    return $initialized;

}

sub _set_inquiry_values_horizontal {

    my ($context) = @_;

    my $result = 1;

    undef $context->{in};
    $context->{skip_columns} = {};

    $context->{inquiry_value_stats} = {
        total => 0,
        created => 0,
        updated => 0,
    };

    foreach my $colname (map { $_->{colname}; } @{$context->{columns}}) {

        $result &= _append_inquiryvalue_in($context,$colname,$context->{record}->{$colname});

        # save next chunk if full unless it's a new index section:
        if ($inquiry_values_col_block > 0
            and (scalar @{$context->{in}}) >= $inquiry_values_col_block
            ) {
            $result &= _save_inquiry_values($context);
        }

    }

    $result &= _save_inquiry_values($context);

    _log_inquiry_values_count($context);

    return $result;

}

sub _clear_inquiries {

    my ($context) = @_;

    my $result = 1;
    my $proband_id = $context->{proband}->{id};
    my $trial_id = $context->{inquiry_trial}->{id};

    $context->{clear_map} = {};

    if (not $context->{proband_created}
        and ($clear_categories or $clear_all_categories)
        and not exists $context->{clear_map}->{$proband_id}) {
        my $columns = [];
        $columns = $context->{all_columns} if $clear_all_categories;
        $columns = $context->{columns} if $clear_categories;
        my $removed_value_count = 0;

        $context->{clear_map}->{$proband_id} = {};
        foreach my $column (@$columns) {
            my $category_map = $context->{clear_map}->{$proband_id};

            my $category = ($column->{inquiry}->{category} // '');
            unless (exists $category_map->{$category}) {
                my $values;
                my $category_label = "inquiry category '" . $category . "'";
                eval {
                    $values = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValue::clear($proband_id, $trial_id, $category);
                };
                if ($@) {
                    _warn_or_error($context,"error deleting $category_label values: " . $@);
                    $result = 0;
                } else {
                    _info($context,"$category_label values deleted",1);
                }
                $category_map->{$category} = $values;
                $removed_value_count += scalar @$values;
            }
        }
        _info($context,"$removed_value_count inquiry values deleted");
    }
    return $result;

}

sub _register_proband {

    my ($context) = @_;

    my $result = 1;

    $context->{proband_created} = 0;
    $context->{criterions} = [];
    my $alias;
    my $id;
    my %record = %{$context->{record}};
    if (length($inquiry_proband_alias_column_name) 
        and exists $context->{record}->{$inquiry_proband_alias_column_name}
        and length($context->{record}->{$inquiry_proband_alias_column_name})) {
        $alias = $context->{record}->{$inquiry_proband_alias_column_name};
    }
    if (exists $context->{record}->{proband_id}
        and length($context->{record}->{proband_id})) {
        # use proband_id column if specified and not empty:
        $id = $context->{record}->{proband_id};
        $result = append_probandid_criterion($context,$id);
        delete $record{proband_id};
    } elsif (defined $alias) {
        $result = append_probandalias_criterion($context,$alias,$inquiry_proband_department_column_name);
        delete $record{$inquiry_proband_department_column_name};
    }

    my @vals = map { $context->{record}->{$_->{colname}} } @{$context->{columns}};
    unless (scalar grep { defined($_) and length(trim($_)) > 0; } @vals) {
        $result = 0; #no inquiry data to save
    }
    
    if ($result) {
        if (scalar @{$context->{criterions}}) { # requires at least one proband list attribute of supported field type ...
            lock $registration;
            my $probands = undef;
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
                         my $in = get_proband_in($context,$alias,$inquiry_proband_category_column_name,$inquiry_proband_department_column_name,$inquiry_proband_gender_column_name);
                         $in->{"person"} = ($context->{inquiry_trial}->{type}->{person} ? \1 : \0);                        
                         $context->{proband} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::add_item($in);
                    };
                    if ($@) {
                        _warn_or_error($context,"error creating proband: " . $@);
                        $result = 0;
                    } else {
                        _info($context,"proband " . $context->{proband}->alias . " created");
                        #$proband_created = 1;
                        $context->{proband_created} = 1;
                    }
                } else {
                    _warn_or_error($context,"alias required to create proband");
                    $result = 0;
                }
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
            }

            if ($context->{proband} and $context->{proband}->locked) {
                _info($context,"proband is locked");
                return 0;
            }

        } else {
            _warn_or_error($context,"no criterion to load proband");
            $result = 0;
        }
    }

    return $result;
}

sub _get_inquiryvalue_in {
    my ($context,$colname,$value,$contains_code) = @_;

    return (undef,1) unless defined $value;
    
    my $proband_id = $context->{proband}->{id};

    my $column;
    $column = $context->{column_map}->{$colname} if $colname;

    if ($column) {

        my $inquiry = $column->{inquiry};
        
        return (undef, 1) if exists $context->{skip_columns}->{$colname};

        my $inquiry_id = $inquiry->{id};

        my %in = (
            inquiryId => $inquiry_id,
            probandId => $proband_id,
        );
        my $old_value = undef;
        unless ($clear_categories or $clear_all_categories) {
            eval {
                $old_value = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::get_item($proband_id, $inquiry_id)->{rows}->[0];
            };
            if ($@) {
                my $error_code = get_ctsms_restapi_last_error();
                _warn($context,"error loading old inquiry value: " . $@);
                return (undef,0);
            } elsif (defined $old_value) {
                if ($old_value->{id}) {
                    $in{id} = $old_value->{id};
                    $in{version} = $old_value->{version};
                } else {
                    # just a preset value ...
                }
            }
        }
        $value = mark_utf8($value);
        my $field_type = $inquiry->{field}->{fieldType}->{type};
        if ($inquiry->{field}->is_select() and $field_type ne $SKETCH) {
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
                             and not $inquiry->{field}->is_select_one()) {
                        $column = $context->{all_column_map}->{$_};
                        if (grep { $column->{selection_set_value}->{id} == $_->{id}; } @{$old_value->{selectionValues}}) {
                            $in{selectionValueIds} //= [];
                            push(@{$in{selectionValueIds}},$column->{selection_set_value}->{id});
                        }
                    }
                }
            } else {
                eval {
                    $in{selectionValueIds} = get_selection_set_value_ids($context,$inquiry->{field},$value,$contains_code,$selection_set_value_separator);
                };
                if ($@) {
                    _warn_or_error($context,$@);
                    return (undef,0);
                }
            }
        } elsif ($field_type eq $AUTOCOMPLETE) {
            $in{textValue} = (length($value) ? $value : undef);
        } elsif ($inquiry->{field}->is_text()) {
            $in{textValue} = (length($value) ? $value : '');
        } elsif ($field_type eq $CHECKBOX) {
            $in{booleanValue} = (stringtobool($value) ? \1 : \0);
        } elsif ($field_type eq $DATE) {
            $in{dateValue} = valid_excel_to_date($value);
            #$in{dateValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $TIME) {
            $in{timeValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $TIMESTAMP) {
            $in{timestampValue} = (length($value) ? $value : undef);
        } elsif ($field_type eq $INTEGER) {
            $in{longValue} = ((length($value) and not is_unknown_value($value)) ? $value : undef);
        } elsif ($field_type eq $FLOAT) {
            $in{floatValue} = ((length($value) and not is_unknown_value($value)) ? sanitize_decimal($value) : undef);
        } else {
            _warn_or_error($context,"unsupported inquiry field type '$field_type' ($inquiry->{field}->{name})");
            return (undef,0);
        }
        return (\%in,1);
    } else {
        _warn_or_error($context,"unknown inquiry field column '$colname'");
        return (undef,0);
    }
}

sub _append_inquiryvalue_in {
    my $context = shift;
    my $colname = shift;
    $context->{in} = [] unless $context->{in};
    my ($in,$result) = _get_inquiryvalue_in($context, $colname, @_);
    if ($in) {
        push(@{$context->{in}},$in);
        if ($result) {
            my $column = $context->{column_map}->{$colname};
        }
    }
    return $result;
}

sub _log_inquiry_values_count {

    my ($context) = @_;
    _info($context,$context->{inquiry_value_stats}->{total} . " inquiry values (" . $context->{inquiry_value_stats}->{created} . " created, " . $context->{inquiry_value_stats}->{updated} . " updated)");
    lock $value_count;
    $value_count += $context->{inquiry_value_stats}->{total};
    $context->{inquiry_value_stats} = {
        total => 0,
        created => 0,
        updated => 0,
    };

}

sub _save_inquiry_values {

    my ($context) = @_;
    my $result = 1;
    return $result unless scalar @{$context->{in}};
    my $out;
    eval {
        $out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::set_inquiryvalues($context->{in},undef,$timezone);
    };
    my $stats = get_values_stats($context,$out,sub {
            my $in_row = shift;
            return ($in_row->{probandId} . '-' . $in_row->{inquiryId});
        },sub {
            my $out_row = shift;
            return ($out_row->{proband}->{id} . '-' . $out_row->{inquiry}->{id});
        });
    $context->{in} = [];
    if ($@) {
        _warn_or_error($context,"error saving inquiry values: " . $@);
        $result = 0;
    } else {
        map { _info($context,$_->{inquiry}->{uniqueName} . ' saved',1); } @{$out->{rows}};
        _info($context, (scalar @{$out->{rows}}) . " inquiry values (" . $stats->{created} . " created, " . $stats->{updated} . " updated)",1);
        map { $context->{inquiry_value_stats}->{$_} += $stats->{$_}; } keys %$stats;
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
    rowprocessingerror($context->{tid},get_log_label($context) . $message,getlogger(__PACKAGE__));

}

sub _warn {

    my ($context,$message) = @_;
    $context->{warning_count} = $context->{warning_count} + 1;
    rowprocessingwarn($context->{tid},get_log_label($context) . $message,getlogger(__PACKAGE__));

}

sub _info {

    my ($context,$message,$debug) = @_;
    if ($debug) {
        processing_debug($context->{tid},get_log_label($context) . $message,getlogger(__PACKAGE__));
    } else {
        processing_info($context->{tid},get_log_label($context) . $message,getlogger(__PACKAGE__));
    }
}

1;
