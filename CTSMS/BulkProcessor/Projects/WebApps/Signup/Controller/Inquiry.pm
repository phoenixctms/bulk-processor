package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry;

use strict;

## no critic

use Dancer qw();

use HTTP::Status qw();

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    json_response
    json_error
    to_json_safe
    to_json_base64
    save_params
    $restapi
    get_site
    get_navigation_options
    get_template
    apply_lwp_file_response
    get_error
    set_error
    add_error_data
    get_paginated_response
    get_page_index

    date_ui_to_iso
    date_iso_to_ui
    date_ui_to_json
    time_ui_to_iso
    time_iso_to_ui
    time_ui_to_json
    datetime_ui_to_iso
    datetime_iso_to_ui
    datetime_ui_to_json
    get_input_timezone

    get_ctsms_baseuri
    get_restapi_uri
    $id_separator_string
    sanitize_decimal
    sanitize_integer
    get_site_name

    check_done
    check_prev
);

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Settings qw(
    $enable_geolocation_services
    $force_default_geolocation
    $system_timezone
    $convert_timezone
    $ctsms_sites
);


use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::InputFieldType qw(
    $SINGLE_LINE_TEXT
    $MULTI_LINE_TEXT
    $AUTOCOMPLETE
    $CHECKBOX
    $DATE
    $TIME
    $TIMESTAMP
    $SELECT_ONE_DROPDOWN
    $SELECT_ONE_RADIO_H
    $SELECT_ONE_RADIO_V
    $SELECT_MANY_H
    $SELECT_MANY_V
    $INTEGER
    $SKETCH
    $FLOAT
);

use CTSMS::BulkProcessor::Utils qw(trim stringtobool string_to_utf8bytes utf8bytes_to_string);
use CTSMS::BulkProcessor::Array qw(removeduplicates array_to_map);

my $listentry_load_all_existing_inquiryvalues = 1;
my $save_all_pages = 0;

my %field_to_param_type_map = (
    $SINGLE_LINE_TEXT => [ 'text' ],
    $MULTI_LINE_TEXT => [ 'text' ],
    $AUTOCOMPLETE => [ 'text' ],
    $CHECKBOX => [ 'boolean' ],
    $DATE => [ 'date' ],
    $TIME => [ 'time' ],
    $TIMESTAMP => [ 'timestampdate', 'timestamptime' ],
    $SELECT_ONE_DROPDOWN => [ 'selection' ],
    $SELECT_ONE_RADIO_H => [ 'selection' ],
    $SELECT_ONE_RADIO_V => [ 'selection' ],
    $SELECT_MANY_H => [ 'selection' ],
    $SELECT_MANY_V => [ 'selection' ],
    $INTEGER => [ 'long' ],
    $SKETCH => [ 'ink' ],
    $FLOAT => [ 'float' ],
);
my $param_value_types = removeduplicates([ map { @{$_}; } values %field_to_param_type_map ]);
my $param_value_types_re = '^(' . join('|',@$param_value_types) . ')_(\\d+)$';
$param_value_types_re = qr/$param_value_types_re/;

our $navigation_options = sub {

    my $inquiries_open = (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::created()
        and (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode() or CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::contact_created())
        and CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::selected()
        and not CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::inquiries_na()
        and (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode() or not CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::trials_na()));
    my $trial = Dancer::session('trial');
    return get_navigation_options($inquiries_open ? Dancer::Plugin::I18N::localize('navigation_inquiry_trial_label',$trial->{name}) : Dancer::Plugin::I18N::localize('navigation_inquiry_label'),
        $inquiries_open ? '/inquiry' : undef, #id exist...
        undef,
        $CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::End::navigation_options);

};

Dancer::get('/inquiry/pdf',sub {

    my $params = Dancer::params();

    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
    return unless (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode() or CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created());
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_selected();
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_inquiries_na();
    return unless (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode() or CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_trials_na());

    my $proband_id = Dancer::session('proband_id');
    my $trial = Dancer::session('trial');
    return apply_lwp_file_response(CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::render_inquiries(
        $proband_id,
        $trial->{id},
        undef,
        1,
        $params->{blank},
        $restapi,
    ), $proband_id . '_' . $trial->{id} . '_inquiryform' . ($params->{blank} ? '_blank' : '') . '.pdf',0);

});

