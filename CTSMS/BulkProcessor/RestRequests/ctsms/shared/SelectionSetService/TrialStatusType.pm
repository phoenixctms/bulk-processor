package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::TrialStatusType;
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

    get_initial_items
    get_transition_items
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'selectionset/trialstatustype/' . get_query_string({ typeId => $id });
};
my $get_initial_items_path_query = sub {
    return 'selectionset/initialtrialstatustypes';
};
my $get_transition_items_path_query = sub {
    my ($id) = @_;
    return 'selectionset/trialstatustypetransitions/' . get_query_string({ typeId => $id });
};
#my $collection_path_query = 'api/' . $resource . '/';

my $fieldnames = [
    "actions",
    "color",
    "id",
    "ignoreTimelineEvents",
    "initial",
    "inquiryValueInputEnabled",
    "ecrfValueInputEnabled",
    "lockdown",
    "name",
    "nameL10nKey",
    "nodeStyleClass",
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

sub get_initial_items {

    my ($load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_initial_items_path_query(),$headers),$load_recursive,$restapi);

}

sub get_transition_items {

    my ($id,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_transition_items_path_query($id),$headers),$load_recursive,$restapi);

}

#sub get_itemX {
#
#    my ($filters,$load_recursive,$headers) = @_;
#    my $restapi = &$default_restapi();
#    return builditems_fromrows($restapi->extract_collection_items($restapi->get(&$get_item_filter_path_query($filters),$headers),undef,undef,
#        { $CTSMS::BulkProcessor::RestConnectors::CTSMSRestApi::ITEM_REL_PARAM => $item_relation }),$load_recursive)->[0];
#
#}

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

1;
