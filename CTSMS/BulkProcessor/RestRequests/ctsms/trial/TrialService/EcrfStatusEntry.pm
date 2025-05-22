package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfStatusEntry;
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

    render_ecrf
    get_ecrfpdfvo
);


my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($listentry_id,$ecrf_id,$visit_id) = @_;
    my %params = ();
    $params{visit_id} = $visit_id if defined $visit_id;
    return 'ecrfstatusentry/' . $listentry_id . '/' . $ecrf_id . get_query_string(\%params);
};
my $get_renderecrf_path_query = sub {
    my ($listentry_id,$ecrf_id,$visit_id,$done,$blank) = @_;
    my %params = ();
    $params{done} = booltostring($done) if defined $done;
    $params{blank} = booltostring($blank);
    $params{visit_id} = $visit_id if defined $visit_id;
    return 'ecrfstatusentry/' . $listentry_id . '/ecrfpdf' . ((defined $ecrf_id) ? '/' . $ecrf_id : '') . get_query_string(\%params);;
};
my $get_ecrfpdfvo_path_query = sub {
    my ($listentry_id,$ecrf_id,$visit_id,$done,$blank) = @_;
    my %params = ();
    $params{done} = booltostring($done) if defined $done;
    $params{blank} = booltostring($blank);
    $params{visit_id} = $visit_id if defined $visit_id;
    return 'ecrfstatusentry/' . $listentry_id . '/ecrfpdf' . ((defined $ecrf_id) ? '/' . $ecrf_id : '') . '/head' . get_query_string(\%params);;
};

my $fieldnames = [
    "ecrf",
    "exportResponseMsg",
    "exportStatus",
    "exportTimestamp",
    "id",
    "listEntry",
    "modifiedTimestamp",
    "modifiedUser",
    "status",
    "validationResponseMsg",
    "validationStatus",
    "validationTimestamp",
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

    my ($listentry_id,$ecrf_id,$visit_id,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_item_path_query($listentry_id,$ecrf_id,$visit_id),$headers),$load_recursive,$restapi);

}

sub render_ecrf {

    my ($listentry_id,$ecrf_id,$visit_id,$done,$blank,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get_file(&$get_renderecrf_path_query($listentry_id,$ecrf_id,$visit_id,$done,$blank),$headers);

}

sub get_ecrfpdfvo {

    my ($listentry_id,$ecrf_id,$visit_id,$done,$blank,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get(&$get_ecrfpdfvo_path_query($listentry_id,$ecrf_id,$visit_id,$done,$blank),$headers);

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

#sub get_item_path {
#
#    my ($id) = @_;
#    return &$get_item_path_query($id);
#
#}

1;