Dancer::get('/inquiry',sub {

    return unless _save_listentry();

    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
    return unless (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode() or CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created());
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_selected();
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_inquiries_na();
    return unless (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode() or CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_trials_na());

    my $site = get_site();
    my $trial = Dancer::session('trial');
    my $address = Dancer::session('proband_address_out');
    
    if ($listentry_load_all_existing_inquiryvalues and listentry_mode()) {
        # preload all values, to indicate what was saved already.
        my $p = {};
        while (1) {
            my ($values) = _load_inquiryvalues($trial,$p,0);
            if (scalar @{$values->{rows}} > 0) {
                Dancer::debug((scalar @{$values->{rows}}) . " inquiry values preloaded");
                $p->{page_num} += 1;
            } else {
                last;
            }
        }
    }    

    return get_template('inquiry',
        script_names => [ 'sketch/jquery.colorPicker', 'sketch/raphael-2.2.0', 'sketch/raphael.sketchpad', 'sketch/json2.min', 'sketch/sketch',
                          'fieldcalculation/js-joda', 'fieldcalculation/js-joda-timezone', 'fieldcalculation/strip-comments', 'fieldcalculation/jquery.base64',
                          'fieldcalculation/restApi', 'fieldcalculation/locationDistance', 'fieldcalculation/fieldCalculation', 'inquiry'],
        style_names => [ 'sketch/colorPicker', 'sketch/sketch', 'inquiry' ],
        js_model => {
            enableGeolocationServices => ($enable_geolocation_services ? \1 : \0),
            forceDefaultGeolocation => ($force_default_geolocation ? \1 : \0),
            defaultGeolocationLatitude => $site->{default_geolocation_latitude},
            defaultGeolocationLongitude => $site->{default_geolocation_longitude},
            apiError => get_error(1),
            saveAllPages => ($save_all_pages ? \1 : \0),
            trial => $trial,
            trialBase64 => to_json_base64($trial),
            probandBase64 => to_json_base64(Dancer::session('proband_out')),
            probandAddressesBase64 => to_json_base64($address ? [ $address ] : Dancer::session('proband_addresses')),

            ctsmsBaseUri => get_ctsms_baseuri(),
            restApiUrl => get_restapi_uri(),
            inquiryPage => Dancer::session('inquiry_page') // 0,
            noSelectionLabel => Dancer::Plugin::I18N::localize('no_selection_label'),
            requiredLabel => Dancer::Plugin::I18N::localize('required_label'),
            optionalLabel => Dancer::Plugin::I18N::localize('optional_label'),
            systemTimeLabel => Dancer::Plugin::I18N::localize('system_time_label',$system_timezone),
            inputTimeLabel => Dancer::Plugin::I18N::localize('input_time_label',get_input_timezone($site)),

            yesBtnLabel => Dancer::Plugin::I18N::localize('yes_btn_label'),
            noBtnLabel => Dancer::Plugin::I18N::localize('no_btn_label'),

            applyCalculatedValueBtnLabel => Dancer::Plugin::I18N::localize('apply_calculated_value_btn_label'),

            inquiriesGridHeader => Dancer::Plugin::I18N::localize('inquiries_grid_header',$trial->{name}),
            inquiriesPbarTemplate => Dancer::Plugin::I18N::localize('inquiries_pbar_template'),

            sketchToggleRegionTooltip => Dancer::Plugin::I18N::localize('sketch_toggle_region_tooltip'),
            sketchDrawModeTooltip => Dancer::Plugin::I18N::localize('sketch_draw_mode_tooltip'),
            sketchUndoTooltip => Dancer::Plugin::I18N::localize('sketch_undo_tooltip'),
            sketchRedoTooltip => Dancer::Plugin::I18N::localize('sketch_redo_tooltip'),
            sketchClearTooltip => Dancer::Plugin::I18N::localize('sketch_clear_tooltip'),


            sketchPenWidth0Tooltip => Dancer::Plugin::I18N::localize('sketch_pen_width_0_tooltip'),
            sketchPenWidth1Tooltip => Dancer::Plugin::I18N::localize('sketch_pen_width_1_tooltip'),
            sketchPenWidth2Tooltip => Dancer::Plugin::I18N::localize('sketch_pen_width_2_tooltip'),
            sketchPenWidth3Tooltip => Dancer::Plugin::I18N::localize('sketch_pen_width_3_tooltip'),

            sketchPenOpacity0Tooltip => Dancer::Plugin::I18N::localize('sketch_pen_opacity_0_tooltip'),
            sketchPenOpacity1Tooltip => Dancer::Plugin::I18N::localize('sketch_pen_opacity_1_tooltip'),
            sketchPenOpacity2Tooltip => Dancer::Plugin::I18N::localize('sketch_pen_opacity_2_tooltip'),

        },

    );
});

