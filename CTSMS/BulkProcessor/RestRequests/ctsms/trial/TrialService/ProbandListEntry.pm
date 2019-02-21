package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntry;
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

    addsignup_item
    add_item
    get_trial_list
);


my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'probandlistentry/' . $id;
};
my $get_trial_path_query = sub {
    my ($trial_id, $probandgroup_id,$proband_id,$total) = @_;
    my %params = ();
    $params{probandGroupId} = $probandgroup_id if defined $probandgroup_id;
    $params{probandId} = $proband_id if defined $proband_id;
    $params{total} = booltostring($total); # if defined $proband_id;
    return 'trial/' . $trial_id . '/list/probandlistentry' . get_query_string(\%params);
};
my $get_addsignup_path_query = sub {
    my ($randomize) = @_;
    my %params = ();
    $params{randomize} = booltostring($randomize) if defined $randomize;
    return 'probandlistentry/signup/' . get_query_string(\%params);
};
my $get_add_path_query = sub {
    my ($randomize) = @_;
    my %params = ();
    $params{randomize} = booltostring($randomize) if defined $randomize;
    return 'probandlistentry/' . get_query_string(\%params);
};
#my $get_update_path_query = sub {
#    return 'probandlistentry/';
#};

my $fieldnames = [
    "exportResponseMsg",
    "exportStatus",
    "exportTimestamp",
    "group",
    "id",
    "lastStatus",
    "modifiedTimestamp",
    "modifiedUser",
    "position",
    "proband",
    "trial",
    "version",
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

sub addsignup_item {

    my ($in,$randomize,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->post(&$get_addsignup_path_query($randomize),$in,$headers),$load_recursive,$restapi);

}

sub add_item {

    my ($in,$randomize,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->post(&$get_add_path_query($randomize),$in,$headers),$load_recursive,$restapi);

}

sub get_trial_list {

    my ($trial_id,$probandgroup_id,$proband_id,$total,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_trial_path_query($trial_id,$probandgroup_id,$proband_id,$total),$p,$sf),$headers),$p),$load_recursive,$restapi);

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
    #    value => $self->{zipcode},
    #    label => $self->{zipcode},
    #};

}

1;
