package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::EcrfFieldStatusType;
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

    $ANNOTATION_QUEUE
    $VALIDATION_QUEUE
    $QUERY_QUEUE
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'selectionset/ecrffieldstatustype/' . get_query_string({ typeId => $id });
};
my $get_initial_items_path_query = sub {
    my ($queue) = @_;
    return 'selectionset/initialecrffieldstatustypes/' . get_query_string({ queue => $queue });
};
my $get_transition_items_path_query = sub {
    my ($id) = @_;
    return 'selectionset/ecrffieldstatustypetransitions/' . get_query_string({ typeId => $id, 'system' => 'false' });
};


my $fieldnames = [
    "color",
    "commentRequired",
    "id",
    "initial",
    "name",
    "nameL10nKey",
    "resolved",
    "system",
];

our $ANNOTATION_QUEUE = 'ANNOTATION';
our $VALIDATION_QUEUE = 'VALIDATION';
our $QUERY_QUEUE = 'QUERY';
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

    my ($queue,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_initial_items_path_query($queue),$headers),$load_recursive,$restapi);

}

sub get_transition_items {

    my ($id,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_transition_items_path_query($id),$headers),$load_recursive,$restapi);

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

1;
