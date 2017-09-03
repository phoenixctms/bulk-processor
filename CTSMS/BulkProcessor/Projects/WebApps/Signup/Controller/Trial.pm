package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial;

use strict;

## no critic

use Dancer qw();
use JSON qw();
use HTTP::Status qw();
#no use Dancer::Plugin::I18N !!;
use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    save_params
    $restapi
    get_site
    get_navigation_options
    get_template
    get_error
    set_error
    get_paginated_response
    json_error
    get_page_index
    get_site_option
    check_done
);
#    get_site_name
#use CTSMS::BulkProcessor::Projects::WebApps::Signup::Settings qw(
#    $phone_number_prefix_preset
#);

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry qw();
#use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues qw();

our $navigation_options = sub {
    my $trials_open = (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::created()
        and CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::contact_created()
        and not CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::trials_na());
    return get_navigation_options(Dancer::Plugin::I18N::localize('navigation_trial_label'),
        $trials_open ? '/trial' : undef, #id exist...
        undef,
        $CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Inquiry::navigation_options);
        #$CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Address::navigation_options);
};
    
Dancer::get('/trial',sub {
    #my $params = save_params(
    #    'trial_id',
    #);

    #Dancer::session('proband_id', 5849789); #5843441);
    #Dancer::session('proband_phone_id', 5849793);
    #Dancer::session('proband_email_id', 5849795);
    #Dancer::session('proband_address_id',5849791);    
    
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created();
    return unless check_trials_na();
    #Dancer::session('proband_address_country_name',Dancer::session('proband_address_country_name') || Dancer::session('proband_citizenship'));
    #Dancer::session('proband_phone_value',Dancer::session('proband_phone_value') || $phone_number_prefix_preset);
    
    my $site = get_site();
    
    my $inquiry_trial;
    if ($site->{inquiry_trial}) {
        $inquiry_trial = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($site->{inquiry_trial}->{id},
            { _activeInquiryCount => 1, _overrides => { signupInquiries => JSON::true, }, },
            $restapi);
        my $trial_inquiries_saved_map = Dancer::session('trial_inquiries_saved_map') // {};
        my $inquiries_saved_map = $trial_inquiries_saved_map->{$inquiry_trial->{id}} // {};
        my $posted_inquiries_map = Dancer::session('posted_inquiries_map_' . $inquiry_trial->{id}) // {};
        set_inquiry_counts($inquiry_trial,$inquiries_saved_map,$posted_inquiries_map);            
    }
    
    return get_template('trial',
        script_names => 'trial',
        style_names => 'trial',
        js_model => {
            apiError => get_error(1),
            trial => Dancer::session('trial'),
            probandListEntryIdMap => Dancer::session('proband_list_entry_id_map') // {},
            trialPage => Dancer::session('trial_page') // 0,
            
            trialsGridHeader => Dancer::Plugin::I18N::localize('trials_grid_header'),
            openInquiriesBtnLabel => Dancer::Plugin::I18N::localize('open_inquiries_btn_label'),
            signupBtnLabel => Dancer::Plugin::I18N::localize('signup_btn_label'),
            inquiriesPbarTemplate => Dancer::Plugin::I18N::localize('inquiries_pbar_template'),
            inquiryTrial => $inquiry_trial,
            
            probandAddressCountryNameTooltip => Dancer::Plugin::I18N::localize('proband_address_country_name_tooltip'),
            probandAddressZipCodeTooltip => Dancer::Plugin::I18N::localize('proband_address_zip_code_tooltip'),
            probandAddressCityNameTooltip => Dancer::Plugin::I18N::localize('proband_address_city_name_tooltip'),
            probandAddressStreetNameTooltip => Dancer::Plugin::I18N::localize('proband_address_street_name_tooltip'),
            probandAddressHouseNumberTooltip => Dancer::Plugin::I18N::localize('proband_address_house_number_tooltip'),
            probandAddressEntranceTooltip => Dancer::Plugin::I18N::localize('proband_address_entrance_tooltip'),
            probandAddressDoorNumberTooltip => Dancer::Plugin::I18N::localize('proband_address_door_number_tooltip'),
            probandPhoneTooltip => Dancer::Plugin::I18N::localize('proband_phone_tooltip'),
            probandEmailTooltip => Dancer::Plugin::I18N::localize('proband_email_tooltip'),
        },        
    );
});

