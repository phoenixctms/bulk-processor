package CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::ProbandAddress;
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
    get_item
    get_item_path

    add_item
    update_item
    render_probandletter
    get_probandletterpdfvo
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'probandaddress/' . $id;
};
my $get_add_path_query = sub {
    return 'probandaddress/';
};
my $get_update_path_query = sub {
    return 'probandaddress/';
};
my $get_renderprobandletter_path_query = sub {
    my ($id) = @_;
    return 'probandaddress/' . $id . '/probandletterpdf';
};
my $get_probandletterpdfvo_path_query = sub {
    my ($id) = @_;
    return 'probandaddress/' . $id . '/probandletterpdf/head';
};

my $fieldnames = [
    "afnus",
    "careOf",
    "cityName",
    "civicName",
    "countryName",
    "decrypted",
    "deliver",
    "doorNumber",
    "entrance",
    "houseNumber",
    "id",
    "modifiedTimestamp",
    "modifiedUser",
    "name",
    "proband",
    "streetName",
    "type",
    "version",
    "wireTransfer",
    "zipCode",
    "province",
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub get_item {

    my ($id,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_item_path_query($id),$headers),$load_recursive,$restapi);

}

sub add_item {

    my ($in,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->post(&$get_add_path_query(),$in,$headers),$load_recursive,$restapi);

}

sub update_item {

    my ($in,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->put(&$get_update_path_query(),$in,$headers),$load_recursive,$restapi);

}

sub render_probandletter {

    my ($proband_address_id,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get_file(&$get_renderprobandletter_path_query($proband_address_id),$headers);

}

sub get_probandletterpdfvo {

    my ($proband_address_id,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get(&$get_probandletterpdfvo_path_query($proband_address_id));

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

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

sub TO_JSON {

    my $self = shift;
    return { %{$self} };

}

1;
