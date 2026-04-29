package CTSMS::BulkProcessor::Projects::ETL::Import;
use strict;

use File::Basename qw();

use utf8;
use Encode qw();

use Tie::IxHash;

use CTSMS::BulkProcessor::Globals qw(
    $ctsmsrestapi_username
);

use CTSMS::BulkProcessor::FileProcessors::CSVFile qw();
use CTSMS::BulkProcessor::FileProcessors::XlsFileSimple qw();
use CTSMS::BulkProcessor::FileProcessors::XlsxFileSimple qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::user::UserService::User qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Sex qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Department qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule qw();

use CTSMS::BulkProcessor::Utils qw(threadid trim excel_to_date zerofill);
use CTSMS::BulkProcessor::Array qw(array_to_map contains);

use CTSMS::BulkProcessor::Projects::ETL::Job qw(
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

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
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

my @csvxextension = ('.csv', '.txt');
my @xlsextension = ('.xls');
my @xlsxextension = ('.xlsx');
#join('|',map { quotemeta($_) . '$'; } map { ($_, uc($_)); } (@csvxextension,@xlsextension,@xlsxextension))
my $rfileextensions = '\\.[a-zA-Z0-9_.-]+$';

my $rownum_digits = 3;

sub get_input_filename {

    my ($filename_opt,$filename_config) = @_;
    my $filename = $job_file[0];
    if (length($filename_opt)) {
        $filename = $filename_opt;
    } elsif (length($filename_config)) {
        $filename = $filename_config;
    }
    return $filename;

}

sub get_importer {

    my $context = shift;
    my $file = shift;
    rowprocessingerror($context->{tid},'no file specified',getlogger(__PACKAGE__)) unless length($file);
    my ($filename, $filedir, $filesuffix) = File::Basename::fileparse($file, $rfileextensions);
    return CTSMS::BulkProcessor::FileProcessors::CSVFile->new(@_) if contains($filesuffix,\@csvxextension,1); # CSVDB does not support multithread
    return CTSMS::BulkProcessor::FileProcessors::XlsFileSimple->new(@_) if contains($filesuffix,\@xlsextension,1);
    return CTSMS::BulkProcessor::FileProcessors::XlsxFileSimple->new(@_) if contains($filesuffix,\@xlsxextension,1);
    rowprocessingerror($context->{tid},"unsupported input file type '$filesuffix'",getlogger(__PACKAGE__));

}

sub mark_utf8 {
    my $byte_string = shift;
    my $ustring = $byte_string;
    eval {
        $ustring = Encode::decode('UTF-8',$byte_string,Encode::FB_CROAK);
    };
    return $ustring;
    #or die "Could not decode string: $@";
    #return Encode::decode("UTF-8", shift);
}

sub sanitize_decimal {

    my ($decimal) = @_;

    $decimal =~ s/\s+//g;
    $decimal =~ s/[,.]/./;
    return $decimal;

}

sub valid_excel_to_date {
    my $excel_date = trim(shift);
    my $date;
    eval {
        $date = excel_to_date($excel_date) if ($excel_date =~ /^\d+$/ and $excel_date > 3);
        $date .= ' 00:00:00' if $date;
    };
    return $date;
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

sub is_unknown_value {
    my $string = shift;
    #if ($string =~ /^[?x]+$/ or
    if ($string eq '#VALUE!') {
        return 1;
    }
    return 0;
}


sub get_selection_set_value_ids {

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
    $value = [ map { trim($_); } grep { length($_) and not is_unknown_value($_); } @$value ];
    my $selectionValueIds = [ map { $_->{id}; } grep { &$contains_code($_,$value); } @{$field->{selectionSetValues}} ];
    unless ((scalar @{$selectionValueIds}) == (scalar @$value)) {
        die("unknown value(s) '" . join(',',@$value) . "' for $field->{name}");
    }
    return $selectionValueIds;

}

sub append_probandalias_criterion {
    my ($context,$alias,$proband_department_column_name) = @_;
    if (length($alias)) {
        push(@{$context->{criterions}},{
            position => 1,
            #tieId => undef,
            restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
            propertyId => $context->{criterionproperty_map}->{'proband.personParticulars.alias'},
            stringValue => mark_utf8($alias),
        });
        push(@{$context->{criterions}},{
            position => 2,
            tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
            restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
            propertyId => $context->{criterionproperty_map}->{'proband.deferredDelete'},
            booleanValue => \0,
        });
        # if there is a department column, search for alias by department ...
        if (length($proband_department_column_name)
            and exists $context->{record}->{$proband_department_column_name}) {
            my $value = $context->{record}->{$proband_department_column_name};
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

sub append_probandid_criterion {
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

sub get_values_stats {
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



sub get_proband_in {
    my ($context,$alias,$proband_category_column_name,$proband_department_column_name,$proband_gender_column_name) = @_;

    my $category;
    if (length($proband_category_column_name)
        and exists $context->{record}->{$proband_category_column_name}) {
        my $value = $context->{record}->{$proband_category_column_name};
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
    if (length($proband_department_column_name)
        and exists $context->{record}->{$proband_department_column_name}) {
        my $value = $context->{record}->{$proband_department_column_name};
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
    if (length($proband_gender_column_name)
        and exists $context->{record}->{$proband_gender_column_name}) {
        $gender = $context->{record}->{$proband_gender_column_name};
    }
    $gender = $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Sex::NOT_KNOWN unless length($gender);

    my %in = (
        "categoryId" => $category->{id},
        #"person" => ($context->{inquiry_trial}->{type}->{person} ? \1 : \0),
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

sub init_context {

    my ($context) = @_;

    my $result = 1;

    $context->{tid} = threadid();
    
    my ($keys,$values);

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

    return $result;
}

sub _warn_or_error {
    my ($context,$message) = @_;
    if ($context->{skip_errors}) {
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

sub get_log_label {

    my ($context) = @_;
    my $label = "(line " . zerofill($context->{rownum},$rownum_digits);
    $label .= "/proband " . $context->{proband}->alias if $context->{proband};
    $label .= ") ";
    return $label;

}

1;