Dancer::post('/inquiries',sub {

    my $ajax_error;
    return $ajax_error if $ajax_error = CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created_ajax();
    return $ajax_error if $ajax_error = CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_selected_ajax();

    my $params = Dancer::params();

    my $trial = Dancer::session('trial');
    
    return get_paginated_response($params,sub { my $p = shift;
        my ($values,$posted_inquiries_map,$strokes_id_map,$trial_inquiries_saved_map,$inquiries_saved_map) = _load_inquiryvalues($trial,$p,$params->{load_all_js_values});

        foreach my $inquiry_value (@{$values->{js_rows}}) {
            $inquiry_value->{dateValue} = date_iso_to_ui($inquiry_value->{dateValue},0);
            $inquiry_value->{timeValue} = time_iso_to_ui($inquiry_value->{timeValue},0);
            ($inquiry_value->{timestampdateValue},$inquiry_value->{timestamptimeValue}) = datetime_iso_to_ui(delete $inquiry_value->{timestampValue},$inquiry_value->{userTimeZone});
            $inquiry_value->{inkValue} = _pack_inkvalue(utf8bytes_to_string(delete $inquiry_value->{inkValues}),
                [ map { $inquiry_value->{_inputFieldSelectionSelectionSetValueMap}->{$_}; } @{$inquiry_value->{selectionValueIds}} ]);

            if (not $inquiry_value->{disabled}) {
                _restore_from_session($posted_inquiries_map,$inquiry_value);
            }

            $inquiry_value->{dateValue} = date_ui_to_json($inquiry_value->{dateValue},0);
            $inquiry_value->{timeValue} = time_ui_to_json($inquiry_value->{timeValue},0);
            $inquiry_value->{timestampValue} = datetime_ui_to_json(delete $inquiry_value->{timestampdateValue},delete $inquiry_value->{timestamptimeValue},$inquiry_value->{userTimeZone});

            $inquiry_value->{inkValues} = string_to_utf8bytes(delete $inquiry_value->{inkValue});
        }
        $values->{js_rows_base64} = to_json_base64(delete $values->{js_rows});

        $values->{trial} = $trial;
        Dancer::session('inquiry_page',get_page_index($params));
        return $values;
    });
});

Dancer::post('/inquiry/savepage',sub {
    my $ajax_error;
    return $ajax_error if $ajax_error = CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_selected_ajax();
    my $trial = Dancer::session('trial');
    my $posted_inquiries_map = _save_page_params($trial,$save_all_pages);
    if ($save_all_pages) {
        CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::set_inquiry_counts($trial,undef,$posted_inquiries_map);
        Dancer::session('trial',$trial);
        return json_response($trial);
    } else {
        return $ajax_error if $ajax_error = CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created_ajax();
        if (not CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode()) {
            return $ajax_error if $ajax_error = CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created_ajax();
        }
        return $ajax_error if $ajax_error = CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_inquiries_na_ajax();
        if (not CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode()) {
            return $ajax_error if $ajax_error = CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_trials_na_ajax();
        }

        eval {
            ($posted_inquiries_map, my $trial_inquiries_saved_map) = _save_page($trial,$posted_inquiries_map);
            CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::set_inquiry_counts($trial,$trial_inquiries_saved_map,$posted_inquiries_map);
            Dancer::session('trial',$trial);
        };
        if ($@) {
            return json_error(HTTP::Status::HTTP_NOT_FOUND,undef,&$restapi()->responsedata);
        } else {
            return json_response($trial);
        }
    }


});

Dancer::post('/inquiry',sub {
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_selected();
    my $trial = Dancer::session('trial');
    my $posted_inquiries_map = _save_page_params($trial,$save_all_pages);

    return check_done(sub {
        check_prev(sub {
            return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
            return unless (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode() or CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created());
            return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_inquiries_na();
            return unless (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::listentry_mode() or CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_trials_na());
            eval {
               ($posted_inquiries_map, my $trial_inquiries_saved_map) = _save_page($trial,$posted_inquiries_map);
            };
            if ($@) {
                set_error(&$restapi()->responsedata);
                return Dancer::forward('/inquiry', undef, { method => 'GET' });
            } else {
                return Dancer::forward('/end', undef, { method => 'GET' });
            }
        }, sub {
            Dancer::forward('/trial', undef, { method => 'GET' });
        });
    });
});

