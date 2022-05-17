package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Contact;

use strict;

## no critic

use Dancer qw();

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    save_params
    $restapi
    get_site
    get_navigation_options
    get_template
    get_error
    set_error
    check_done
);

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Settings qw(
    $phone_number_prefix_preset
    $email_notify_preset
);

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandContactDetailValue qw();

use CTSMS::BulkProcessor::Utils qw(trim stringtobool);

our $navigation_options = sub {
    return get_navigation_options(Dancer::Plugin::I18N::localize('navigation_contact_label'),
        CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::created() ? '/contact' : undef, #id exist...
        undef,
        $CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::navigation_options);
};

Dancer::get('/contact',sub {
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
    Dancer::session('proband_address_country_name',Dancer::session('proband_address_country_name') || Dancer::session('proband_citizenship'));

    unless (defined Dancer::session(_type_to_param_prefix('email_contact_detail_type') . 'notify')) {
        Dancer::session(_type_to_param_prefix('email_contact_detail_type') . 'notify',($email_notify_preset ? 'true' : ''));
    }
    return get_template('contact',
        script_names => 'contact',
        style_names => 'contact',
        js_model => {
            apiError => get_error(1),
            probandAddressCountryNameTooltip => Dancer::Plugin::I18N::localize('proband_address_country_name_tooltip'),
            probandAddressZipCodeTooltip => Dancer::Plugin::I18N::localize('proband_address_zip_code_tooltip'),
            probandAddressProvinceTooltip => Dancer::Plugin::I18N::localize('proband_address_province_tooltip'),
            probandAddressCityNameTooltip => Dancer::Plugin::I18N::localize('proband_address_city_name_tooltip'),
            probandAddressStreetNameTooltip => Dancer::Plugin::I18N::localize('proband_address_street_name_tooltip'),
            probandAddressHouseNumberTooltip => Dancer::Plugin::I18N::localize('proband_address_house_number_tooltip'),
            probandAddressEntranceTooltip => Dancer::Plugin::I18N::localize('proband_address_entrance_tooltip'),
            probandAddressDoorNumberTooltip => Dancer::Plugin::I18N::localize('proband_address_door_number_tooltip'),
            probandPhoneTooltip => Dancer::Plugin::I18N::localize('proband_phone_tooltip'),
            probandEmailTooltip => Dancer::Plugin::I18N::localize('proband_email_tooltip'),
            probandEmailNotifyTooltip => Dancer::Plugin::I18N::localize('proband_email_notify_tooltip'),
        },
        trials_na => CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::trials_na(),
    );
});

Dancer::post('/contact',sub {
    my $params = save_params(
        'proband_address_city_name',
        'proband_address_country_name',
        'proband_address_door_number',
        'proband_address_entrance',
        'proband_address_house_number',
        'proband_address_street_name',
        'proband_address_zip_code',
        'proband_address_province',
        _type_to_param_prefix('phone_contact_detail_type') . 'value',
        _type_to_param_prefix('email_contact_detail_type') . 'value',
        _type_to_param_prefix('email_contact_detail_type') . 'notify',
    );
    Dancer::session(_type_to_param_prefix('email_contact_detail_type') . 'notify','') unless defined $params->{_type_to_param_prefix('email_contact_detail_type') . 'notify'};
    return unless CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Proband::check_created();
    eval {
        my $address_in = _get_address_in($params);
        my $address_out;
        if (_address_created()) {
            $address_out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress::update_item($address_in,0,$restapi);
            Dancer::debug('proband address id ' . $address_out->{id} . ' updated');
        } else {
            $address_out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress::add_item($address_in,0,$restapi);
            Dancer::debug('proband address id ' . $address_out->{id} . ' created');
        }
        Dancer::session("proband_address_id",$address_out->{id});
        Dancer::session("proband_address_version",$address_out->{version});
        Dancer::session("proband_address_out",$address_out);

        my $type = 'phone_contact_detail_type';
        my $prefix = _type_to_param_prefix($type);
        my $phone_in = _get_contactdetailvalue_in($params,$type);
        my $phone_out;
        if (_contactdetailvalue_created($type)) {
            $phone_out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandContactDetailValue::update_item($phone_in,0,$restapi);
            Dancer::debug('proband contact detail value id ' . $phone_out->{id} . " ($type) updated");
        } else {
            $phone_out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandContactDetailValue::add_item($phone_in,0,$restapi);
            Dancer::debug('proband contact detail value id ' . $phone_out->{id} . " ($type) created");
        }
        Dancer::session($prefix . 'id',$phone_out->{id});
        Dancer::session($prefix . 'version',$phone_out->{version});

        $type = 'email_contact_detail_type';
        $prefix = _type_to_param_prefix($type);
        my $email_in = _get_contactdetailvalue_in($params,$type);
        my $email_out;
        if (_contactdetailvalue_created($type)) {
            $email_out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandContactDetailValue::update_item($email_in,0,$restapi);
            Dancer::debug('proband contact detail value id ' . $email_out->{id} . " ($type) updated");
        } else {
            $email_out = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandContactDetailValue::add_item($email_in,0,$restapi);
            Dancer::debug('proband contact detail value id ' . $email_out->{id} . " ($type) created");
        }
        Dancer::session($prefix . 'id',$email_out->{id});
        Dancer::session($prefix . 'version',$email_out->{version});

        if (not defined $phone_in->{value} and not defined $email_in->{value}) {
            Dancer::error("neither phone nor email entered");
            die(Dancer::Plugin::I18N::localize('error_no_contact_details') . "\n");
        }

    };
    if ($@) {
        set_error($@);
        return Dancer::forward('/contact', undef, { method => 'GET' });
    } else {
        return check_done(sub {
            return Dancer::forward(CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::Trial::trials_na() ? '/end' : '/trial', undef, { method => 'GET' });
        });
    }
});

