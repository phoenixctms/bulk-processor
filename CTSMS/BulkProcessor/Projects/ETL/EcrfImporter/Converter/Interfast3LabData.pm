package Converter::Interfast3LabData;
use strict;

## no critic

use File::Basename qw(basename);
use Excel::Writer::XLSX;

use CTSMS::BulkProcessor::FileProcessors::CSVFileSimple qw();

use CTSMS::BulkProcessor::Projects::ETL::EcrfSettings qw(
    $ecrf_data_trial_id
    $output_path
    $skip_errors
);

use CTSMS::BulkProcessor::Projects::ETL::Ecrf qw(
    get_ecrf_map
    get_horizontal_cols
);

use CTSMS::BulkProcessor::Projects::ETL::Import qw(
    init_context
);

use CTSMS::BulkProcessor::Projects::ETL::Job qw(
    @job_file
);

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteEcrfField qw(
    complete_ecrf_field
);
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie qw(
    $AND
);
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction qw(
    $EQ
    $GE
);
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule qw(
    $PROBAND_DB
);

use CTSMS::BulkProcessor::SqlConnectors::CSVDB qw(
    sanitize_spreadsheet_name
    sanitize_column_name
);

use CTSMS::BulkProcessor::Utils qw(trim timestampdigits);
use CTSMS::BulkProcessor::Logging qw(
    getlogger
    processing_info
    scriptinfo
);
use CTSMS::BulkProcessor::LogError qw(
    rowprocessingerror
    rowprocessingwarn
    fileerror
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    convert
    process
);

my $xlsxextension = '.xlsx';
my $xlsxmimetype = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

my $lab_request_name_infix = '[Interfast3] lab request number';

# Interfast3 lab exports: metadata line, then header, then data. Separator is ';'.
# Qualifier columns KZ1/KZ2/VKZ repeat after each analyte — rename to <analyte>_KZ1 etc.

sub process {
    return convert(@_);
}

