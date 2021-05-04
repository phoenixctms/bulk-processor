package CTSMS::BulkProcessor::Projects::ETL::Criteria::Process;
use strict;

## no critic

use threads::shared qw();

use Tie::IxHash;

use Excel::Writer::XLSX qw();

use Encode qw();

use CTSMS::BulkProcessor::Projects::ETL::Criteria::Settings qw(
    $skip_errors
    $dry
    $output_path

    $export_criteria_page_size
    $criteria_export_xlsx_filename

    $criteria_import_xlsx_filename

);

use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
    processing_debug
);
use CTSMS::BulkProcessor::LogError qw(
    fileerror
    rowprocessingwarn
    rowprocessingerror
);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty qw(
    $NONE
    $LONG
    $LONG_HASH
    $FLOAT
    $FLOAT_HASH
    $STRING
    $STRING_HASH
    $BOOLEAN
    $BOOLEAN_HASH
    $DATE
    $DATE_HASH
    $TIME
    $TIME_HASH
    $TIMESTAMP
    $TIMESTAMP_HASH
);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule qw(@DB_MODULES);

use CTSMS::BulkProcessor::Array qw(array_to_map);

use CTSMS::BulkProcessor::Utils qw(threadid timestampdigits booltostring stringtobool);

use CTSMS::BulkProcessor::FileProcessors::XlsxFileSimple qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    export_criteria
    import_criteria
);

my $xlsxextension = '.xlsx';
my $comment_char = '#';

### export:
my %criteria_out_to_excel_map = ();
tie(%criteria_out_to_excel_map, 'Tie::IxHash',
    "id" => sub { my ($criteria_out) = @_; return $criteria_out->{id}; },
    "category" => sub { my ($criteria_out) = @_; return $criteria_out->{category}; },
    "label" => sub { my ($criteria_out) = @_; return $criteria_out->{label}; },
    "comment" => sub { my ($criteria_out) = @_; return $criteria_out->{comment}; },
    "loadByDefault" => sub { my ($criteria_out) = @_; return booltostring($criteria_out->{loadByDefault}); },
    "version" => sub { my ($criteria_out) = @_; return $criteria_out->{version}; },
);
my %criterion_out_to_excel_map = ();
tie(%criterion_out_to_excel_map, 'Tie::IxHash',
    "criteriaId" => sub { my ($criteria_out,$criterion_out) = @_; return $criteria_out->{id}; },
    "position" => sub { my ($criteria_out,$criterion_out) = @_; return $criterion_out->{position}; },
    "tie" => sub { my ($criteria_out,$criterion_out) = @_;
        my $tie = $criterion_out->{tie};
        return (defined $tie ? $tie->{nameL10nKey} : undef);
    },
    "property" => sub { my ($criteria_out,$criterion_out) = @_;
        my $property = $criterion_out->{property};
        return (defined $property ? $property->{nameL10nKey} : undef);
    },
    "restriction" => => sub { my ($criteria_out,$criterion_out) = @_;
        my $restriction = $criterion_out->{restriction};
        return (defined $restriction ? $restriction->{nameL10nKey} : undef);
    },
    "value" => sub { my ($criteria_out,$criterion_out) = @_;
        my $property = $criterion_out->{property};
        if ($property) {
            my $value_type = $property->{valueType};
            if ($value_type) {
                if ($value_type eq $LONG or $value_type eq $LONG_HASH) {
                    return $criterion_out->{longValue};
                } elsif ($value_type eq $FLOAT or $value_type eq $FLOAT_HASH) {
                    return $criterion_out->{floatValue};
                } elsif ($value_type eq $STRING or $value_type eq $STRING_HASH) {
                    return $criterion_out->{stringValue};
                } elsif ($value_type eq $BOOLEAN or $value_type eq $BOOLEAN_HASH) {
                    return booltostring($criterion_out->{booleanValue});
                } elsif ($value_type eq $DATE or $value_type eq $DATE_HASH) {
                    return $criterion_out->{dateValue};
                } elsif ($value_type eq $TIME or $value_type eq $TIME_HASH) {
                    return $criterion_out->{timeValue};
                } elsif ($value_type eq $TIMESTAMP or $value_type eq $TIMESTAMP_HASH) {
                    return $criterion_out->{timestampValue};


                }
            }
        }
    },
);

