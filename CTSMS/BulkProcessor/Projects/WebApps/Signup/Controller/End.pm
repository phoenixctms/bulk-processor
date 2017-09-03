package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::End;

use strict;

## no critic

use Dancer qw();
use JSON qw();
#no use Dancer::Plugin::I18N !!;
use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    $restapi
    get_site
    get_navigation_options
    get_template
    get_error
    apply_lwp_file_response
    date_iso_to_ui
);

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues qw();

our $navigation_options = sub {
    my $done  = (CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::created() and
        CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::contact_created());
    return get_navigation_options(Dancer::Plugin::I18N::localize('navigation_end_label'),
        $done ? '/end' : undef,
        undef,
        undef);
};

Dancer::get('/end/probandletterpdf',sub {
    
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created();

    return apply_lwp_file_response(CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress::render_probandletter(
        Dancer::session('proband_address_id'),
        $restapi,
    ), Dancer::session('proband_id') . '_probandletter.pdf', 0);
        
});


Dancer::get('/end/inquiryformspdf',sub {
    
    my $params = Dancer::params();
        
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created(); 
    #return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_selected();
    #return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_inquiries_na();
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_trials_na();

    my $proband_id = Dancer::session('proband_id');
    my $site = get_site();

    #my $trial = Dancer::session('trial');
    return apply_lwp_file_response(CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::render_inquiries_signup(
        $site->{trial_department} ? $site->{trial_department}->{id} : undef,
        $proband_id,
        1,
        $restapi,
    ), $proband_id . '_inquiryforms.pdf',0);
    #$proband_id . '_' .XX $trial->{id} . '_inquiryform.pdf',0);
        
});

    
Dancer::get('/end',sub {
    CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
    CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact::check_contact_created();
    my $trial_inquiries_saved_map = Dancer::session('trial_inquiries_saved_map') // {};
    my $saved_inquiry_count = 0;
    foreach my $trial_id (keys %$trial_inquiries_saved_map) {
        my $trial = {};
        my $inquiries_saved_map = $trial_inquiries_saved_map->{$trial_id} // {};
        CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::set_inquiry_counts($trial,$inquiries_saved_map,undef);
        $saved_inquiry_count += $trial->{_savedInquiryCount};
    }
    return get_template('end',
        script_names => 'end',
        style_names => 'end',
        js_model => {
            apiError => get_error(1),            
            #siteOptions => get_site_options(),
        },
        saved_inquiry_count => $saved_inquiry_count,
        auto_delete_deadline => date_iso_to_ui(Dancer::session('proband_out')->{autoDeleteDeadline}),
    );
});

Dancer::post('/end',sub {
    #using forward will not preserve session data set on the forwarding rule. ?
    my $last_created = Dancer::session("proband_created_timestamp");
    Dancer::session->destroy();
    #Dancer::Session::engine()->write_session_id(undef);
    #Dancer::Session->get_current_session();
    Dancer::session("proband_created_timestamp",$last_created);
    #return Dancer::forward('/', undef, { method => 'GET' });
    return get_template('start',
        script_names => 'start',
        style_names => 'start',
        js_model => {
            apiError => get_error(1),            
            probandCreated => JSON::false,
            probandDepartmentId => undef,
            CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Start::start_js_model(),
        },
    );    
    
});

1;
