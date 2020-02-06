package CTSMS::BulkProcessor::Projects::WebApps::Signup::Settings;
use strict;

## no critic


use Storable qw(dclone);

use CTSMS::BulkProcessor::Globals qw(
    $working_path
    $enablemultithreading
    $cpucount
    create_path
);

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    scriptinfo
    configurationinfo
);

use CTSMS::BulkProcessor::LogError qw(
    fileerror
    configurationwarn
    configurationerror
);

use CTSMS::BulkProcessor::LoadConfig qw(
    split_tuple
    parse_regexp
);

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi
);

use CTSMS::BulkProcessor::Utils qw(format_number prompt get_year_month stringtobool);
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Department qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ContactDetailType qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::AddressType qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::massmail::MassMailService::MassMail qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings
    get_ctsms_site_lang_restapi

    $defaultsettings
    $defaultconfig

    $dancer_sessions_path
    $dancer_environment
    $default_language_code
    $dancer_maketext_options
    $system_timezone
    $default_timezone
    $default_date_format
    $default_decimal_separator

    $ctsms_sites
    $default_site
    $decimal_point

    $proband_create_interval_limit
    $phone_number_prefix_preset
    $email_notify_preset
    $proband_agreed_preset
    $language_menu

    $google_maps_api_url
    $enable_geolocation_services
    $force_default_geolocation

    $ctsms_base_uri

    $google_site_verification
);

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.yml';

our $dancer_sessions_path = $working_path . 'sessions/';
our $dancer_environment = 'development';
our $default_language_code = 'en';
our $dancer_maketext_options = { Style => 'gettext' };
our $system_timezone = 'UTC';
our $default_timezone = $system_timezone;
our $default_date_format = 'yyyy-MM-dd';
our $default_decimal_separator = '.'; # expected by the user

our $ctsms_sites = {};
our $default_site = undef;

our $decimal_point = '.'; # expected by the rest-api

our $proband_create_interval_limit = 300; #less than session timeout
our $phone_number_prefix_preset = '+43';
our $email_notify_preset = 1;
our $proband_agreed_preset = 0;
our $language_menu = 0;

our $google_maps_api_url = 'https://www.google.at/maps/api/js?sensor=false';
our $enable_geolocation_services = 0;
our $force_default_geolocation = 1;

our $ctsms_base_uri = undef;

