package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::VisitScheduleItem;
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

use CTSMS::BulkProcessor::Utils qw(booltostring);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    get_trial_list
    get_interval
);


my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'visitscheduleitem/' . $id;
};
my $get_trial_path_query = sub {
    my ($trial_id,$sort) = @_;
    my %params = ();


    $params{sort} = booltostring($sort);
    return 'trial/' . $trial_id . '/list/visitscheduleitem' . get_query_string(\%params);
};
my $get_interval_path_query = sub {
    my ($trial_id,$from,$to,$sort) = @_;
    my %params = ();
    $params{trial_id} = $trial_id if defined $trial_id;
    $params{from} = $from if defined $from;
    $params{to} = $from if defined $to;
    $params{sort} = booltostring($sort);
    return 'visitscheduleitem/interval' . get_query_string(\%params);
};

my $fieldnames = [
    "group",
    "id",
    "modifiedTimestamp",
    "modifiedUser",
    "name",
    "notify",
    "start",
    "stop",
    "token",
    "trial",
    "version",
    "visit",
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

sub get_trial_list {

    my ($trial_id,$sort,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_trial_path_query($trial_id,$sort),$p,$sf),$headers),$p),$load_recursive,$restapi);

}

sub get_interval {

    my ($trial_id,$from,$to,$sort,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_interval_path_query($trial_id,$from,$to,$sort),$headers),$load_recursive,$restapi);

}


sub builditems_fromrows {

    my ($rows,$load_recursive,$restapi) = @_;

    my $item;

    if (defined $rows and ref $rows eq 'ARRAY') {
        my @items = ();
        foreach my $row (@$rows) {
            $item = __PACKAGE__->new($row);

            # transformations go here ...
            $item->{proband} = $row->{proband} if exists $row->{proband};

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
