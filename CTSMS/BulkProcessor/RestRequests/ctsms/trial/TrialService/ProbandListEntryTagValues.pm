package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues;
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

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValue qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagJsonValue qw();


require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    get_probandlistentrytagvalues
    set_probandlistentrytagvalues

);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($listentry_id, $tag_id) = @_;
    return 'probandlistentry/' . $listentry_id . '/tagvalue/' . $tag_id;
};
my $get_getprobandlistentrytagvalues_path_query = sub {
    my ($listentry_id, $sort, $load_all_js_values) = @_;
    my %params = ();
    $params{load_all_js_values} = booltostring($load_all_js_values);
    $params{sort} = booltostring($sort);
    return 'probandlistentry/' . $listentry_id . '/tagvalues' . get_query_string(\%params);
};

my $get_setprobandlistentrytagvalues_path_query = sub {
    my ($force) = @_;
    my %params = ();
    $params{force} = booltostring($force) if defined $force;
    return 'probandlistentrytagvalue/' . get_query_string(\%params);
};

my $fieldnames = [
    "rows",
    "js_rows",
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub get_item {

    my ($listentry_id, $tag_id,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_item_path_query($listentry_id, $tag_id),$headers),$load_recursive,$restapi);

}

sub get_probandlistentrytagvalues {

    my ($listentry_id, $sort, $load_all_js_values, $p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_getprobandlistentrytagvalues_path_query($listentry_id, $sort, $load_all_js_values),$p,$sf),$headers),$p),$load_recursive,$restapi);

}

sub set_probandlistentrytagvalues {

    my ($in,$force,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->put(&$get_setprobandlistentrytagvalues_path_query($force),$in,$headers),$load_recursive,$restapi);

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

    $item->{rows} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValue::builditems_fromrows($item->{rows},$load_recursive,$restapi);
    $item->{js_rows} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagJsonValue::builditems_fromrows($item->{js_rows},$load_recursive,$restapi);

}

#sub get_item_path {
#
#   my ($id) = @_;
#    return &$get_item_path_query($id);
#
#}

1;