sub _address_created {
    my $id = Dancer::session('proband_address_id');
    if (defined $id and length($id) > 0) {
        return 1;
    }
    return 0;
}

sub _get_address_in {
    my $params = shift;
    my $site = get_site();
    return {
        (_address_created() ? (
            "id" => Dancer::session('proband_address_id'),
            "version" => Dancer::session('proband_address_version'),
        ) : ()),
        "afnus" => \0,

        "careOf" => "",
        "cityName" => trim($params->{proband_address_city_name}),
        "countryName" => trim($params->{proband_address_country_name}),
        "deliver" => \1,
        "doorNumber" => trim($params->{proband_address_door_number}),
        "entrance" => trim($params->{proband_address_entrance}),
        "houseNumber" => trim($params->{proband_address_house_number}),
        "probandId" => Dancer::session('proband_id'),
        "streetName" => trim($params->{proband_address_street_name}),
        "typeId" => $site->{address_type}->{id},
        "zipCode" => trim($params->{proband_address_zip_code}),
        "province" => trim($params->{proband_address_province}),
    };
}

sub _type_to_param_prefix {
    my $type = shift;
    if ('phone_contact_detail_type' eq $type) {
        return "proband_phone_";
    } elsif ('email_contact_detail_type' eq $type) {
        return "proband_email_";
    } else {
        Dancer::error('unknow contact detail type: ', $type);
        die("unknow contact detail type: $type\n");
    }
}

sub contact_created {
    return (_address_created() and _contactdetailvalue_created('email_contact_detail_type')
        and _contactdetailvalue_created('phone_contact_detail_type'));
}

sub clear_contact_ids {
    Dancer::session('proband_address_id',undef);
    Dancer::session(_type_to_param_prefix('email_contact_detail_type') . 'id',undef);
    Dancer::session(_type_to_param_prefix('phone_contact_detail_type') . 'id',undef);
}

sub check_contact_created {
    unless (contact_created()) {
        set_error(Dancer::Plugin::I18N::localize('error_no_contact_created'));
        Dancer::forward('/contact', undef, { method => 'GET' });
        return 0;
    }
    return 1;
}

sub check_contact_created_ajax {
    unless (contact_created()) {
        return json_error(HTTP::Status::HTTP_NOT_FOUND,'/contact',Dancer::Plugin::I18N::localize('error_no_contact_created'));
    }
    return undef;
}

sub _contactdetailvalue_created {
    my $type = shift;
    my $id = Dancer::session(_type_to_param_prefix($type) . 'id');
    if (defined $id and length($id) > 0) {
        return 1;
    }
    return 0;
}

sub _get_contactdetailvalue_in {
    my ($params,$type) = @_;
    my $site = get_site();
    my $prefix = _type_to_param_prefix($type);
    my $value = _sanitize_contactdetailvalue($params->{$prefix . 'value'},$type);
    my $notify = (exists $params->{$prefix . 'notify'} ? stringtobool($params->{$prefix . 'notify'} // '') : 1); # default 1 for phone
    return {
        (_contactdetailvalue_created($type) ? (
            "id" => Dancer::session($prefix . 'id'),
            "version" => Dancer::session($prefix . 'version'),
        ) : ()),

        "na" => (length($value) > 0 ? \0 : \1),
        "notify" => ((length($value) > 0 and $notify) ? \1 : \0),
        "probandId" => Dancer::session('proband_id'),
        "typeId" => $site->{$type}->{id},
        "value" => (length($value) > 0 ? $value : undef),
    };
}

sub _sanitize_contactdetailvalue {
    my ($value,$type) = @_;
    $value //= '';
    if ('phone_contact_detail_type' eq $type) {
        $value =~ s/[^0-9+]+//g;
        $value =~ s/^00/+/g;
        if (defined $phone_number_prefix_preset and length($phone_number_prefix_preset) > 0) {
            $value =~ s/^0/$phone_number_prefix_preset/g;
        }
    } elsif ('email_contact_detail_type' eq $type) {
        $value = trim($value);
    }
    return $value
}

1;
