package CTSMS::BulkProcessor::Projects::ETL::Remoc::Entry;
use strict;

## no critic

use threads::shared qw();

#use DateTime::TimeZone qw();
use DateTime::Format::ISO8601 qw();
#use CTSMS::BulkProcessor::FakeTime qw();

use CTSMS::BulkProcessor::Projects::ETL::Settings qw(
    
    $skip_errors

);
use CTSMS::BulkProcessor::Projects::ETL::Remoc::Settings qw(
    
    $dialysis_substitution_volume_ecrf_id
    $dialysis_substitution_volume_clear_ecrf
    $dialysis_substitution_volume_probandlistentrytag_id
    $dialysis_substitution_volume_ecrffield_externalid_pattern
    $dialysis_substitution_volume_mapping

);
#$dry

use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
    processing_debug
);
use CTSMS::BulkProcessor::LogError qw(
    rowprocessingerror
    rowprocessingwarn
);

use CTSMS::BulkProcessor::Projects::ETL::Remoc::Dao::DialysisSubstitutionVolume qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValue qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::VisitScheduleItem qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTag qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty qw();

#use CTSMS::BulkProcessor::ConnectorPool qw(
#    get_ctsms_restapi
#);

use CTSMS::BulkProcessor::Projects::ETL::ProjectConnectorPool qw(
    destroy_all_dbs
);

use CTSMS::BulkProcessor::Array qw(array_to_map);
use CTSMS::BulkProcessor::Utils qw(threadid); #create_uuid

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    entry_dialysis_substitution_volume
);

my $NO_VISIT_ID = -1;

sub entry_dialysis_substitution_volume {

    my $static_context = {};
    my $result = _dialysis_substitution_volume_checks($static_context);

    #destroy_all_dbs();
    my $warning_count = 0;
    #my $updated_password_count :shared = 0;
    $result = CTSMS::BulkProcessor::Projects::ETL::Remoc::Dao::DialysisSubstitutionVolume::process_records(
        static_context => $static_context,
        process_code => sub {
            my ($context,$records,$row_offset) = @_;
            my $rownum = $row_offset;
            foreach my $record (@$records) {
                $rownum++;
                next unless _set_dialysis_substitution_volume_context($context,$record,$rownum);
                next unless _delete_dialysis_substitution_volume($context,$record,$rownum);
                next unless _entry_dialysis_substitution_volume($context,$record,$rownum);
            }

            #return 0;
            return 1;
        },
        init_process_context_code => sub {
            my ($context)= @_;
            #$context->{api} = &get_ctsms_restapi();
            $context->{error_count} = 0;
            $context->{warning_count} = 0;
            $context->{clear_map} = {};
            #$context->{updated_password_count} = 0;
            # below is not mandatory..
            #_check_insert_tables();
        },
        uninit_process_context_code => sub {
            my ($context)= @_;
            #undef $context->{api};
            #destroy_all_dbs();
            #{
            #    lock $warning_count;
                $warning_count += $context->{warning_count};
                #$updated_password_count += $context->{updated_password_count};
            #}
        },
        load_recursive => 0,
        'sort' => 1,
        multithreading => 0,
        numofthreads => 0,
    ) if $result;
    return ($result,$warning_count);
}

sub _delete_dialysis_substitution_volume {
    my ($context,$record,$rownum) = @_;

    my $result = 1;
    my $listentry_id = $context->{probandlistentry}->{id};
    
    if ($dialysis_substitution_volume_clear_ecrf and not exists $context->{clear_map}->{$listentry_id}) {
        eval {
            $context->{clear_map}->{$listentry_id} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValue::clear($listentry_id, $context->{dialysis_substitution_volume_ecrf}->{id});
        };
        if ($@) {
            _warn_or_error($context,"$context->{rownum}: error deleting eCRF values: " . $@);
            $result = 0;
        } else {
            _info($context,"$context->{rownum}: " . (scalar @{$context->{clear_map}->{$listentry_id}}) . " eCRF values deleted");
        }
    }
    return $result;
    
}