sub listentry_mode {
    my $id = Dancer::session('listentry_id');
    if (defined $id and length($id) > 0) {
        return 1;
    }
    return 0;
}

sub clear_listentry_mode {
    CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::clear_session() if listentry_mode();
}

sub keep_listentry_mode {
    if (listentry_mode()) {
        Dancer::forward('/inquiry', { beacon => Dancer::session('listentry')->{beacon} }, { method => 'GET' });
        return 1;
    }
    return 0;
}

sub reset_listentry_beacons {
    if (listentry_mode()) {
        eval {
            CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::reset_beacon(
                            Dancer::session('listentry')->{beacon},
                            0,$restapi);
        };
        if ($@) {
            Dancer::error("failed to reset listentry beacon: " . $@);
        }
    } else {
        # for regular registations, retain the beacon for use in emails?
        my $proband_list_entry_id_map = Dancer::session('proband_list_entry_id_map') // {};
        if (scalar values %$proband_list_entry_id_map) {
            foreach my $listentry (values %$proband_list_entry_id_map) {
                eval {
                    CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::reset_beacon(
                            $listentry->{beacon},
                            0,$restapi);
                };
                if ($@) {
                    Dancer::error("failed to reset listentry beacon: " . $@);
                }
            }
        }
    }
}

sub _save_listentry {
    my $params = Dancer::params();
    my $beacon_id = $params->{'beacon'}; # || $params->{'id'} || $params->{'listentry_id'};
    if ($beacon_id) {
        my $log_prefix = "picked up listentry beacon/id $beacon_id: ";
        my $proband_list_entry_id_map = Dancer::session('proband_list_entry_id_map') // {};
        my $trial = Dancer::session("trial");
        my $proband_list_entry;
        if ($trial
            and exists $proband_list_entry_id_map->{$trial->{id}}
            and ($beacon_id eq $proband_list_entry_id_map->{$trial->{id}}->{beacon} or $beacon_id == $proband_list_entry_id_map->{$trial->{id}}->{id})) {
            $proband_list_entry = $proband_list_entry_id_map->{$trial->{id}};
            Dancer::debug($log_prefix . "proceeding listentry id " . $proband_list_entry_id_map->{$trial->{id}}->{id});
        } else {
            Dancer::debug($log_prefix . "loading listentry");
            eval {
                $proband_list_entry = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::get_item($beacon_id,0,$restapi);
            };
            if ($@) {
                set_error($@);
                Dancer::forward('/proband', undef, { method => 'GET' });
                return 0; 
            }
        }
        if ($proband_list_entry) {
            if (listentry_mode() and $proband_list_entry->{id} != Dancer::session("listentry_id")) {
                Dancer::debug($log_prefix . "switching to listentry id $proband_list_entry->{id}");
                CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::clear_session();
            }
            my $proband = $proband_list_entry->{proband};
            $trial = $proband_list_entry->{trial};
            if (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::created() and $proband->{id} != Dancer::session("proband_id")) {
                Dancer::debug($log_prefix . "switching to proband id $proband->{id}");
                CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::clear_session()
            }
            
            my $filter_mode;
            my $filter_site = sub {
                my $_site = shift;
                my $result = 0;
                if ($_site->{department}->{id} == $proband->{department}->{id}) {
                    $result = 1;
                }
                if ($filter_mode) {
                    if ($filter_mode eq 'TRIAL') {
                        if ($_site->{trial_department} and $_site->{trial_department}->{id} != $trial->{department}->{id}) {
                            $result = 0;
                        }
                    }
                }
                return $result;
            };            
            
            $filter_mode = 'TRIAL';
            my $site_name = (grep { $filter_site->($ctsms_sites->{$_}); } sort keys %$ctsms_sites)[0];
            if ($site_name) {
                Dancer::debug($log_prefix . 'site ' . $site_name . ' found for department ' . $proband->{department}->{name} . ' and trial department ' . $trial->{department}->{name});
            } else {
                undef $filter_mode;
                $site_name = (grep { $filter_site->($ctsms_sites->{$_}); } sort keys %$ctsms_sites)[0];
                if ($site_name) {
                    Dancer::debug($log_prefix . 'site ' . $site_name . ' found for department ' . $proband->{department}->{name});
                }
            }
            
            if ($site_name) {
                CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::save_site($site_name) if $site_name ne get_site_name();
            
                Dancer::session("listentry_id", $proband_list_entry->{id});
                Dancer::session("listentry", $proband_list_entry);
                
                Dancer::session("proband_id",$proband->{id});
                Dancer::session("proband_version",$proband->{version});
                Dancer::session("proband_department_id",$proband->{department}->{id});
                Dancer::session("proband_out",$proband);
                
                my $addresses = Dancer::session("proband_addresses");
                unless ($addresses) {
                    Dancer::debug($log_prefix . "loading proband addresses");
                    eval {
                         $addresses = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress::get_proband_list($proband->{beacon}, undef, undef , 0, $restapi);
                    };
                    if ($@) {
                        set_error($@);
                        Dancer::forward('/proband', undef, { method => 'GET' });
                        return 0; 
                    } else {
                        Dancer::session("proband_addresses",$addresses);
                    }
                }
                CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::clear_contact_ids();
                
                $proband_list_entry_id_map->{$trial->{id}} = $proband_list_entry;
                Dancer::session('proband_list_entry_id_map',$proband_list_entry_id_map);
                
                $trial = Dancer::session("trial");
                if ($proband_list_entry->{trial}->{id} != ($trial ? $trial->{id} : 0)) {
                    Dancer::debug($log_prefix . "loading inquiry count for trial $proband_list_entry->{trial}->{name}");
                    eval {
                        $trial = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($proband_list_entry->{trial}->{id},{ _activeInquiryCount => 1 },$restapi);
                    };
                    if ($@) {
                        set_error($@);
                        Dancer::forward('/proband', undef, { method => 'GET' });
                        return 0;
                    }
                }
                
                my $trial_inquiries_saved_map = Dancer::session('trial_inquiries_saved_map') // {};
                my $inquiries_saved_map = $trial_inquiries_saved_map->{$trial->{id}} // {};
                my $posted_inquiries_map = Dancer::session('posted_inquiries_map_' . $trial->{id}) // {};
                CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::set_inquiry_counts($trial,$inquiries_saved_map,$posted_inquiries_map);
                Dancer::session('trial',$trial);
                
                Dancer::session('enabled_trial', $trial); # enable trial, disregarding the signup state

                if (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::inquiries_na()) {
                    set_error(Dancer::Plugin::I18N::localize('error_inquiries_na'));
                    Dancer::forward('/proband', undef, { method => 'GET' });
                    return 0;
                }
                
                #use Data::Dumper;
                #Dancer::debug($log_prefix . Dumper(Dancer::session));
                          
            } else {
                Dancer::debug($log_prefix . 'no site found for department ' . $proband->{department}->{name});
                set_error(Dancer::Plugin::I18N::localize('error_listentry_unknown_site', $trial->{department}->{name}));
                Dancer::forward('/proband', undef, { method => 'GET' });
                return 0; 
            }
        } else {
            Dancer::debug($log_prefix . "invalid list entry");
            set_error(Dancer::Plugin::I18N::localize('error_invalid_listentry', $beacon_id));
            Dancer::forward('/proband', undef, { method => 'GET' });
            return 0; 
        }
    }
    return 1;
}