#### import:
sub _get_criteria_in {
    my ($context,$row,$criterion_map) = @_;
    _warn_or_error($context,"empty criteria id at row $context->{rownum} in spreadsheet '$context->{spread_sheet}'") unless $row->[0];
    my $update = ((not $context->{create_all} and length($row->[5])) > 0 ? 1 : 0);
    return ($update,{
        "module" => $context->{module},
        "id" => ($update ? $row->[0] : undef),
        "category" => (length($row->[1]) > 0 ? $row->[1] : undef),
        "label" => $row->[2],
        "comment" => $row->[3],
        "loadByDefault" => (stringtobool($row->[4]) ? \1 : \0),
        "version" => ($update ? $row->[5] : 0),
        "criterions" => (defined $row->[0] ? $criterion_map->{$row->[0]} // [] : []),
    });
}

sub _get_criterion_in {
    my ($context,$row) = @_;
    _warn_or_error($context,"empty criteria id at row $context->{rownum} in spreadsheet '$context->{spread_sheet}'") unless $row->[0];
    my $tie = (length($row->[2]) > 0 ? $context->{criteriontie_map}->{$row->[2]} : undef);
    my $property = (length($row->[3]) > 0 ? $context->{criterionproperty_map}->{$context->{module}}->{$row->[3]} : undef);
    my $restriction = (length($row->[4]) > 0 ? $context->{criterionrestriction_map}->{$row->[4]} : undef);
    my %in = (
        position => $row->[1],
        tieId => (defined $tie ? $tie->{id} : undef),
        propertyId => (defined $property ? $property->{id} : undef),
        restrictionId => (defined $restriction ? $restriction->{id} : undef),
    );
    if ($property) {
        my $value_type = $property->{valueType};
        if ($value_type) {
            my $val = $row->[5];
            if ($value_type eq $LONG or $value_type eq $LONG_HASH) {
                $in{'longValue'} = $val;
            } elsif ($value_type eq $FLOAT or $value_type eq $FLOAT_HASH) {
                $in{ 'floatValue'} = $val;
            } elsif ($value_type eq $STRING or $value_type eq $STRING_HASH) {
                $in{ 'stringValue'} = $val;
            } elsif ($value_type eq $BOOLEAN or $value_type eq $BOOLEAN_HASH) {
                $in{ 'booleanValue'} = (stringtobool($val) ? \1 : \0);
            } elsif ($value_type eq $DATE or $value_type eq $DATE_HASH) {
                $in{ 'dateValue'} = $val;
            } elsif ($value_type eq $TIME or $value_type eq $TIME_HASH) {
                $in{ 'timeValue'} = $val;
            } elsif ($value_type eq $TIMESTAMP or $value_type eq $TIMESTAMP_HASH) {
                $in{ 'timestampValue'} = $val;


            }
        }
    }
    return ($row->[0],\%in);
}

my $criteria_sheetname_format = '%s_criteria';
my $criterion_sheetname_format = '%s_criterion';

sub export_criteria {

    my $static_context = {};
    my $result = _init_export_criteria_context($static_context);

    my $warning_count = 0;
    my $criteria_count = 0;
    foreach my $module (map { CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_module($_); } @DB_MODULES) {
        $result &= CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::process_items(
            static_context => $static_context,
            module => $module,
            process_code => sub {
                my ($context,$items,$row_offset) = @_;
                my $rownum = $row_offset;
                my @rows = ();
                foreach my $criteria (@$items) {
                    $rownum++;
                    my $col = 0;
                    foreach my $colname (keys %criteria_out_to_excel_map) {
                        my $cell_value = &{$criteria_out_to_excel_map{$colname}}($criteria);
                        $context->{criteria_worksheet}->write_blank( $context->{criteria_row}, $col, $context->{cell_format} ) unless defined $cell_value;

                        $context->{criteria_worksheet}->write_string($context->{criteria_row}, $col, (($criteria->{deferredDelete} and $col == 0) ? $comment_char : '') . $cell_value,$context->{cell_format}) if defined $cell_value;
                        $col++;
                    }
                    $context->{criteria_row} += 1;
                    if (defined $criteria->{criterions} and (scalar @{$criteria->{criterions}}) > 0) {
                        $context->{criterion_row} += 1;
                        foreach my $criterion (sort { $a->{position} <=> $b->{position} } @{$criteria->{criterions}}) {
                            $col = 0;
                            foreach my $colname (keys %criterion_out_to_excel_map) {
                                my $cell_value = &{$criterion_out_to_excel_map{$colname}}($criteria,$criterion);
                                $context->{criterion_worksheet}->write_blank( $context->{criterion_row}, $col, $context->{cell_format} ) unless defined $cell_value;

                                $context->{criterion_worksheet}->write_string($context->{criterion_row}, $col, (($criteria->{deferredDelete} and $col == 0) ? $comment_char : '') . $cell_value,$context->{cell_format}) if defined $cell_value;
                                $col++;
                            }
                            $context->{criterion_row} += 1;
                        }
                    }
                    $criteria_count++;
                }
                return 1;
            },
            init_process_context_code => sub {
                my ($context)= @_;

                $context->{error_count} = 0;
                $context->{warning_count} = 0;

                my $col = 0;
                $context->{criteria_worksheet} = $context->{workbook}->add_worksheet(sprintf($criteria_sheetname_format,$module));
                $context->{criteria_row} = 0;
                foreach my $colname (keys %criteria_out_to_excel_map) {
                    $context->{criteria_worksheet}->write_string($context->{criteria_row}, $col, ($col > 0 ? '' : $comment_char) . $colname, $context->{header_format});
                    $col++;
                }
                $context->{criteria_row} += 1;

                $col = 0;
                $context->{criterion_worksheet} = $context->{workbook}->add_worksheet(sprintf($criterion_sheetname_format,$module));
                $context->{criterion_row} = 0;
                foreach my $colname (keys %criterion_out_to_excel_map) {
                    $context->{criterion_worksheet}->write_string($context->{criterion_row}, $col, ($col > 0 ? '' : $comment_char) . $colname, $context->{header_format});
                    $col++;
                }
                $context->{criterion_row} += 1;

            },
            uninit_process_context_code => sub {
                my ($context)= @_;
                $warning_count += $context->{warning_count};
                processing_info(undef,"$module criteria exported",getlogger(__PACKAGE__));
            },
            blocksize => $export_criteria_page_size,
            load_recursive => 0,
            multithreading => 0,

        ) if $result;
    }
    $static_context->{workbook}->close() if $static_context->{workbook};
    return ($result,$warning_count,$criteria_count,$static_context->{filename});

}

sub _init_export_criteria_context {
    my ($context) = @_;

    my $result;

    $context->{tid} = threadid();

    $context->{filename} = $output_path . sprintf($criteria_export_xlsx_filename,timestampdigits(),$xlsxextension);

    if ($context->{workbook} = Excel::Writer::XLSX->new($context->{filename})) {

        $context->{header_format} = $context->{workbook}->add_format();
        $context->{header_format}->set_bold();

        $context->{cell_format} = undef;

        processing_info(undef,"workbook '$context->{filename}' created",getlogger(__PACKAGE__));
        $result = 1;
    } else {
        fileerror($!, getlogger(__PACKAGE__));
        $result = 0;
    }

    return $result;
}

sub import_criteria {

    my ($create_all) = @_;
    my $static_context = { create_all => $create_all, };
    my $result = _init_import_criteria_context($static_context);

    my $importer = CTSMS::BulkProcessor::FileProcessors::XlsxFileSimple->new();

    my $warning_count = 0;
    my $updated_count = 0;
    my $added_count = 0;
    foreach my $module (@DB_MODULES) {

        $static_context->{module} = $module;
        my $criterion_map = {};

        if ($importer->process(
            file => $criteria_import_xlsx_filename,
            static_context => $static_context,
            sheet_name => sprintf($criterion_sheetname_format,CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_module($module)),
            process_code => sub {
                my ($context,$rows,$row_offset) = @_;
                my $rownum = $row_offset;
                foreach my $row (@$rows) {
                    $rownum++;
                    $context->{rownum} = $rownum;
                    next if (scalar @$row) == 0 or (scalar @$row) == 1;

                    next if substr($row->[0],0,length($comment_char)) eq $comment_char;

                    my ($criteria_id,$criterion_in) = _get_criterion_in($context,$row);
                    next unless $criteria_id;

                    if (not exists $criterion_map->{$criteria_id}) {
                        $criterion_map->{$criteria_id} = [];
                    }
                    push(@{$criterion_map->{$criteria_id}},$criterion_in);

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
                $warning_count += $context->{warning_count};
                processing_debug(undef,"$context->{sheet_name} imported",getlogger(__PACKAGE__));
            },
            skip_errors => 1,
        )) {

            unless ($importer->process(
                file => $criteria_import_xlsx_filename,
                static_context => $static_context,
                sheet_name => sprintf($criteria_sheetname_format,CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_module($module)),
                process_code => sub {
                    my ($context,$rows,$row_offset) = @_;
                    my $rownum = $row_offset;
                    foreach my $row (@$rows) {
                        $rownum++;
                        $context->{rownum} = $rownum;
                        next if (scalar @$row) == 0 or (scalar @$row) == 1;

                        next if substr($row->[0],0,length($comment_char)) eq $comment_char;

                        my ($update,$criteria_in) = _get_criteria_in($context,$row,$criterion_map);

                        my $criteria_out;
                        if ($dry) {
                            if ($update) {
                                eval {
                                    $criteria_out = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_item($criteria_in->{id});
                                };
                                if ($@) {
                                    _warn_or_error($context,"fetching criteria '$criteria_in->{label}' (id $criteria_in->{id}) failed");
                                    $result = 0;
                                } else {
                                    _info($context,"criteria id $criteria_out->{id} fetched",1);
                                }
                            } else {
                                _info($context,"fetching criteria id $criteria_out->{id} skipped",1);
                            }
                        } elsif ($update) {
                            eval {
                                $criteria_out = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::update_item($criteria_in);
                            };
                            if ($@) {
                                _warn_or_error($context,"updating criteria '$criteria_in->{label}' (id $criteria_in->{id}) failed");
                                $result = 0;
                            } else {
                                _info($context,"criteria id $criteria_out->{id} updated",1);
                                $updated_count++;
                            }
                        } else {
                            eval {
                                $criteria_out = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::add_item($criteria_in);
                            };
                            if ($@) {
                                _warn_or_error($context,"adding criteria '$criteria_in->{label}' failed");
                                $result = 0;
                            } else {
                                _info($context,"criteria id $criteria_out->{id} added",1);
                                $added_count++;
                            }
                        }

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
                    $warning_count += $context->{warning_count};
                    processing_info(undef,"$context->{sheet_name} imported",getlogger(__PACKAGE__));
                },
                skip_errors => 1,
            )) {
                $result = 0;
            }
        } else {
            $result = 0;
        }

    }
    return ($result,$warning_count,$updated_count,$added_count);

}

sub _init_import_criteria_context {
    my ($context) = @_;

    my $result = 1;

    $context->{tid} = threadid();

    eval {
        my ($keys,$values);
        ($context->{criteriontie_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item; },'last');
        ($context->{criterionrestriction_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item; },'last');
        $context->{criterionproperty_map} = {};
        foreach my $module (@DB_MODULES) {
            ($context->{criterionproperty_map}->{$module}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty::get_items(
                $module),
                sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item; },'last');
        }
    };
    if ($@) {
        rowprocessingerror($context->{tid},'error loading criteria building blocks',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
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
    rowprocessingerror($context->{tid},$message,getlogger(__PACKAGE__));

}

sub _warn {

    my ($context,$message) = @_;
    $context->{warning_count} = $context->{warning_count} + 1;
    rowprocessingwarn($context->{tid},$message,getlogger(__PACKAGE__));

}

sub _info {

    my ($context,$message,$debug) = @_;
    if ($debug) {
        processing_debug($context->{tid},$message,getlogger(__PACKAGE__));
    } else {
        processing_info($context->{tid},$message,getlogger(__PACKAGE__));
    }
}

1;
