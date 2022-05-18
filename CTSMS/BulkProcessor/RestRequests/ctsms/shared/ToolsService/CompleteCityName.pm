package CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteCityName;
use strict;

## no critic

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi

);

use CTSMS::BulkProcessor::RestProcessor qw(
    copy_row
    get_query_string
);

use CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi qw(_get_api);
use CTSMS::BulkProcessor::RestItem qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    complete_city_name
);

my $default_restapi = \&get_ctsms_restapi;
my $get_complete_path_query = sub {
    my ($city_name_infix,$country_name_infix,$province_infix,$zip_code_prefix, $limit) = @_;
    my %params = ();
    $params{cityNameInfix} = $city_name_infix if defined $city_name_infix;
    $params{countryNameInfix} = $country_name_infix if defined $country_name_infix;
    $params{zipCodePrefix} = $zip_code_prefix if defined $zip_code_prefix;
    $params{limit} = $limit if defined $limit;
    if (length($province_infix)) {
        $params{provinceInfix} = $province_infix;
        return 'tools/complete/citynameprovince/' . get_query_string(\%params);
    } else {
        return 'tools/complete/cityname/' . get_query_string(\%params);
    }
};


my $fieldnames = [
    'cityname',
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub complete_city_name {

    my ($city_name_infix,$country_name_infix,$province_infix,$zip_code_prefix, $limit, $load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_complete_path_query($city_name_infix,$country_name_infix,$province_infix,$zip_code_prefix, $limit),$headers),$load_recursive,$restapi);

}


sub builditems_fromrows {

    my ($rows,$load_recursive,$restapi) = @_;

    my $item;

    if (defined $rows and ref $rows eq 'ARRAY') {
        my @items = ();
        foreach my $row (@$rows) {
            $item = __PACKAGE__->new($row);

            # transformations go here ...

            push @items,$item;
        }
        return \@items;
    } elsif (defined $rows and ref $rows eq 'HASH') {
        $item = __PACKAGE__->new($rows);
        return $item;
    }
    return undef;

}

sub TO_JSON {

    my $self = shift;
    return {
        value => $self->{cityname},
        label => $self->{cityname},
    };
}

1;
