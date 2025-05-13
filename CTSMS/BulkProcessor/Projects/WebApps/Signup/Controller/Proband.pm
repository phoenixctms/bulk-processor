package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband;

use strict;

## no critic

use HTTP::Status qw();

use Dancer qw();

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    save_params
    $restapi
    get_site
    get_navigation_options
    get_template
    set_error
    get_error
    date_ui_to_iso
    json_error
);

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Settings qw(
    $proband_create_interval_limit
    $proband_agreed_preset
);

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();

use CTSMS::BulkProcessor::Utils qw(timestamp secs_to_years trim stringtobool);
use CTSMS::BulkProcessor::Calendar qw(datetime_delta);

our $navigation_options = sub {
    return get_navigation_options(Dancer::Plugin::I18N::localize('navigation_proband_label'),'/proband',
        undef,
        $CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::navigation_options);
};

Dancer::get('/proband',sub {
    Dancer::session("referer",Dancer::request->referer) unless Dancer::session("referer");
    save_site();
    save_enabled_trial();
    unless (defined Dancer::session('proband_agreed')) {
        Dancer::session('proband_agreed',($proband_agreed_preset ? 'true' : ''));
    }

    my $site = get_site();
    return get_template('proband',
        script_names => 'proband',
        style_names => 'proband',
        js_model => {
            apiError => get_error(1),

            probandCreated => (created() ? \1 : \0),

            probandAgreedTooltip => Dancer::Plugin::I18N::localize('proband_agreed_tooltip'),
            probandPrefixedTitlesTooltip => Dancer::Plugin::I18N::localize('proband_prefixed_titles_tooltip'),
            probandFirstNameTooltip => Dancer::Plugin::I18N::localize('proband_first_name_tooltip'),
            probandLastNameTooltip => Dancer::Plugin::I18N::localize('proband_last_name_tooltip'),
            probandPostpositionedTitlesTooltip => Dancer::Plugin::I18N::localize('proband_postpositioned_titles_tooltip'),
            probandGenderTooltip => Dancer::Plugin::I18N::localize('proband_gender_tooltip'),
            probandDobTooltip => Dancer::Plugin::I18N::localize('proband_dob_tooltip',$site->{date_format}),
            probandCitizenshipTooltip => Dancer::Plugin::I18N::localize('proband_citizenship_tooltip'),
        },
    );
});