Dancer::post('/trials',sub {
    my $params = Dancer::params();
    my $site = get_site();
    #$department_id,$load_recursive,$restapi,$headers
    return get_paginated_response($params,sub { my $p = shift;
        #$p->{page_size} = 1;
        my $trials = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_signup_list(
            $site->{trial_department} ? $site->{trial_department}->{id} : undef,
            $p,
            { sort_by => 'name', sort_dir => 'asc', },
            { _activeInquiryCount => 1 },$restapi);
        my $proband_list_entry_id_map = Dancer::session('proband_list_entry_id_map') // {};
        my $trial_inquiries_saved_map = Dancer::session('trial_inquiries_saved_map') // {};
        foreach my $trial (@$trials) {
            $trial->{_signedUp} = (exists $proband_list_entry_id_map->{$trial->{id}} ? JSON::true : JSON::false);
            #my $trial_id = $trial->{id};
            #if ($site->{inquiry_trial}) {
            #    $trial_id = $site->{inquiry_trial}->{id};
            #}
            my $inquiries_saved_map = $trial_inquiries_saved_map->{$trial->{id}} // {};
            my $posted_inquiries_map = Dancer::session('posted_inquiries_map_' . $trial->{id}) // {};
            set_inquiry_counts($trial,$inquiries_saved_map,$posted_inquiries_map);
        }
        
        #$values->{probandListEntryIdMap} = $proband_list_entry_id_map;
        Dancer::session('trial_page',get_page_index($params));
        return $trials;
    });
});

Dancer::post('/trial',sub {
    #my $params = save_params(
    #    'trial_id',
    #);
    my $params = Dancer::params();
    #Dancer::session('trial_id',undef);
    Dancer::session('trial',undef);
    Dancer::session('inquiry_page',undef);
    #my $inquiries_na = 1;
    #Dancer::session('inquiries_na',$inquiries_na);

    return check_done(sub {
        return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
        return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created();
        return unless check_trials_na();
        my $site = get_site();
    
        eval {
            #if (defined $params->{trial} and length($params->{trial}) > 0) {
                my $trial = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($params->{trial},{ _activeInquiryCount => 1 },$restapi);

                Dancer::debug('trial id ' . $trial->{id} . ' selected');
                #my $trial_id = $trial->{id};
                #Dancer::session('trial_id',$trial_id);
                #######Dancer::session('trial',$trial);
                #$inquiries_na = not($trial->{status}->{inquiryValueInputEnabled} and $trial->{signupInquiries} and $trial->{_activeInquiryCount} > 0);
                #Dancer::session('inquiries_na',$inquiries_na);
                if ($trial->{signupProbandList} and not signedup($trial)) {
                    my $proband_list_entry_id_map = Dancer::session('proband_list_entry_id_map') // {};
                    my $proband_list_entry = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry::addsignup_item(
                        _get_probandlistentry_in($proband_list_entry_id_map,$trial),
                        0,$restapi);
                    Dancer::debug('proband list entry id ' . $proband_list_entry->{id} . ' created');
                    $proband_list_entry_id_map->{$trial->{id}} = $proband_list_entry;
                    Dancer::session('proband_list_entry_id_map',$proband_list_entry_id_map);
                    #Dancer::session("proband_list_entry_" . $trial->{id},$proband_list_entry);
                }
                if ($trial->{signupInquiries} and $trial->{_activeInquiryCount} == 0 and $site->{inquiry_trial}) {
                    $trial = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($site->{inquiry_trial}->{id},
                        { _activeInquiryCount => 1, _overrides => { signupInquiries => JSON::true, }, },
                        $restapi);
                }
                my $trial_inquiries_saved_map = Dancer::session('trial_inquiries_saved_map') // {};
                my $inquiries_saved_map = $trial_inquiries_saved_map->{$trial->{id}} // {};
                my $posted_inquiries_map = Dancer::session('posted_inquiries_map_' . $trial->{id}) // {};
                set_inquiry_counts($trial,$inquiries_saved_map,$posted_inquiries_map);                
                Dancer::session('trial',$trial);
                
            #}
        };
        if ($@) {
            set_error($@);
            return Dancer::forward('/trial', undef, { method => 'GET' });
        } else {
            return Dancer::forward(inquiries_na() ? '/trial' : '/inquiry', undef, { method => 'GET' });
            #return check_done(sub {
            #    return Dancer::forward(inquiries_na() ? '/trial' : '/inquiry', undef, { method => 'GET' });
            #});
        }
    });

});

