package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf;
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
    get_getecrffieldvaluessectionmaxindex
);


my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'ecrf/' . $id;
};
my $get_trial_path_query = sub {
    my ($trial_id,$sort) = @_;
    my %params = ();
    $params{sort} = booltostring($sort);

    return 'trial/' . $trial_id . '/list/ecrf' . get_query_string(\%params);
};
my $get_getecrffieldvaluessectionmaxindex_path_query = sub {
    my ($ecrf_id, $visit_id, $section) = @_;
    my %params = ();
    $params{section} = $section;
    $params{visit_id} = $visit_id if defined $visit_id;
    return 'ecrf/' . $ecrf_id . '/ecrffieldvalues/maxindex' . get_query_string(\%params);
};


my $fieldnames = [
    "active",
    "description",
    "disabled",
    "enableBrowserFieldCalculation",
    "externalId",
    "groups",
    "id",
    "modifiedTimestamp",
    "modifiedUser",
    "name",
    "revision",
    "probandListStatus",
    "title",
    "trial",
    "uniqueName",
    "version",
    "visits",
    "deferredDelete",
    "deferredDeleteReason",
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

sub get_getecrffieldvaluessectionmaxindex {

    my ($ecrf_id, $visit_id, $section, $restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get(&$get_getecrffieldvaluessectionmaxindex_path_query($ecrf_id, $visit_id, $section),$headers);

}

sub builditems_fromrows {

    my ($rows,$load_recursive,$restapi) = @_;

    my $item;

    if (defined $rows and ref $rows eq 'ARRAY') {
        my @items = ();
        foreach my $row (@$rows) {
            $item = __PACKAGE__->new($row);

            # transformations go here ...
            transformitem($item,$load_recursive,$restapi);

            push @items,$item;
        }
        return \@items;
    } elsif (defined $rows and ref $rows eq 'HASH') {
        $item = __PACKAGE__->new($rows);
        transformitem($item,$load_recursive,$restapi);
        return $item;
    }
    return undef;

}

sub transformitem {
    my ($item,$load_recursive,$restapi) = @_;

}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

1;
