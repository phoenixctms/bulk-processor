package CTSMS::BulkProcessor::Projects::ETL::Duplicates::Process;
use strict;

## no critic

use threads::shared qw();

use Unicode::Normalize qw();





use Encode qw();

use CTSMS::BulkProcessor::Projects::ETL::Duplicates::Settings qw(
    $skip_errors
    $dry

    $proband_plain_text_truncate_table
    $proband_plain_text_ignore_duplicates
    $import_proband_page_size
    $person_name_prefix_length
    $import_proband_multithreading
    $import_proband_numofthreads

    $proband_duplicate_truncate_table
    $create_duplicate_multithreading
    $create_duplicate_numofthreads

    $update_proband_multithreading
    $update_proband_numofthreads
    $duplicate_proband_category
    $duplicate_comment_prefix
    $proband_categories_not_to_update
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

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule qw();

use CTSMS::BulkProcessor::Projects::ETL::Duplicates::ProjectConnectorPool qw(
    get_sqlite_db
    destroy_all_dbs
);

use CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText qw();
use CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandDuplicate qw();

use CTSMS::BulkProcessor::Array qw(array_to_map powerset contains);

use CTSMS::BulkProcessor::Utils qw(threadid);



require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    import_proband
    create_duplicate
    update_proband
);

sub import_proband {


    my $static_context = {};

    my $result = _import_proband_checks($static_context);

    $result = CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText::create_table($proband_plain_text_truncate_table) if $result;

    my $warning_count :shared = 0;
    $result = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::process_search_items(
        static_context => $static_context,
        in => $static_context->{proband_criteria},
        process_code => sub {
            my ($context,$items,$row_offset) = @_;
            my $rownum = $row_offset;
            my @rows = ();
            foreach my $item (@$items) {
                $rownum++;

                if (not $item->{decrypted}) {
                    _warn_or_error($context,"proband id $item->{id} not decrypted");
                } elsif (not $item->{person}) {
                    _warn_or_error($context,"proband id $item->{id} not person");
                } elsif ($item->{blinded}) {
                    _warn_or_error($context,"proband id $item->{id} is blinded");
                } else {
                    my $cnt = 0;

                    foreach my $first_names (@{powerset(_normalize_person_name($item->{firstName},0,1))}) {
                        next unless @$first_names;
                        foreach my $last_names (@{powerset(_normalize_person_name($item->{lastName},1,1))}) {
                            next unless @$last_names;
                            my @row = ();
                            push(@row,join(' ',@$first_names));
                            push(@row,join(' ',@$last_names));
                            push(@row,$item->{dateOfBirth});
                            push(@row,$item->{id});
                            push(@row,$item->{version});
                            push(@row,$item->{category}->{nameL10nKey});
                            push(@row,$item->{comment});

                            push(@rows,\@row);
                            $cnt++;
                        }
                    }
                    _info($context,"$cnt name variants for proband id $item->{id}") if $cnt > 1;
                }

            }

            if ((scalar @rows) > 0) {
                eval {
                    $context->{db}->db_do_begin(CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText::getinsertstatement($proband_plain_text_ignore_duplicates));
                    $context->{db}->db_do_rowblock(\@rows);
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
                    _info($context,(scalar @rows) . " proband plain text records created");
                }
            }

            return 1;
        },
        init_process_context_code => sub {
            my ($context)= @_;
            $context->{db} = &get_sqlite_db();
            $context->{error_count} = 0;
            $context->{warning_count} = 0;
        },
        uninit_process_context_code => sub {
            my ($context)= @_;
            undef $context->{db};
            destroy_all_dbs();
            {
                lock $warning_count;
                $warning_count += $context->{warning_count};
            }
        },
        blocksize => $import_proband_page_size,
        load_recursive => 0,
        multithreading => $import_proband_multithreading,
        numofthreads => $import_proband_numofthreads,
    ) if $result;
    return ($result,$warning_count);

}

sub _normalize_person_name {

    my ($name,$suppress_prefixes,$split) = @_;

    #$name = "Vous avez aimé l'épée offerte par les elfes à Frodon";

    $name = Unicode::Normalize::NFKD($name);
    $name =~ s/\p{NonspacingMark}//g;

    $name = lc($name);
    $name =~ s/[_-]/ /g;
    $name =~ s/\s+/ /g;
    $name =~ s/^\s+//g;
    $name =~ s/\s+$//g;

    if ($split or $suppress_prefixes) {
        my @parts = split(' ',$name);
        if ($suppress_prefixes) {
            my @parts_filtered = ();
            foreach my $part (@parts) {
                push(@parts_filtered,$part) if length($part) > $person_name_prefix_length;
            }
            return join(' ',@parts_filtered) unless $split;
            return @parts_filtered;
        } else {
            return @parts;
        }
    } else {
        return $name;
    }

}