sub _load_inquiryvalues {
    my ($trial,$p,$load_all_js_values) = @_;
    my $values = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::get_inquiryvalues(
        Dancer::session('proband_id'), #null will give error...
        $trial->{id},
        undef,
        1,
        1,
        $load_all_js_values,
        ($convert_timezone ? undef : get_input_timezone()),
        $p,
        undef,
        { _selectionSetValueMap => 1, _inputFieldSelectionSelectionSetValueMap => 1 },$restapi);
    my $posted_inquiries_map = Dancer::session('posted_inquiries_map_' . $trial->{id}) // {};
    my $strokes_id_map = Dancer::session('strokes_id_map') // {};
    my $trial_inquiries_saved_map = Dancer::session('trial_inquiries_saved_map') // {}; #when saved somwhere else meantime; optional..?
    my $inquiries_saved_map = $trial_inquiries_saved_map->{$trial->{id}} // {};
    foreach my $inquiry_value (@{$values->{rows}}) {
        $inquiry_value->{dateValue} = date_iso_to_ui($inquiry_value->{dateValue},0);
        $inquiry_value->{timeValue} = time_iso_to_ui($inquiry_value->{timeValue},0);
        ($inquiry_value->{timestampdateValue},$inquiry_value->{timestamptimeValue}) = datetime_iso_to_ui(delete $inquiry_value->{timestampValue},$inquiry_value->{inquiry}->{field}->{userTimeZone});
        $inquiry_value->{inkValue} = _pack_inkvalue(delete $inquiry_value->{inkValues},$inquiry_value->{selectionValues});

        if (not $inquiry_value->{inquiry}->{disabled}) {
            _restore_from_session($posted_inquiries_map,$inquiry_value);
        }
        $inquiry_value->{_posted} = (exists $posted_inquiries_map->{$inquiry_value->{inquiry}->{id}} ? \1 : \0);

        foreach my $selection_set_value (@{$inquiry_value->{inquiry}->{field}->{selectionSetValues}}) {
            $strokes_id_map->{$selection_set_value->{strokesId}} = $selection_set_value->{id} if (defined $selection_set_value->{strokesId} and length($selection_set_value->{strokesId}) > 0);
        }
        $inquiries_saved_map->{$inquiry_value->{inquiry}->{id}} = { id => $inquiry_value->{id}, version => $inquiry_value->{version}, user_timezone => $inquiry_value->{inquiry}->{field}->{userTimeZone}, };
    }
    $trial_inquiries_saved_map->{$trial->{id}} = $inquiries_saved_map;
    Dancer::session('trial_inquiries_saved_map', $trial_inquiries_saved_map);
    $trial->{_activeInquiryCount} = $p->{total_count};
    CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::set_inquiry_counts($trial,$inquiries_saved_map,$posted_inquiries_map);
    Dancer::session('trial',$trial);
    Dancer::session('strokes_id_map',$strokes_id_map);
    
    return ($values,$posted_inquiries_map,$strokes_id_map,$trial_inquiries_saved_map,$inquiries_saved_map);
}

