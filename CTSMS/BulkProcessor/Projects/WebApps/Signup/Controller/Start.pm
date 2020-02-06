package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Start;

use strict;

## no critic

use Dancer qw();


use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    get_site_options
    get_navigation_options
    get_template
    get_error
);

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Settings qw(
    $enable_geolocation_services
);

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();

our $navigation_options = sub {
    return get_navigation_options(Dancer::Plugin::I18N::localize('navigation_start_label'),'/',
        undef,
        $CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::navigation_options);
};

Dancer::get('/',sub {

    Dancer::session("referer",Dancer::request->referer);
    return get_template('start',
        script_names => 'start',
        style_names => 'start',
        js_model => {
            apiError => get_error(1),
            probandCreated => (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::created() ? \1 : \0),
            probandDepartmentId => Dancer::session("proband_department_id"),
            start_js_model(),
        },
    );
});

Dancer::post('/',sub {
    #using forward will not preserve session data set on the forwarding rule. ?
    CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::save_site();
    return Dancer::forward('/proband', undef, { method => 'GET' });
});


sub start_js_model {
    return (
        siteOptions => get_site_options(),
        enableGeolocationServices => ($enable_geolocation_services ? \1 : \0),
        trialSitesHeader => Dancer::Plugin::I18N::localize('trial_sites_header'),
        selectSiteBtnLabel => Dancer::Plugin::I18N::localize('select_site_btn_label'),
    );
}

1;
