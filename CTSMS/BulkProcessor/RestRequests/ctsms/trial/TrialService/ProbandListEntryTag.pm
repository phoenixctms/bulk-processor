package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTag;
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

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputField qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    get_trial_list
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'probandlistentrytag/' . $id;
};
my $get_trial_path_query = sub {
    my ($trial_id,$stratification) = @_;
    my %params = ();
    $params{stratification} = booltostring($stratification) if defined $stratification;
    return 'trial/' . $trial_id . '/list/probandlistentrytag' . get_query_string(\%params);
};

my $fieldnames = [
    "comment",
    "disabled",
    "excelDate",
    "excelValue",
    "ecrfValue",
    "externalId",
    "field",
    "id",
    "jsOutputExpression",
    "jsValueExpression",
    "jsVariableName",
    "modifiedTimestamp",
    "modifiedUser",
    "optional",
    "position",
    "trial",
    "uniqueName",
    "version",
    "stratification",
    "randomize",
    "title",
    "titleL10nKey",
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

    my ($trial_id,$stratification,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_trial_path_query($trial_id,$stratification),$p,$sf),$headers),$p),$load_recursive,$restapi);

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
    $item->{field} = CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputField::builditems_fromrows($item->{field},$load_recursive,$restapi);

}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

1;
