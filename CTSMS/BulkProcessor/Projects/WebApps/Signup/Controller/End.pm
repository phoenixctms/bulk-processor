package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::End;

use strict;

## no critic

use Dancer qw();


use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    $restapi
    get_site
    get_navigation_options
    get_template
    get_error
    apply_lwp_file_response
    date_iso_to_ui
    get_lang
);

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::massmail::MassMailService::MassMailRecipient qw();

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


    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::check_trials_na();

    my $proband_id = Dancer::session('proband_id');
    my $site = get_site();


    return apply_lwp_file_response(CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues::render_inquiries_signup(
        $site->{trial_department} ? $site->{trial_department}->{id} : undef,
        $proband_id,
        1,
        $restapi,
    ), $proband_id . '_inquiryforms.pdf',0);


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
    eval {
        foreach my $in (_get_mass_mail_recipient_ins()) {
            my $out;
            if (defined $in->{massMailId}) {
                if (_mass_mail_recipient_created($in->{massMailId})) {
                    $out = CTSMS::BulkProcessor::RestRequests::ctsms::massmail::MassMailService::MassMailRecipient::reset_item(
                        Dancer::session(_mass_mail_param_prefix($in->{massMailId},'recipient_id')),
                        Dancer::session(_mass_mail_param_prefix($in->{massMailId},'version')),0,$restapi);
                    Dancer::debug('mass mail recipient id ' . $out->{id} . ' reset');
                    Dancer::session(_mass_mail_param_prefix($in->{massMailId},'version'),$out->{version});
                } else {
                    $out = CTSMS::BulkProcessor::RestRequests::ctsms::massmail::MassMailService::MassMailRecipient::add_item($in,0,$restapi);
                    Dancer::debug('mass mail recipient id ' . $out->{id} . ' created');
                    Dancer::session(_mass_mail_param_prefix($in->{massMailId},'recipient_id'),$out->{id});
                    Dancer::session(_mass_mail_param_prefix($in->{massMailId},'version'),$out->{version});
                }
            }
        }
    };
    if ($@) {
        Dancer::error("failed to create/reset mass mail recipient: " . $@);
    }
    return get_template('end',
        script_names => 'end',
        style_names => 'end',
        js_model => {
            apiError => get_error(1),

        },
        saved_inquiry_count => $saved_inquiry_count,
        auto_delete_deadline => date_iso_to_ui(Dancer::session('proband_out')->{autoDeleteDeadline},1),
    );
});

Dancer::post('/end',sub {

    my $last_created = Dancer::session("proband_created_timestamp");
    Dancer::session->destroy();


    Dancer::session("proband_created_timestamp",$last_created);

    return get_template('start',
        script_names => 'start',
        style_names => 'start',
        js_model => {
            apiError => get_error(1),
            probandCreated => \0,
            probandDepartmentId => undef,
            CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Start::start_js_model(),
        },
    );

});

sub _mass_mail_param_prefix {
    my ($mass_mail_id,$type) = @_;
    return 'mass_mail_' . $mass_mail_id . '_' . $type;
}

sub _mass_mail_recipient_created {
    my ($mass_mail_id) = @_;
    my $id = Dancer::session(_mass_mail_param_prefix($mass_mail_id,'recipient_id'));
    if (defined $id and length($id) > 0) {
        return 1;
    }
    return 0;
}

sub _get_mass_mail_recipient_ins {

    my $site = get_site();
    my $lang = get_lang();
    return () unless defined $site->{mass_mail}->{$lang};
    return map { {
        "probandId" => Dancer::session('proband_id'),
        "massMailId" => $_->{id},
    }; } @{$site->{mass_mail}->{$lang}};
}

1;
