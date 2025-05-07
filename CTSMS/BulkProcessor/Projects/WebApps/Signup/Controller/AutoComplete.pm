package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::AutoComplete;

use strict;

## no critic

use Dancer qw();

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    json_response
    $restapi
);

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Settings qw(
    $address_country
    $address_province
);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteStreetName qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteZipCode qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteCountryName qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteCityName qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteProvince qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteTitle qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteInputFieldSelectionSetValueValue qw();

Dancer::post('/autocomplete/street',sub {
    my $params = Dancer::params();
    return json_response(CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteStreetName::complete_street_name(
        $params->{street_name},
        $params->{country_name} || $address_country,
        $params->{province} || $address_province,
        $params->{city_name},
        undef,
        undef,0,$restapi)
    );
});

Dancer::post('/autocomplete/zip',sub {
    my $params = Dancer::params();
    return json_response(CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteZipCode::complete_zip_code(
        $params->{zip_code},
        $params->{country_name} || $address_country,
        $params->{province} || $address_province,
        length($params->{city_name}) > 0 ? $params->{city_name} : undef,
        undef,0,$restapi)
    );
});

Dancer::post('/autocomplete/country',sub {
    my $params = Dancer::params();
    return json_response(CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteCountryName::complete_country_name(
        $params->{country_name} || $address_country,
        undef,0,$restapi)
    );
});

Dancer::post('/autocomplete/city',sub {
    my $params = Dancer::params();
    return json_response(CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteCityName::complete_city_name(
        $params->{city_name},
        $params->{country_name} || $address_country,
        $params->{province} || $address_province,
        length($params->{zip_code}) > 0 ? $params->{zip_code} : undef,
        undef,0,$restapi)
    );
});

Dancer::post('/autocomplete/province',sub {
    my $params = Dancer::params();
    return json_response(CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteProvince::complete_province(
        $params->{city_name},
        $params->{country_name} || $address_country,
        $params->{province} || $address_province,
        length($params->{zip_code}) > 0 ? $params->{zip_code} : undef,
        undef,0,$restapi)
    );
});

Dancer::post('/autocomplete/title',sub {
    my $params = Dancer::params();
    return json_response(CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteTitle::complete_title(
        $params->{title},
        undef,0,$restapi)
    );
});

Dancer::post('/autocomplete/fieldvalue',sub {
    my $params = Dancer::params();
    return json_response(CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteInputFieldSelectionSetValueValue::complete_input_field_selection_set_value_value(
        $params->{value},
        $params->{id},
        undef,0,$restapi)
    );
});

1;