Dancer::post('/proband',sub {

    my $params = save_params(
        (!created() ? ('proband_agreed') : ()),
        'proband_citizenship',
        'proband_dob',
        'proband_first_name',
        'proband_gender',
        'proband_last_name',
        'proband_postpositioned_title_1',
        'proband_postpositioned_title_2',
        'proband_postpositioned_title_3',
        'proband_prefixed_title_1',
        'proband_prefixed_title_2',
        'proband_prefixed_title_3',
    );
    if (!created()) {
        Dancer::session('proband_agreed','') unless defined $params->{'proband_agreed'};

        unless (stringtobool($params->{'proband_agreed'} // '')) {
            set_error(Dancer::Plugin::I18N::localize('error_proband_not_agreed'));
            return Dancer::forward('/proband', undef, { method => 'GET' });
        }
    }
    eval {
        my $in = _get_in($params);
        my $out;
        if (created()) {
            $out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::update_item($in,0,$restapi);
            Dancer::debug('proband id ' . $out->{id} . ' updated');
        } elsif (_proband_create_interval_limit_ok()) {
            $out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::add_item($in,0,$restapi);
            Dancer::debug('proband id ' . $out->{id} . ' created');
            Dancer::session("proband_created_timestamp",timestamp());

        } else {
            Dancer::error("proband create rate limit of $proband_create_interval_limit, last proband created at: ",Dancer::session("proband_created_timestamp"));
            die(Dancer::Plugin::I18N::localize('error_proband_create_rate_limit') . "\n");
        }
        Dancer::session("proband_id",$out->{id});
        Dancer::session("proband_version",$out->{version});
        Dancer::session("proband_department_id",$out->{department}->{id});
        Dancer::session("proband_out",$out);
    };
    if ($@) {
        set_error($@);
        return Dancer::forward('/proband', undef, { method => 'GET' });
    } else {
        return Dancer::forward('/contact', undef, { method => 'GET' });
    }
});

sub save_site {
    my $params = Dancer::params();
    my $site;
    if (exists $params->{'site'}) {
        Dancer::session('trial_page',undef);
        Dancer::session('site',$params->{'site'});
        $site = get_site();
        Dancer::debug('selected site: ', $site->{label});
    } else {
        $site = get_site();
    }
    if (created()) {
        if ($site->{department}->{id} ne Dancer::session('proband_department_id')) {
            _clear_session();
            Dancer::debug('site changed, starting new proband');
        }
    } else {
        _clear_session();
        Dancer::debug('starting new proband');
    }
}

sub _clear_session {
    
    my $referer = Dancer::session("referer");
    my $site = Dancer::session('site');
    my $lang = Dancer::session('lang');
    my $last_created = Dancer::session("proband_created_timestamp");
    my $error = Dancer::session('api_error');
    
    Dancer::session->destroy();
    
    Dancer::session('referer',$referer) if $referer;
    Dancer::session('site',$site) if $site;
    Dancer::session('lang',$lang) if $lang;
    Dancer::session('proband_created_timestamp',$last_created) if $last_created;
    Dancer::session('api_error',$error) if $error;
    
    #Dancer::session("proband_id",undef);
    #CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::clear_contact_ids();
    #Dancer::session('proband_list_entry_id_map',undef);
    #Dancer::session('trial',undef);
    #Dancer::session('trial_search',undef);
    #Dancer::session('enabled_trial',undef);

}

sub save_enabled_trial {
    my $params = Dancer::params();
    if (exists $params->{'trial'}) {
        my $enabled_trial;
        eval {
            my $site = get_site();
            my $p = { page_size => 1 , page_num => 1, total_count => undef };
            my $sf = { id => $params->{'trial'}, };
            $enabled_trial = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_signup_list(
                $site->{trial_department} ? $site->{trial_department}->{id} : undef,
                $p,
                $sf,
                undef,$restapi)->[0];

        };
        if ($enabled_trial) {
            Dancer::session('enabled_trial', $enabled_trial);
            Dancer::debug('enabled trial: ', $enabled_trial->{id});
        }
    }
}

sub created {
    my $id = Dancer::session('proband_id');
    if (defined $id and length($id) > 0) {
        return 1;
    }
    return 0;
}

sub check_created {
    unless (created()) {
        set_error(Dancer::Plugin::I18N::localize('error_no_proband_created'));
        Dancer::forward('/proband', undef, { method => 'GET' });
        return 0;
    }
    return 1;
}

sub check_created_ajax {
    unless (created()) {
        return json_error(HTTP::Status::HTTP_NOT_FOUND,'/proband',Dancer::Plugin::I18N::localize('error_no_proband_created'));
    }
    return undef;
}

sub _proband_create_interval_limit_ok {
    my $last_created = Dancer::session("proband_created_timestamp");
    if (defined $last_created
        and defined $proband_create_interval_limit
        and $proband_create_interval_limit > 0
        and (my $delta = datetime_delta($last_created,timestamp())) < $proband_create_interval_limit) {


        return 0;
    }
    return 1;
}

sub _get_in {
    my $params = shift;
    my $site = get_site();
    my $enabled_trial = Dancer::session('enabled_trial');
    return {
        (created() ? (
            "id" => Dancer::session('proband_id'),
            "version" => Dancer::session('proband_version'),
        ) : ()),
        "categoryId" => $site->{proband_category}->{id},
        "person" => \1,
        "blinded" => \0,
        "citizenship" => trim($params->{proband_citizenship}),
        "comment" => Dancer::Plugin::I18N::localize('proband_comment',Dancer::request->uri_base(),Dancer::Plugin::I18N::localize($site->{label}),(defined $enabled_trial ? $enabled_trial->{name} : ''),Dancer::request->address(),Dancer::request->user_agent,Dancer::session("referer")),
        "dateOfBirth" => date_ui_to_iso($params->{proband_dob}),
        "departmentId" => $site->{department}->{id},
        "firstName" => trim($params->{proband_first_name}),
        "gender" => $params->{proband_gender},
        "lastName" => trim($params->{proband_last_name}),
        "postpositionedTitle1" => trim($params->{proband_postpositioned_title_1}),
        "postpositionedTitle2" => trim($params->{proband_postpositioned_title_2}),
        "postpositionedTitle3" => trim($params->{proband_postpositioned_title_3}),
        "prefixedTitle1" => trim($params->{proband_prefixed_title_1}),
        "prefixedTitle2" => trim($params->{proband_prefixed_title_2}),
        "prefixedTitle3" => trim($params->{proband_prefixed_title_3}),
    };
}

1;