sub _entry_dialysis_substitution_volume {
    my ($context,$record,$rownum) = @_;

    my $result = 1;
    my $index = $record->{row_id} - 1;
    my $visit_id = (defined $context->{visit} ? $context->{visit}->{id} : $NO_VISIT_ID);
    my $listentry_id = $context->{probandlistentry}->{id};
    
    my @in = ();
    foreach my $external_id (keys %$dialysis_substitution_volume_mapping) {
        my $ecrffield_id = $context->{ecrffields_map}->{$external_id}->{$visit_id}->{id};
        unless (defined $ecrffield_id) {
            _warn($context,"$context->{rownum}: no eCRF field '$external_id'" . (defined $context->{visit} ? " for visit '$context->{visit}->{token}'" : ''));
            #$result = 0;
            $ecrffield_id = $context->{ecrffields_map}->{$external_id}->{$NO_VISIT_ID}->{id};
            unless (defined $ecrffield_id) {
                _warn_or_error($context,"$context->{rownum}: no eCRF field '$external_id'");
                $result = 0;
                next;
            }
        }
        my $old_value = undef;
        unless ($dialysis_substitution_volume_clear_ecrf) {
            eval {
                $old_value = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::get_item($listentry_id, $ecrffield_id, $index)->{rows}->[0];
            };
            if ($@) {
                _warn_or_error($context,"$context->{rownum}: error loading old value: " . $@);
                $result = 0;
            }
        }
        push(@in,{
            (defined $old_value ? (
                id => $old_value->{id},
                version => $old_value->{version},
                #reasonForChange => 'import',
            ) : ()),
            ecrfFieldId => $ecrffield_id,
            index => $index,
            listEntryId => $listentry_id,
            $dialysis_substitution_volume_mapping->{$external_id}->{type} => $record->{$dialysis_substitution_volume_mapping->{$external_id}->{field}},
        });
    }
    my $out;
    eval {
        $out = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues::set_ecrffieldvalues(\@in);
    };
    if ($@) {
        _warn_or_error($context,"$context->{rownum}: error saving eCRF values: " . $@);
        $result = 0;
    } else {
        _info($context,"$context->{rownum}: " . (scalar @{$out->{rows}}) . " eCRF values saved");
    }

    return $result;

}