sub _save_page {
    my ($trial,$posted_inquiries_map) = @_;
    my $trial_inquiries_saved_map = Dancer::session('trial_inquiries_saved_map') // {};
    my $inquiries_saved_map = $trial_inquiries_saved_map->{$trial->{id}} // {};
    my $in = _get_inquiryvalues_in($posted_inquiries_map,$inquiries_saved_map);
    my $out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::set_inquiryvalues($in,0,
        ($convert_timezone ? undef : get_input_timezone()),0,$restapi);
    foreach my $inquiry_value (@{$out->{rows}}) {
       $inquiries_saved_map->{$inquiry_value->{inquiry}->{id}} = { id => $inquiry_value->{id}, version => $inquiry_value->{version}, user_timezone => $inquiry_value->{inquiry}->{field}->{userTimeZone}, };
       Dancer::debug('inquiry value ' . $inquiry_value->{id} . ' set');
    }
    $trial_inquiries_saved_map->{$trial->{id}} = $inquiries_saved_map;
    Dancer::session('trial_inquiries_saved_map', $trial_inquiries_saved_map);
    $posted_inquiries_map = undef;
    Dancer::session('posted_inquiries_map_' . $trial->{id},$posted_inquiries_map);
    return ($posted_inquiries_map,$trial_inquiries_saved_map);
}

