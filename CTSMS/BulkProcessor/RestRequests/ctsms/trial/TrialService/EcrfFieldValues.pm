package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValues;
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

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValue qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldJsonValue qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    get_ecrffieldvalues
    set_ecrffieldvalues

    get_getecrffieldvaluessectionmaxindex
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($listentry_id, $visit_id, $ecrffield_id, $index) = @_;
    my %params = ();
    $params{visit_id} = $visit_id if defined $visit_id;
    $params{index} = $index if defined $index;
    return 'ecrfstatusentry/' . $listentry_id . '/ecrffieldvalue/' . $ecrffield_id . get_query_string(\%params);
};
my $get_getecrffieldvalues_path_query = sub {
    my ($listentry_id, $ecrf_id, $visit_id, $load_all_js_values, $tz) = @_;
    my %params = ();
    $params{load_all_js_values} = booltostring($load_all_js_values);
    $params{visit_id} = $visit_id if defined $visit_id;
    $params{tz} = $tz if $tz;
    return 'ecrfstatusentry/' . $listentry_id . '/' . $ecrf_id . '/ecrffieldvalues' . get_query_string(\%params);
};

my $get_setecrffieldvalues_path_query = sub {
    my ($force,$tz) = @_;
    my %params = ();
    $params{force} = booltostring($force) if defined $force;
    $params{tz} = $tz if $tz;
    return 'ecrffieldvalue/' . get_query_string(\%params);
};

my $get_getecrffieldvaluessectionmaxindex_path_query = sub {
    my ($listentry_id, $ecrf_id, $visit_id, $section) = @_;
    my %params = ();
    $params{section} = $section;
    $params{visit_id} = $visit_id if defined $visit_id;
    return 'ecrfstatusentry/' . $listentry_id . '/' . $ecrf_id . '/ecrffieldvalues/maxindex' . get_query_string(\%params);
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

    my ($listentry_id, $visit_id, $ecrffield_id, $index,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_item_path_query($listentry_id, $visit_id, $ecrffield_id, $index),$headers),$load_recursive,$restapi);

}

sub get_ecrffieldvalues {

    my ($listentry_id, $ecrf_id, $visit_id, $load_all_js_values, $tz, $p, $sf, $load_recursive, $restapi, $headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_getecrffieldvalues_path_query($listentry_id, $ecrf_id, $visit_id, $load_all_js_values, $tz),$p,$sf),$headers),$p),$load_recursive,$restapi);

}

sub set_ecrffieldvalues {

    my ($in,$force,$tz,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->put(&$get_setecrffieldvalues_path_query($force,$tz),$in,$headers),$load_recursive,$restapi);

}

sub get_getecrffieldvaluessectionmaxindex {

    my ($listentry_id, $ecrf_id, $visit_id, $section, $restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get(&$get_getecrffieldvaluessectionmaxindex_path_query($listentry_id, $ecrf_id, $visit_id, $section),$headers);

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

    $item->{rows} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValue::builditems_fromrows($item->{rows},$load_recursive,$restapi);
    $item->{js_rows} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldJsonValue::builditems_fromrows($item->{js_rows},$load_recursive,$restapi);

}

#sub get_item_path {
#
#    my ($id) = @_;
#    return &$get_item_path_query($id);
#
#}

1;