our $google_site_verification = undef;

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;



        $result &= _prepare_working_paths(1);


        $dancer_environment = $data->{dancer_environment} if exists $data->{dancer_environment};
        $proband_create_interval_limit = $data->{proband_create_interval_limit} if exists $data->{proband_create_interval_limit};
        $phone_number_prefix_preset = $data->{phone_number_prefix_preset} if exists $data->{phone_number_prefix_preset};
        $email_notify_preset = stringtobool($data->{email_notify_preset}) if exists $data->{email_notify_preset};
        $proband_agreed_preset = stringtobool($data->{proband_agreed_preset}) if exists $data->{proband_agreed_preset};
        $default_language_code = $data->{default_language_code} if exists $data->{default_language_code};
        $system_timezone = $data->{system_timezone} if exists $data->{system_timezone};
        $default_timezone = $data->{default_timezone} if exists $data->{default_timezone};
        $default_date_format = $data->{default_date_format} if exists $data->{default_date_format};
        $default_decimal_separator = $data->{default_decimal_separator} if exists $data->{default_decimal_separator}; # expected by the user entry

        $ctsms_base_uri = $data->{ctsms_base_uri} if exists $data->{ctsms_base_uri};

        $google_site_verification = $data->{google_site_verification} if exists $data->{google_site_verification};

        $ctsms_sites = $data->{ctsms_sites} if exists $data->{ctsms_sites};
        $default_site = undef;

        if ('HASH' eq ref $ctsms_sites) {
            foreach my $site_name (keys %$ctsms_sites) {
                my $site = $ctsms_sites->{$site_name};
                if ('HASH' eq ref $site) {
                    if ($site->{default}) {
                        if (defined $default_site) {
                            configurationwarn($configfile,"$site_name - default site already defined",getlogger(__PACKAGE__));
                        } else {
                            $default_site = $site_name;
                        }
                    }
                    $site->{timezone} = $default_timezone unless $site->{timezone};
                    $site->{date_format} = $default_date_format unless $site->{date_format};
                    $site->{decimal_separator} = $default_decimal_separator unless $site->{decimal_separator};
                    my $credentials = $site->{credentials};
                    if ('HASH' eq ref $credentials) {
                        unless ('HASH' eq ref $site->{mass_mail}) {
                            $site->{mass_mail} = { map { $_ => $site->{mass_mail}; } keys %$credentials };
                        }
                        foreach my $lang (keys %$credentials) {
                            my $departments = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Department::get_items(0,get_ctsms_site_lang_restapi($site_name,$lang));
                            my $department_nameL10nKey = (ref $site->{department} ? $site->{department}->{nameL10nKey} : $site->{department});
                            my $department;
                            $department = [ grep { local $_ = $_; $_->{nameL10nKey} eq $department_nameL10nKey; } @$departments ]->[0] if $department_nameL10nKey;
                            configurationerror($configfile,"$site_name - no or unknown department",getlogger(__PACKAGE__)) unless defined $department;
                            if (ref $site->{department}) {
                                $site->{department}->{name}->{$lang} = $department->{name};
                            } else {
                                $site->{department} = $department;
                                $site->{department}->{name} = { $lang => $department->{name} };
                            }

                            my $trial_department_nameL10nKey = (ref $site->{trial_department} ? $site->{trial_department}->{nameL10nKey} : $site->{trial_department});
                            if ($trial_department_nameL10nKey) {
                                my $trial_department = [ grep { local $_ = $_; $_->{nameL10nKey} eq $trial_department_nameL10nKey; } @$departments ]->[0];
                                configurationerror($configfile,"$site_name - no or unknown trial department",getlogger(__PACKAGE__)) unless defined $trial_department;

                                    if (ref $site->{trial_department}) {
                                        $site->{trial_department}->{name}->{$lang} = $trial_department->{name};
                                    } else {
                                        $site->{trial_department} = dclone($trial_department);
                                        $site->{trial_department}->{name} = { $lang => $trial_department->{name} };
                                    }




                            }

                            my $probandcategory = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandCategory::get_preset_item(1,1,0,get_ctsms_site_lang_restapi($site_name,$lang));
                            configurationerror($configfile,"$site_name - no proband category preset found",getlogger(__PACKAGE__)) unless defined $probandcategory;
                            if (ref $site->{proband_category}) {
                                $site->{proband_category}->{name}->{$lang} = $probandcategory->{name};
                            } else {
                                $site->{proband_category} = $probandcategory;
                                $site->{proband_category}->{name} = { $lang => $probandcategory->{name} };
                            }

                            my $contactdetailtypes = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ContactDetailType::get_proband_items(1,undef,0,get_ctsms_site_lang_restapi($site_name,$lang));
                            my $phonecontactdetailtype_nameL10nKey = (ref $site->{phone_contact_detail_type} ? $site->{phone_contact_detail_type}->{nameL10nKey} : $site->{phone_contact_detail_type});
                            my $phonecontactdetailtype;
                            $phonecontactdetailtype = [ grep { local $_ = $_; $_->{nameL10nKey} eq $phonecontactdetailtype_nameL10nKey; } @$contactdetailtypes ]->[0] if $phonecontactdetailtype_nameL10nKey;
                            configurationerror($configfile,"$site_name - no or unknown phone contact detail type",getlogger(__PACKAGE__)) unless defined $phonecontactdetailtype;
                            if (ref $site->{phone_contact_detail_type}) {
                                $site->{phone_contact_detail_type}->{name}->{$lang} = $phonecontactdetailtype->{name};
                            } else {
                                $site->{phone_contact_detail_type} = $phonecontactdetailtype;
                                $site->{phone_contact_detail_type}->{name} = { $lang => $phonecontactdetailtype->{name} };
                            }
                            my $emailcontactdetailtype_nameL10nKey = (ref $site->{email_contact_detail_type} ? $site->{email_contact_detail_type}->{nameL10nKey} : $site->{email_contact_detail_type});
                            my $emailcontactdetailtype;
                            $emailcontactdetailtype = [ grep { local $_ = $_; $_->{nameL10nKey} eq $emailcontactdetailtype_nameL10nKey; } @$contactdetailtypes ]->[0] if $emailcontactdetailtype_nameL10nKey;
                            configurationerror($configfile,"$site_name - no or unknown email contact detail type",getlogger(__PACKAGE__)) unless defined $emailcontactdetailtype;
                            if (ref $site->{email_contact_detail_type}) {
                                $site->{email_contact_detail_type}->{name}->{$lang} = $emailcontactdetailtype->{name};
                            } else {
                                $site->{email_contact_detail_type} = $emailcontactdetailtype;
                                $site->{email_contact_detail_type}->{name} = { $lang => $emailcontactdetailtype->{name} };
                            }

                            my $addresstypes = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::AddressType::get_proband_items(1,undef,0,get_ctsms_site_lang_restapi($site_name,$lang));
                            my $addresstype_nameL10nKey = (ref $site->{address_type} ? $site->{address_type}->{nameL10nKey} : $site->{address_type});
                            my $addresstype;
                            $addresstype = [ grep { local $_ = $_; $_->{nameL10nKey} eq $addresstype_nameL10nKey; } @$addresstypes ]->[0] if $addresstype_nameL10nKey;
                            configurationerror($configfile,"$site_name - no or unknown address type",getlogger(__PACKAGE__)) unless defined $addresstype;
                            if (ref $site->{address_type}) {
                                $site->{address_type}->{name}->{$lang} = $addresstype->{name};
                            } else {
                                $site->{address_type} = $addresstype;
                                $site->{address_type}->{name} = { $lang => $addresstype->{name} };
                            }

                            if (ref $site->{inquiry_trial}) {

                            } elsif (defined $site->{inquiry_trial} and length($site->{inquiry_trial}) > 0) {
                                $site->{inquiry_trial} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item(
                                    $site->{inquiry_trial},
                                    { _activeInquiryCount => 1, _overrides => { signupInquiries => \1, }, },
                                    get_ctsms_site_lang_restapi($site_name,$lang)
                                );
                                configurationerror($configfile,"$site_name - default inquiry form has no form fields",getlogger(__PACKAGE__)) unless $site->{inquiry_trial}->{_activeInquiryCount};
                            }

                            if (ref $site->{mass_mail}->{$lang}) {

                            } elsif (defined $site->{mass_mail}->{$lang} and length($site->{mass_mail}->{$lang}) > 0) {
                                my @mails = map { CTSMS::BulkProcessor::RestRequests::ctsms::massmail::MassMailService::MassMail::get_item($_,0,get_ctsms_site_lang_restapi($site_name,$lang)); } split_tuple($site->{mass_mail}->{$lang});
                                $site->{mass_mail}->{$lang} = \@mails;

                            }

                        }
                    } else {
                        configurationerror($configfile,"$site_name - credentials hash required",getlogger(__PACKAGE__));
                    }
                } else {
                    configurationerror($configfile,"$site_name - hash required",getlogger(__PACKAGE__));
                }
            }
        } else {
            configurationerror($configfile,"ctsms_sites hash required",getlogger(__PACKAGE__));
        }
        configurationerror($configfile,"no default site specified",getlogger(__PACKAGE__)) unless defined $default_site;











        return $result;

    }
    return 0;

}

sub get_ctsms_site_lang_restapi {
    my ($site_name,$lang) = @_;
    my $site = $ctsms_sites->{$site_name};
    return get_ctsms_restapi($site_name . '_' . $lang,
        $site->{uri},
        $site->{credentials}->{$lang}->{username},
        $site->{credentials}->{$lang}->{password},
        $site->{realm});
}

sub _prepare_working_paths {

    my ($create) = @_;
    my $result = 1;
    my $path_result;

    ($path_result,$dancer_sessions_path) = create_path($working_path . 'sessions',$dancer_sessions_path,$create,\&fileerror,getlogger(__PACKAGE__));
    $result &= $path_result;





    return $result;

}

1;