sub _restore_from_session {
    my ($posted_inquiries_map,$inquiry_value) = @_;
    my @original_values = ();
    my $inquiry_id;
    my $selectionSetValueMap;
    my $inquiry_name;
    my $is_js;
    my $input_field_type;
    if (exists $inquiry_value->{inquiryId}) {
        $inquiry_id = $inquiry_value->{inquiryId};
        $selectionSetValueMap = $inquiry_value->{_inputFieldSelectionSelectionSetValueMap};
        $inquiry_name = $inquiry_value->{inputFieldName};
        $is_js = 1;
        $input_field_type = $inquiry_value->{inputFieldType};
    } else {
        $inquiry_id = $inquiry_value->{inquiry}->{id};
        $selectionSetValueMap = $inquiry_value->{inquiry}->{field}->{_selectionSetValueMap};
        $inquiry_name = $inquiry_value->{inquiry}->{field}->{name};
        $is_js = 0;
        $input_field_type = $inquiry_value->{inquiry}->{field}->{fieldType}->{type};
    }
    foreach my $type (@{$field_to_param_type_map{$input_field_type}}) {

        my $session_value;
        $session_value = $posted_inquiries_map->{$inquiry_id} if exists $posted_inquiries_map->{$inquiry_id};
        my $field_name = $type . 'Value';
        my $original_value;
        if (exists $inquiry_value->{$field_name}) {
            $original_value = $inquiry_value->{$field_name}
        } else {
            $field_name = $type . ($is_js ? 'ValueIds' : 'Values');
            if (exists $inquiry_value->{$field_name}) {
                $original_value = $inquiry_value->{$field_name};
            } else {
                Dancer::error('unknow inquiry param value type: ', $type);
                die("unknow inquiry param value type: $type\n");
            }
        }
        if (defined $session_value) {
            my $override_value;
            if ('boolean' eq $type) {
                $override_value = (stringtobool($session_value->[-1]->{value}) ? \1 : \0);
            } elsif ('selection' eq $type) {
                $override_value = [];
                foreach my $selection (@$session_value) {
                    my $id = $selection->{value};
                    if (length($id) > 0) {
                        my $item = $selectionSetValueMap->{$id};
                        if (defined $item) {
                            push(@$override_value,$item->{id}) if $is_js;
                            push(@$override_value,$item) if not $is_js;
                        }
                    }
                }
            } elsif ('timestampdate' eq $type or 'timestamptime' eq $type) {
                foreach my $date_and_time (@$session_value) {
                    if ($type eq $date_and_time->{type} and length($date_and_time->{value}) > 0) {
                        $override_value = $date_and_time->{value};
                    }
                }
            } elsif ('ink' eq $type) {
                if ($is_js) {
                    Dancer::debug('overriding ' . $inquiry_name. ': ', $inquiry_value->{selectionValueIds});
                    push(@original_values,$inquiry_value->{selectionValueIds});
                    $override_value = $session_value->[0]->{value};
                    (undef,$inquiry_value->{selectionValueIds}) = _unpack_inkvalue($override_value,$inquiry_value->{inputFieldSelectionSetValues},1);
                } else {
                    Dancer::debug('overriding ' . $inquiry_name. ': ', $inquiry_value->{selectionValues});
                    push(@original_values,$inquiry_value->{selectionValues});
                    $override_value = $session_value->[0]->{value};
                    (undef,$inquiry_value->{selectionValues}) = _unpack_inkvalue($override_value,$inquiry_value->{inquiry}->{field}->{selectionSetValues});
                }
            } else {
                $override_value = $session_value->[-1]->{value};
            }

            $inquiry_value->{$field_name} = $override_value;
            Dancer::debug('overriding ' . $inquiry_name . ': ', $override_value);
        } else {
            Dancer::debug('no entered value for ' .$inquiry_name . ': ', $original_value);
        }
        push(@original_values,$original_value);
    }
    return @original_values;

}

sub _pack_inkvalue {

    my ($ink_value,$selection_values) = @_;
    my $ink_value_w_ids;
    if (defined $ink_value and length($ink_value) > 0) {
        $ink_value_w_ids = Dancer::from_json($ink_value);
    } else {
        $ink_value_w_ids = [];
    }
    my @stroke_ids = ();
    foreach my $selection_value (@$selection_values) {
        push(@stroke_ids,$selection_value->{strokesId});
    }
    push(@$ink_value_w_ids,join($id_separator_string,@stroke_ids));

    $ink_value_w_ids = to_json_safe($ink_value_w_ids);
    return $ink_value_w_ids;

}

sub _unpack_inkvalue {

    my ($ink_value_w_ids,$selection_set_values,$ids_only) = @_;
    if (defined $ink_value_w_ids and length($ink_value_w_ids) > 0) {
        $ink_value_w_ids = Dancer::from_json($ink_value_w_ids);
        if ((scalar @$ink_value_w_ids) > 0) {
            my @selection_values = ();
            unless (ref $ink_value_w_ids->[-1]) {
                my $strokes_id_map = $selection_set_values;
                ($strokes_id_map, undef, undef) = array_to_map($selection_set_values,sub { my $item = shift; return $item->{strokesId}; },undef,'last') if 'ARRAY' eq ref $strokes_id_map;
                foreach my $stroke_id (split(quotemeta($id_separator_string),pop(@$ink_value_w_ids))) {
                    if (exists $strokes_id_map->{$stroke_id}) {
                        push(@selection_values,$strokes_id_map->{$stroke_id}) if not $ids_only;
                        push(@selection_values,$strokes_id_map->{$stroke_id}->{id}) if $ids_only;
                    }
                }
            }

            return (to_json_safe($ink_value_w_ids),\@selection_values);
        }
    }
    return (undef, undef);

}

