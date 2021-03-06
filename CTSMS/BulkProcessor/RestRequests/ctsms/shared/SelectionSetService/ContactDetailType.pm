package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ContactDetailType;
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

    get_proband_items
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'selectionset/contactdetailtype/' . get_query_string({ typeId => $id });
};
my $get_proband_item_path_query = sub {
    my ($person,$animal) = @_;
    my %params = ();
    $params{person} = booltostring($person) if defined $person;
    $params{animal} = booltostring($animal) if defined $animal;
    return 'selectionset/availableprobandcontactdetailtypes/' . get_query_string(\%params);
};
my $get_staff_item_path_query = sub {
    return 'selectionset/availablestaffcontactdetailtypes/';
};

my $fieldnames = [
    "email",
    "id",
    "maxOccurrence",
    "mismatchMsgL10nKey",
    "name",
    "nameL10nKey",
    "notifyPreset",
    "phone",
    "proband",
    "animal",
    "business",
    "regExp",
    "staff",
    "url",
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

sub get_proband_items {

    my ($person,$animal,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_proband_item_path_query($person,$animal),$headers),$load_recursive,$restapi);

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