sub _dialysis_substitution_volume_checks {
    my ($context) = @_;

    my $result = 1;
    eval {
        $context->{dialysis_substitution_volume_ecrf} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf::get_item($dialysis_substitution_volume_ecrf_id);
    };
    if ($@) {
        rowprocessingerror(undef,'error loading eCRF ID ' . $dialysis_substitution_volume_ecrf_id,getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    } 

    my $dialysis_substitution_volume_count = 0;
    eval {
        $dialysis_substitution_volume_count = CTSMS::BulkProcessor::Projects::ETL::Remoc::Dao::DialysisSubstitutionVolume::countby_filename();
    };
    if ($@ or $dialysis_substitution_volume_count == 0) {
        rowprocessingerror(undef,'please import dialysis substitution volume first',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }    

    eval {
        my ($keys,$values);
        ($context->{criteriontie_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
        ($context->{criterionrestriction_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
        ($context->{criterionproperty_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty::get_items(
            $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty::PROBAND_DB),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
    };
    if ($@) {
        rowprocessingerror(undef,'error loading criteria building blocks',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }
    
    eval {
        $context->{probandlistentrytag} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTag::get_item($dialysis_substitution_volume_probandlistentrytag_id);
    };
    if ($@ or not defined $context->{probandlistentrytag}) {
        rowprocessingerror(undef,'error loading probandlistentrytag',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }     

    my $p = {};
    my $ecrffields;
    eval {
        $ecrffields = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_trial_list(
            #$trial_id,$ecrf_id,$section,$p,$sf,$load_recursive
            $context->{dialysis_substitution_volume_ecrf}->{trial}->{id},$context->{dialysis_substitution_volume_ecrf}->{id},0,$p,{ externalId => $dialysis_substitution_volume_ecrffield_externalid_pattern }); #,undef,$dialysis_substitution_volume_ecrf_section);
    };
    if ($@ or not defined $ecrffields or (scalar @$ecrffields) == 0) {
        rowprocessingerror(undef,'error loading eCRF fields',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    } else {
        my $fields;
        ($context->{ecrffields_map}, my $external_ids, $fields) = array_to_map($ecrffields,sub { my $item = shift; return $item->{externalId}; },undef,'group');
        foreach my $external_id (keys %{$context->{ecrffields_map}}) {
            ($context->{ecrffields_map}->{$external_id}, my $visit_ids, $fields) = array_to_map($context->{ecrffields_map}->{$external_id},
                sub { my $item = shift; return (defined $item->{ecrf}->{visit} ? $item->{ecrf}->{visit}->{id} : $NO_VISIT_ID); },undef,'last');
            
        }
        foreach my $external_id (keys %$dialysis_substitution_volume_mapping) {
            unless (exists $context->{ecrffields_map}->{$external_id}) {
                rowprocessingerror(undef,"no eCRF field for mapping '$external_id'",getlogger(__PACKAGE__));
                $result = 0; #even in skip-error mode..
                last;
            }
        }
    }

    return $result;
}

sub _set_dialysis_substitution_volume_context {

    my ($context,$record,$rownum) = @_;

    my $result = 1;

    $context->{rownum} = $rownum;

    #'TreatmentDate',
    #'TreatmentID',
    #'EffectiveDiaTime',
    $context->{treatment_date} = undef;
    $context->{visit} = undef;
    my $visitscheduleitems = undef;
    eval {
        my $from_dt;
        $from_dt = _datetime_from_string($record->{TreatmentDate});
        #$context->{treatment_date} = _datetime_to_string($from_dt);;
        my $from = _datetime_to_string($from_dt);
        my $to_dt = $from_dt->clone->add(seconds => 1);
        my $to = _datetime_to_string($to_dt);
        $visitscheduleitems = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::VisitScheduleItem::get_interval(
            #$trial_id,$ecrf_id,$section,$p,$sf,$load_recursive
            $context->{dialysis_substitution_volume_ecrf}->{trial}->{id},$from,$to,0); #,undef,$dialysis_substitution_volume_ecrf_section);
    };
    if ($@) {
        _warn_or_error($context,"$context->{rownum}: error loading visit schedule items: " . $@);
        $result = 0;
    } else {
        my %visits = ();
        foreach my $visitscheduleitem (@$visitscheduleitems) {
            $visits{$visitscheduleitem->{visit}->{id}} = $visitscheduleitem->{visit} if defined $visitscheduleitem->{visit};
        }
        if ((scalar keys %visits) == 0) {
            _warn($context,"$context->{rownum}: no visit at date $context->{treatment_date}");
            #$result = 0;
        } elsif ((scalar keys %visits) > 1) {
            _warn_or_error($context,"$context->{rownum}: more than one visit at date $context->{treatment_date}");
            $result = 0;
        } else {
            $context->{visit} = [ values %visits ]->[0];
        }
    }

    $context->{probandlistentry} = undef;
    my $probands = undef;
    eval {
        $probands = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::search({
            module => $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty::PROBAND_DB,
            criterions => [{
                position => 1,
                tieId => undef,
                restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
                propertyId => $context->{criterionproperty_map}->{'proband.trialParticipations.tagValues.tag.id'},
                longValue => $context->{probandlistentrytag}->{id}, #5951379
            },{
                position => 2,
                tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
                restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
                propertyId => $context->{criterionproperty_map}->{'proband.trialParticipations.tagValues.value.stringValue'},
                stringValue => 123
            }],
        });
    };
    if ($@) {
        _warn_or_error($context,"$context->{rownum}: error loading proband: " . $@);
        $result = 0;
    } elsif ((scalar @$probands) == 0) {
        _warn_or_error($context,"$context->{rownum}: no proband found");
        $result = 0;
    } elsif ((scalar @$probands) > 1) {
        _warn_or_error($context,"$context->{rownum}: more than one proband found");
        $result = 0;
    } else {
        my $proband = $probands->[0];
        my $probandlistentries = undef;
        eval {
            $probandlistentries = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::get_trial_list($context->{dialysis_substitution_volume_ecrf}->{trial}->{id},
                undef,$proband->{id},1);
        };
        if ($@) {
            _warn_or_error($context,"$context->{rownum}: error loading probandlistentry: " . $@);
            $result = 0;
        } elsif ((scalar @$probandlistentries) == 0) {
            _warn_or_error($context,"$context->{rownum}: no probandlistentry found");
            $result = 0;
        } elsif ((scalar @$probandlistentries) > 1) {
            _warn_or_error($context,"$context->{rownum}: more than one probandlistentry found");
            $result = 0;
        } else {
            $context->{probandlistentry} = $probandlistentries->[0];
        }
    }
    
    return $result;

}

sub _datetime_to_string {
	my ($dt) = @_;
	return unless defined ($dt);
	my $s = $dt->ymd('-') . ' ' . $dt->hms(':');
	$s .= '.'.$dt->millisecond if $dt->millisecond > 0.0;
	return $s;
}

sub _datetime_from_string {
	my $s = shift;
	$s =~ s/^(\d{4}\-\d{2}\-\d{2})\s+(\d.+)$/$1T$2/;
	my $ts = DateTime::Format::ISO8601->parse_datetime($s);
	#$ts->set_time_zone( DateTime::TimeZone->new(name => 'local') );
	return $ts;
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
