package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionProperty;
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
    get_items

    $NONE
    $LONG
    $LONG_HASH
    $FLOAT
    $FLOAT_HASH
    $STRING
    $STRING_HASH
    $BOOLEAN
    $BOOLEAN_HASH
    $DATE
    $DATE_HASH
    $TIME
    $TIME_HASH
    $TIMESTAMP
    $TIMESTAMP_HASH
);

our $NONE = 'NONE';
our $LONG = 'LONG';
our $LONG_HASH = 'LONG_HASH';
our $FLOAT = 'FLOAT';
our $FLOAT_HASH = 'FLOAT_HASH';
our $STRING = 'STRING';
our $STRING_HASH = 'STRING_HASH';
our $BOOLEAN = 'BOOLEAN';
our $BOOLEAN_HASH = 'BOOLEAN_HASH';
our $DATE = 'DATE';
our $DATE_HASH = 'DATE_HASH';
our $TIME = 'TIME';
our $TIME_HASH = 'TIME_HASH';
our $TIMESTAMP = 'TIMESTAMP';
our $TIMESTAMP_HASH = 'TIMESTAMP_HASH';

my $default_restapi = \&get_ctsms_restapi;
my $get_items_path_query = sub {
    my ($module) = @_;
    return 'selectionset/criterionproperties/' . get_query_string({ module => $module });
};


my $fieldnames = [
    "completeMethodName",
    "converter",
    "entityName",
    "filterItemsName",
    "getNameMethodName",
    "getValueMethodName",
    "id",
    "module",
    "name",
    "nameL10nKey",
    "picker",
    "property",
    "selectionSetServiceMethodName",
    "validRestrictions",
    "valueType",
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub get_items {

    my ($module,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_items_path_query($module),$headers),$load_recursive,$restapi);

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


1;