sub selected {
    my $trial = Dancer::session('trial');
    if (defined $trial) {
        return 1;
    }
    return 0;
}

sub check_selected {
    unless (selected()) {
        set_error(Dancer::Plugin::I18N::localize('error_no_trial_selected'));
        Dancer::forward('/trial', undef, { method => 'GET' });
        return 0;
    }
    return 1;
}

sub check_selected_ajax {
    unless (selected()) {
        return json_error(HTTP::Status::HTTP_NOT_FOUND,'/trial',Dancer::Plugin::I18N::localize('error_no_trial_selected'));
    }
    return undef;
}

sub inquiries_na {
    my $trial = Dancer::session('trial');
    return (defined $trial ? $trial->{_inquiriesNa} : 1);
}

sub check_inquiries_na_ajax {
    if (inquiries_na()) {
        return json_error(HTTP::Status::HTTP_NOT_FOUND,'/trial',Dancer::Plugin::I18N::localize('error_inquiries_na'));
    }
    return undef;
}

sub check_inquiries_na {
    if (inquiries_na()) {
        set_error(Dancer::Plugin::I18N::localize('error_inquiries_na'));
        Dancer::forward('/trial', undef, { method => 'GET' });
        return 0;
    }
    return 1;
}

sub trials_na {
    my $site_option = get_site_option();
    return ((defined $site_option->{trialCount} and $site_option->{trialCount} > 0 and $site_option->{trialSignup}) ? 0 : 1);
}

sub check_trials_na_ajax {
    if (trials_na()) {
        return json_error(HTTP::Status::HTTP_NOT_FOUND,'/trial',Dancer::Plugin::I18N::localize('error_trials_na'));
    }
    return undef;
}

sub check_trials_na {
    if (trials_na()) {
        set_error(Dancer::Plugin::I18N::localize('error_trials_na'));
        Dancer::forward('/', undef, { method => 'GET' });
        return 0;
    }
    return 1;
}

sub signedup {
    #my $trial = Dancer::session('trial');
    my $trial = shift;
    if (defined $trial) {
        my $proband_list_entry_id_map = Dancer::session('proband_list_entry_id_map') // {};
        if (exists $proband_list_entry_id_map->{$trial->{id}}
            and $proband_list_entry_id_map->{$trial->{id}}) {
            return 1;
        }
    }
    return 0;
}

sub _get_probandlistentry_in {
    my ($proband_list_entry_id_map,$trial) = @_;
    #my $trial = Dancer::session('trial');
    #my $proband_list_entry_id_map = Dancer::session('proband_list_entry_id_map') // {};
    return {
        (signedup($trial) ? (
            "id" => $proband_list_entry_id_map->{$trial->{id}}->{id},
            "version" => $proband_list_entry_id_map->{$trial->{id}}->{version},
        ) : ()),
        #"groupId" => undef,
        #"position" => undef,
        "probandId" => Dancer::session('proband_id'),
        "trialId" => $trial->{id},
    };
}

sub set_inquiry_counts {
    my ($trial,$inquiries_saved_map,$posted_inquiries_map) = @_;
    if (defined $inquiries_saved_map) {
        my $inquiry_value_count = 0;
        foreach my $inquiry_id (keys %{$inquiries_saved_map}) {
            my $value_id = $inquiries_saved_map->{$inquiry_id}->{id};
            $inquiry_value_count += 1 if (defined $value_id and length($value_id) > 0);
        }
        $trial->{_savedInquiryCount} = $inquiry_value_count;
    }
    if (defined $posted_inquiries_map) {
        #my $posted_inquiries_map = Dancer::session('posted_inquiries_map_' . $trial->{id}) // {};
        $trial->{_postedInquiryCount} = scalar keys %$posted_inquiries_map;
    }
}

1;