sub convert {
    my ($file) = @_;

    rowprocessingerror(undef,'no input file specified',getlogger(__PACKAGE__)) unless length($file);
    rowprocessingerror(undef,'trial id required',getlogger(__PACKAGE__))
        unless (defined $ecrf_data_trial_id and length($ecrf_data_trial_id));

    scriptinfo("Interfast3LabData: converting $file",getlogger(__PACKAGE__));

    my $static = _init_convert_context();
    my $outfile = $output_path . 'interfast3_lab_data_' . timestampdigits() . $xlsxextension;

    my $workbook = Excel::Writer::XLSX->new($outfile);
    unless ($workbook) {
        fileerror($!,getlogger(__PACKAGE__));
        return undef;
    }
    my $header_format = $workbook->add_format();
    $header_format->set_bold();

    $static->{workbook} = $workbook;
    $static->{header_format} = $header_format;
    $static->{outfile} = $outfile;

    my $header_found = 0;
    my $result = 1;

    my $processor = CTSMS::BulkProcessor::FileProcessors::CSVFileSimple->new(
        field_separator => ';',
        numofthreads => 1,
        blocksize => 50,
    );

    $result = $processor->process(
        file => $file,
        multithreading => 0,
        static_context => {
            %$static,
            header_found_ref => \$header_found,
            skip_errors => $skip_errors,
        },
        process_code => sub {
            my ($context,$rows,$row_offset) = @_;

            foreach my $row (@$rows) {
                next unless (scalar @$row);
                next unless (scalar grep { length(trim($_ // '')) > 0; } @$row);

                unless ($context->{colnames}) {
                    next unless _is_header_row($row);
                    my @colnames = _normalize_colnames($row);
                    $context->{colnames} = \@colnames;
                    ${$context->{header_found_ref}} = 1;
                    _create_lab_sheets($context,\@colnames);
                    processing_info($context->{tid},'CSV header with ' . (scalar @colnames) . ' column(s); lab sheets created',getlogger(__PACKAGE__));
                    next;
                }

                next unless _process_data_row($context,$row);
            }

            return 1;
        },
        init_process_context_code => sub {
            my ($context) = @_;
            $context->{colnames} = undef;
            $context->{error_count} = 0;
            $context->{warning_count} = 0;
        },
        uninit_process_context_code => sub {
        },
    );

    unless ($result and $header_found) {
        $workbook->close() if $workbook;
        unlink $outfile if length($outfile) and -f $outfile;
        rowprocessingerror(undef,'Interfast3LabData: no AnfoNr header row found in ' . $file,getlogger(__PACKAGE__))
            unless $header_found;
        return undef;
    }

    $workbook->close();
    @job_file = (
        $outfile,
        basename($outfile),
        $xlsxmimetype,
    );
    scriptinfo("Interfast3LabData: intermediate file $outfile",getlogger(__PACKAGE__));
    return $outfile;
}

sub _init_convert_context {
    my $context = {
        ecrf_data_trial => CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($ecrf_data_trial_id),
    };
    rowprocessingerror(undef,"error loading trial id $ecrf_data_trial_id",getlogger(__PACKAGE__))
        unless $context->{ecrf_data_trial};

    unless (init_context($context)) {
        rowprocessingerror(undef,'error initializing convert context',getlogger(__PACKAGE__));
    }

    $context->{ecrf_map} = get_ecrf_map($context,0);

    my @lab_ecrfs = ();
    my %lab_columns_by_name = ();
    foreach my $ecrfid (keys %{$context->{ecrf_map}}) {
        my $ecrf = $context->{ecrf_map}->{$ecrfid}->{ecrf};
        next unless (defined $ecrf->{name} and $ecrf->{name} =~ /lab/i);
        $context->{ecrf} = $ecrf;
        my $columns = get_horizontal_cols($context,0);
        my @prepared = ();
        foreach my $column (@$columns) {
            my $external_id = _external_id_of($column->{ecrffield});
            next unless length($external_id);
            push(@prepared,{
                colname => $column->{colname},
                external_id => $external_id,
                ecrffield => $column->{ecrffield},
            });
        }
        push(@lab_ecrfs,$ecrf);
        $lab_columns_by_name{$ecrf->{name}} = \@prepared;
        processing_info(undef,"lab eCRF '$ecrf->{name}': " . (scalar @prepared) . ' column(s) with externalId',getlogger(__PACKAGE__));
    }
    delete $context->{ecrf};
    $context->{lab_ecrfs} = \@lab_ecrfs;
    $context->{lab_columns_by_name} = \%lab_columns_by_name;

    rowprocessingerror(undef,'no eCRFs with "lab" in the name found for this trial',getlogger(__PACKAGE__))
        unless (scalar @lab_ecrfs);

    my $matches = complete_ecrf_field($lab_request_name_infix,20);
    $matches = [] unless (defined $matches and ref $matches eq 'ARRAY');
    my $lab_request_field = _pick_lab_request_field($matches);
    rowprocessingerror(undef,"no eCRF field found for nameInfix '$lab_request_name_infix'",getlogger(__PACKAGE__))
        unless $lab_request_field;
    $context->{lab_request_ecrffield_id} = $lab_request_field->{id} // $lab_request_field->{value};
    rowprocessingerror(undef,"complete ecrffield '$lab_request_name_infix' returned no id",getlogger(__PACKAGE__))
        unless length($context->{lab_request_ecrffield_id});
    scriptinfo("Interfast3LabData: lab request eCRF field id $context->{lab_request_ecrffield_id}",getlogger(__PACKAGE__));

    return $context;
}

sub _pick_lab_request_field {
    my ($matches) = @_;
    return undef unless (scalar @$matches);
    my $needle = lc($lab_request_name_infix);
    foreach my $item (@$matches) {
        foreach my $key (qw/uniqueName title titleL10nKey name label/) {
            if (defined $item->{$key} and lc($item->{$key}) eq $needle) {
                return $item;
            }
        }
    }
    return $matches->[0];
}

sub _external_id_of {
    my ($ecrffield) = @_;
    return undef unless $ecrffield;
    if (defined $ecrffield->{externalId} and length($ecrffield->{externalId})) {
        return $ecrffield->{externalId};
    }
    if (defined $ecrffield->{field} and defined $ecrffield->{field}->{externalId} and length($ecrffield->{field}->{externalId})) {
        return $ecrffield->{field}->{externalId};
    }
    return undef;
}

sub _create_lab_sheets {
    my ($context,$csv_colnames) = @_;

    my %csv_index_by_lc = ();
    for (my $i = 0; $i < scalar @$csv_colnames; $i++) {
        $csv_index_by_lc{lc($csv_colnames->[$i])} = $i;
    }

    $context->{sheets_by_name} = {};
    $context->{anfonr_index} = $csv_index_by_lc{lc('AnfoNr')};

    foreach my $ecrf (@{$context->{lab_ecrfs}}) {
        my $name = $ecrf->{name};
        my @header = ('proband_id');
        my @matched = ();
        foreach my $col (@{$context->{lab_columns_by_name}->{$name} // []}) {
            my $csv_index = $csv_index_by_lc{lc($col->{external_id})};
            next unless defined $csv_index;
            push(@header,$col->{colname});
            push(@matched,{
                colname => $col->{colname},
                csv_index => $csv_index,
                external_id => $col->{external_id},
            });
        }

        my $sheetname = sanitize_spreadsheet_name($name);
        my $worksheet = $context->{workbook}->add_worksheet($sheetname);
        for (my $c = 0; $c < scalar @header; $c++) {
            $worksheet->write_string(0,$c,$header[$c],$context->{header_format});
        }

        $context->{sheets_by_name}->{$name} = {
            worksheet => $worksheet,
            header => \@header,
            matched => \@matched,
            next_row => 1,
            ecrf => $ecrf,
        };
        processing_info($context->{tid},"sheet '$sheetname': " . (scalar @matched) . ' matched column(s)',getlogger(__PACKAGE__));
    }
}

sub _process_data_row {
    my ($context,$row) = @_;

    my $anfonr;
    if (defined $context->{anfonr_index}) {
        $anfonr = trim($row->[$context->{anfonr_index}] // '');
    }
    unless (length($anfonr)) {
        _warn_or_error($context,'skipping row without AnfoNr');
        return 0;
    }

    my $probands;
    eval {
        $probands = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::search({
            module => $PROBAND_DB,
            criterions => [{
                position => 1,
                restrictionId => $context->{criterionrestriction_map}->{$EQ},
                propertyId => $context->{criterionproperty_map}->{'proband.trialParticipations.ecrfValues.ecrfField.id'},
                longValue => $context->{lab_request_ecrffield_id},
            },{
                position => 2,
                tieId => $context->{criteriontie_map}->{$AND},
                restrictionId => $context->{criterionrestriction_map}->{$GE},
                propertyId => $context->{criterionproperty_map}->{'proband.trialParticipations.ecrfValues.value.stringValue'},
                floatValue => $anfonr,
            }],
        });
    };
    if ($@) {
        _warn_or_error($context,"AnfoNr $anfonr: error searching proband: $@");
        return 0;
    }
    $probands //= [];
    if ((scalar @$probands) == 0) {
        _warn_or_error($context,"AnfoNr $anfonr: no proband found");
        return 0;
    }
    if ((scalar @$probands) > 1) {
        _warn_or_error($context,"AnfoNr $anfonr: " . (scalar @$probands) . ' probands found, expected 1');
        return 0;
    }
    my $proband = $probands->[0];

    my $listentries;
    eval {
        $listentries = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::get_trial_list(
            $context->{ecrf_data_trial}->{id},undef,$proband->{id},1);
    };
    if ($@) {
        _warn_or_error($context,"AnfoNr $anfonr: error loading listentry: $@");
        return 0;
    }
    $listentries //= [];
    if ((scalar @$listentries) != 1) {
        _warn_or_error($context,"AnfoNr $anfonr: expected 1 listentry for proband $proband->{id}, got " . (scalar @$listentries));
        return 0;
    }
    my $listentry = $listentries->[0];

    my $ecrf_value;
    eval {
        my $values = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::get_item(
            $listentry->{id},undef,$context->{lab_request_ecrffield_id},undef);
        $ecrf_value = $values->{rows}->[0] if $values;
    };
    if ($@) {
        _warn_or_error($context,"AnfoNr $anfonr: error loading eCRF field value: $@");
        return 0;
    }
    unless ($ecrf_value and $ecrf_value->{ecrfField} and $ecrf_value->{ecrfField}->{ecrf}) {
        _warn_or_error($context,"AnfoNr $anfonr: no eCRF field value for lab request field");
        return 0;
    }

    my $source_ecrf_name = $ecrf_value->{ecrfField}->{ecrf}->{name};
    my $target_sheet_name = $source_ecrf_name . '_lab';
    my $sheet = $context->{sheets_by_name}->{$target_sheet_name};
    unless ($sheet) {
        _warn_or_error($context,"AnfoNr $anfonr: no lab sheet for eCRF '$source_ecrf_name' (expected '$target_sheet_name')");
        return 0;
    }

    my @out = ($proband->{id});
    foreach my $matched (@{$sheet->{matched}}) {
        push(@out,trim($row->[$matched->{csv_index}] // ''));
    }

    my $r = $sheet->{next_row};
    for (my $c = 0; $c < scalar @out; $c++) {
        my $val = $out[$c];
        if (defined $val and length($val)) {
            $sheet->{worksheet}->write_string($r,$c,$val);
        } else {
            $sheet->{worksheet}->write_blank($r,$c);
        }
    }
    $sheet->{next_row} = $r + 1;
    return 1;
}

sub _warn_or_error {
    my ($context,$message) = @_;
    if ($context->{skip_errors}) {
        $context->{warning_count} = ($context->{warning_count} // 0) + 1;
        rowprocessingwarn($context->{tid},$message,getlogger(__PACKAGE__));
    } else {
        $context->{error_count} = ($context->{error_count} // 0) + 1;
        rowprocessingerror($context->{tid},$message,getlogger(__PACKAGE__));
    }
}

sub _is_header_row {
    my ($row) = @_;
    return (trim($row->[0] // '') =~ /^AnfoNr$/i) ? 1 : 0;
}

sub _normalize_colnames {
    my ($header) = @_;
    my @colnames = ();
    my %seen = ();
    my $last_analyte;

    foreach my $raw (@$header) {
        my $name = trim($raw // '');
        $name = 'col' unless length($name);

        if ($name =~ /^(KZ[12]|VKZ)$/i and length($last_analyte)) {
            $name = $last_analyte . '_' . $name;
        } elsif ($name !~ /^(KZ[12]|VKZ)$/i) {
            $last_analyte = $name;
        }

        $name = sanitize_column_name($name);

        my $base = $name;
        my $n = 1;
        while (exists $seen{lc($name)}) {
            $n++;
            $name = $base . '_' . $n;
        }
        $seen{lc($name)} = 1;
        push(@colnames,$name);
    }

    return @colnames;
}

1;