sub _save_page_params {
    my ($trial,$all_pages) = @_;
    my $posted_inquiries_map;
    if ($all_pages) {
        $posted_inquiries_map = Dancer::session('posted_inquiries_map_' . $trial->{id});
    }
    $posted_inquiries_map //= {};
    my %seen_inquiry_ids = ();
    my $params = save_params(
        { regexp => $param_value_types_re, match_cb => sub { my ($name,$value,@captures) = @_;
                my $type = $captures[0];
                my $inquiry_id = $captures[1];
                unless ($seen_inquiry_ids{$inquiry_id}) {
                    $seen_inquiry_ids{$inquiry_id} = 1;
                    delete $posted_inquiries_map->{$inquiry_id};
                }
                my $values;
                if (exists $posted_inquiries_map->{$inquiry_id}) {
                    $values = $posted_inquiries_map->{$inquiry_id};
                } else {
                    $values = [];
                    $posted_inquiries_map->{$inquiry_id} = $values;
                }
                if ('ARRAY' eq ref $value) {
                    push(@$values,map { { name => $name, type => $type, value => $_ }; } @$value);
                } else {
                    push(@$values,{ name => $name, type => $type, value => $value });
                }
                Dancer::debug('param saved: ', $name, $type, $value);
                return 0;
            },
        }
    );
    Dancer::session('posted_inquiries_map_' . $trial->{id},$posted_inquiries_map);
    return $posted_inquiries_map;
}


sub _get_inquiryvalues_in {
    my ($posted_inquiries_map,$inquiries_saved_map) = @_;
    my $proband_id = Dancer::session('proband_id');
    my $strokes_id_map = Dancer::session('strokes_id_map') // {};
    my @result = ();
    foreach my $inquiry_id (keys %$posted_inquiries_map) {
        my $session_values = $posted_inquiries_map->{$inquiry_id};
        my %in = ();


        my $error_code = sub { my ($parser,$msg) = @_; &$restapi()->responsedata(add_error_data($msg,$inquiry_id)); die($msg . "\n"); };
        my ($date,$time,$user_timezone);
        if (exists $inquiries_saved_map->{$inquiry_id}) {
            $in{id} = $inquiries_saved_map->{$inquiry_id}->{id};
            $in{version} = $inquiries_saved_map->{$inquiry_id}->{version};
            $user_timezone = $inquiries_saved_map->{$inquiry_id}->{user_timezone};
        }
        foreach my $session_value (@$session_values) {
            my $type = $session_value->{type};
            my $field_name = $type . 'Value';
            if ('boolean' eq $type) {
                $in{$field_name} = (stringtobool($session_value->{value}) ? \1 : \0);
            } elsif ('selection' eq $type) {
                $field_name = 'selectionValueIds';
                $in{$field_name} = [] unless exists $in{$field_name};
                push(@{$in{$field_name}},$session_value->{value}) if length($session_value->{value}) > 0;
            } elsif ('date' eq $type) {
                $in{$field_name} = date_ui_to_iso($session_value->{value},0,$error_code);
            } elsif ('time' eq $type) {
                $in{$field_name} = time_ui_to_iso($session_value->{value},0,$error_code);
            } elsif ('timestampdate' eq $type) {
                $date = $session_value->{value};
                $in{timestampValue} = datetime_ui_to_iso($date,$time,$user_timezone,$error_code);
            } elsif ('timestamptime' eq $type) {
                $time = $session_value->{value};
                $in{timestampValue} = datetime_ui_to_iso($date,$time,$user_timezone,$error_code);
            } elsif ('float' eq $type) {
                $in{$field_name} = sanitize_decimal($session_value->{value});
            } elsif ('long' eq $type) {
                $in{$field_name} = sanitize_integer($session_value->{value});
            } elsif ('ink' eq $type) {
                ($in{inkValues},$in{selectionValueIds}) = _unpack_inkvalue($session_value->{value},$strokes_id_map);
                $in{inkValues} = string_to_utf8bytes($in{inkValues});
            } else {
                $in{$field_name} = $session_value->{value};
            }
        }
        $in{inquiryId} = $inquiry_id;
        $in{probandId} = $proband_id;
        push(@result,\%in);
    }

    return \@result;
}

1;
