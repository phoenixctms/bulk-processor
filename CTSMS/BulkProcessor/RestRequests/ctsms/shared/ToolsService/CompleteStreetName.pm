package CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteStreetName;
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
    complete_street_name
);

my $default_restapi = \&get_ctsms_restapi;
my $get_complete_path_query = sub {
    my ($street_name_infix, $country_name, $province, $city_name, $zip_code, $limit) = @_;
    my %params = (streetNameInfix => $street_name_infix);
    $params{countryName} = $country_name if defined $country_name;
    $params{zipCode} = $zip_code if defined $zip_code;
    $params{cityName} = $city_name if defined $city_name;
    $params{province} = $province if length($province);
    $params{limit} = $limit if defined $limit;
    return 'tools/complete/streetname/' . get_query_string(\%params);
};

my $fieldnames = [
    'streetname',
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub complete_street_name {

    my ($street_name_infix, $country_name, $province, $city_name,$zip_code, $limit, $load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_complete_path_query($street_name_infix, $country_name, $province, $city_name,$zip_code, $limit),$headers),$load_recursive,$restapi);

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
        value => $self->{streetname},
        label => $self->{streetname},
    };

}

1;