sub _import_proband_checks {
    my ($context) = @_;

    my $result = 1;
    eval {
        my ($keys,$values);
        ($context->{criteriontie_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
        ($context->{criterionrestriction_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::get_items(),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
        ($context->{criterionproperty_map}, $keys, $values) = array_to_map(CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty::get_items(
            $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule::PROBAND_DB),
            sub { my $item = shift; return $item->{nameL10nKey}; },sub { my $item = shift; return $item->{id}; },'last');
    };
    if ($@) {
        rowprocessingerror(undef,'error loading criteria building blocks',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    } else {
        $context->{proband_criteria} = {
            module => $CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule::PROBAND_DB,
            criterions => [{
                position => 1,
                tieId => undef,
                propertyId => $context->{criterionproperty_map}->{'proband.department.id'},
                restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::IS_EQ_CONTEXT_USER_DEPARTMENT_ID},
            },{
                position => 2,
                tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
                propertyId => $context->{criterionproperty_map}->{'proband.person'},
                restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
                booleanValue => \1,
            },{
                position => 3,
                tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
                propertyId => $context->{criterionproperty_map}->{'proband.blinded'},
                restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
                booleanValue => \0,
            },{
                position => 4,
                tieId => $context->{criteriontie_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionTie::AND},
                propertyId => $context->{criterionproperty_map}->{'proband.deferredDelete'},
                restrictionId => $context->{criterionrestriction_map}->{$CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction::EQ},
                booleanValue => \0,
            }],
        };
    }
    return $result;
}

sub create_duplicate {

    my $static_context = {};
    my $result = _create_duplicate_checks($static_context);
    $result = CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandDuplicate::create_table($proband_duplicate_truncate_table) if $result;


    my $warning_count :shared = 0;

    $result = CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText::process_records(
        static_context => $static_context,
        process_code => sub {
            my ($context,$records,$row_offset) = @_;
            my $rownum = $row_offset;



            foreach my $record (@$records) {
                $rownum++;
                if (CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandDuplicate::countby_probandidduplicateid(undef,$record->{proband_id}) > 0) {
                    _info($context,"proband id $record->{proband_id} duplicate skipped",1);
                    next;
                }
                my %matches = ();




                foreach my $match (@{CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText::findby_lastnamefirstnamedateofbirthprobandid(
                        $record->{last_name},
                        $record->{first_name},
                        $record->{date_of_birth},
                    )}) {
                    next if $match->{proband_id} == $record->{proband_id};
                    $matches{$match->{proband_id}} = $match unless exists $matches{$match->{proband_id}};
                }
                foreach my $match (@{CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText::findby_lastnamefirstnamedateofbirthprobandid(
                        $record->{last_name},
                        $record->{first_name},
                    )}) {
                    next if $match->{proband_id} == $record->{proband_id};
                    next unless ($match->{data_of_birth} =~ /^00/ or $record->{data_of_birth} =~ /^00/);
                    $matches{$match->{proband_id}} = $match unless exists $matches{$match->{proband_id}};
                }
                my @rows = ();
                foreach my $duplicate_proband_id (keys %matches) {
                    push(@rows,[ sort {$a <=> $b} ($record->{proband_id}, $duplicate_proband_id) ]);
                }
                _info($context,(scalar keys %matches) . " duplicates for proband id $record->{proband_id}") if (scalar keys %matches) > 0;
                if ((scalar @rows) > 0) {

                    $context->{db}->db_do_begin(
                        CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandDuplicate::getinsertstatement(1),
                    );
                    eval {
                        $context->{db}->db_do_rowblock(\@rows);
                        $context->{db}->db_finish();
                    };
                    my $err = $@;
                    if ($err) {
                        eval {
                            $context->{db}->db_finish(1);
                        };
                        _warn_or_error($context,$err);
                    }
                }
            }

            return 1;
        },
        init_process_context_code => sub {
            my ($context)= @_;


            $context->{db} = &get_sqlite_db();
            $context->{error_count} = 0;
            $context->{warning_count} = 0;
        },
        uninit_process_context_code => sub {
            my ($context)= @_;
            undef $context->{db};
            destroy_all_dbs();
            {
                lock $warning_count;
                $warning_count += $context->{warning_count};
            }
        },
        load_recursive => 0,
        multithreading => $create_duplicate_multithreading,
        numofthreads => $create_duplicate_numofthreads,
    ) if $result;
    return ($result,$warning_count);

}

sub _create_duplicate_checks {
    my ($context) = @_;

    my $result = 1;

    my $proband_count = 0;
    eval {
        $proband_count = CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText::countby_lastnamefirstnamedateofbirth();
    };
    if ($@) {
        rowprocessingerror(undef,'please import probands first',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }

    return $result;
}

sub update_proband {

    my $static_context = {};
    my $result = _update_proband_checks($static_context);


    my $warning_count :shared = 0;
    my $updated_proband_count :shared = 0;
    $result = CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandDuplicate::process_records(
        static_context => $static_context,
        process_code => sub {
            my ($context,$records,$row_offset) = @_;
            my $rownum = $row_offset;
            foreach my $record (@$records) {
                $rownum++;




                my %duplicate_proband_ids = ();
                $duplicate_proband_ids{$record->{proband_id}} = undef;
                foreach my $duplicate (@{CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandDuplicate::findby_probandid($record->{proband_id})}) {
                    $duplicate_proband_ids{$duplicate->{duplicate_proband_id}} = undef;
                }
                my @duplicate_group = sort {$a <=> $b} keys %duplicate_proband_ids;
                $context->{duplicate_group} = \@duplicate_group;

                my $label = "duplicate group - proband ids " . join (', ',@duplicate_group);
                foreach my $proband_id (@duplicate_group) {






                    my $category_info;
                    eval {
                        $category_info = CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText::findby_lastnamefirstnamedateofbirthprobandid(
                            undef,undef,undef,$proband_id)->[0];
                    };
                    if ($@ or not $category_info) {
                        _warn_or_error($context,"$label: cannot find proband id $proband_id: " . $@);
                    } else {
                        $context->{original} = $category_info;
                        my $new_category;
                        $new_category = $duplicate_proband_category unless contains($category_info->{category},$proband_categories_not_to_update);
                        $new_category ||= $category_info->{category};
                        my $category_updated = $new_category ne $category_info->{category};
                        _info($context,"$label: proband id $context->{original}->{proband_id} category $context->{original}->{category} not changed",1) unless $category_updated;
                        my ($new_comment,$comment_updated) = _get_proband_comment($context);
                        if ($category_updated or $comment_updated) {
                            my $in = { "version" => $category_info->{version},
                                "categoryId" => $context->{proband_categories}->{$new_category}->{id},
                                "comment" => $new_comment,
                            };










                            my $out;
                            eval {
                                if ($dry) {
                                    $out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::get_item($proband_id);
                                } else {
                                    $out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::update_category($proband_id,$in);
                                }
                            };
                            if ($@) {
                                _warn($context,"$label: cannot update proband id $proband_id: " . $@);
                            } else {
                                _info($context,"$label: proband id $proband_id" . ($dry ? ' to be modified' : ' updated'));
                                $context->{updated_proband_count} += 1;
                            }
                        } else {
                            _info($context,"$label: proband id $proband_id already marked");
                        }
                    }
                }


            }

            return 1;
        },
        init_process_context_code => sub {
            my ($context)= @_;

            $context->{error_count} = 0;
            $context->{warning_count} = 0;
            $context->{updated_proband_count} = 0;
        },
        uninit_process_context_code => sub {
            my ($context)= @_;

            destroy_all_dbs();
            {
                lock $warning_count;
                $warning_count += $context->{warning_count};
            }
            {
                lock $updated_proband_count;
                $updated_proband_count += $context->{updated_proband_count};
            }
        },
        load_recursive => 0,
        multithreading => $update_proband_multithreading,
        numofthreads => $update_proband_numofthreads,
    ) if $result;
    return ($result,$warning_count,$updated_proband_count);

}

sub _get_proband_comment {
    my ($context) = @_;

    my %duplicate_proband_ids = map { local $_ = $_; $_ => undef; } @{$context->{duplicate_group}};
    delete $duplicate_proband_ids{$context->{original}->{proband_id}};
    my $duplicate_comment_pattern = quotemeta($duplicate_comment_prefix) . '(\d+,?\s*)*';
    my $new_comment = $duplicate_comment_prefix . join(', ', ( sort {$a <=> $b} keys %duplicate_proband_ids ));

    my $original_comment = _mark_utf8($context->{original}->{comment} // '');
    my $comment = $original_comment;
    if ($comment =~ /$duplicate_comment_pattern/mi) {
        $comment =~ s/^.*$duplicate_comment_pattern/$new_comment/mig;
    } else {
        if (length($comment) > 0) {
            $comment =~ s/\s+$//mg;
            $comment .= "\n\n";
        }
        $comment .= $new_comment;
    }
    my $updated = $comment ne $original_comment;
    _info($context,"proband id $context->{original}->{proband_id} comment not changed",1) unless $updated;

    return ($comment,$updated);

}

sub _update_proband_checks {
    my ($context) = @_;

    my $result = 1;

    $context->{tid} = threadid();

    my $proband_count = 0;
    eval {
        $proband_count = CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText::countby_lastnamefirstnamedateofbirth();
    };
    if ($@) {
        rowprocessingerror(undef,'please import probands first',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }

    my $duplicate_count = 0;
    eval {
        $duplicate_count = CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandDuplicate::countby_probandidduplicateid();
    };
    if ($@) {
        rowprocessingerror(undef,'please identify duplicates first',getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }

    eval {
        ($context->{proband_categories}, my $nameL10nKeys, my $items) = array_to_map(
            CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory::get_all(),
            sub { my $item = shift; return $item->{nameL10nKey}; },undef,'last');
    };
    if ($@ or not $context->{proband_categories}->{$duplicate_proband_category}) {
        rowprocessingerror(undef,"cannot load '$duplicate_proband_category' proband category",getlogger(__PACKAGE__));
        $result = 0; #even in skip-error mode..
    }

    _info($context,'proband categories that will not be changed: ' . ((scalar @$proband_categories_not_to_update) > 0 ? join(", ",@$proband_categories_not_to_update) : '[none]'),0);

    return $result;
}

sub _mark_utf8 {
    return Encode::decode("UTF-8", shift);










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
