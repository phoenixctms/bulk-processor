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

#use CTSMS::BulkProcessor::Utils qw(booltostring);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_items
    
    $INVENTOY_DB
    $STAFF_DB
    $COURSE_DB
    $TRIAL_DB
    $PROBAND_DB
    $USER_DB
    $INPUT_FIELD_DB
);

my $default_restapi = \&get_ctsms_restapi;
my $get_items_path_query = sub {
    my ($module) = @_;
    return 'selectionset/criterionproperties/' . get_query_string({ module => $module });
};
#my $collection_path_query = 'api/' . $resource . '/';

my $fieldnames = [
    "completeMethodName",
    "converter",
    "entityName",
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

our $INVENTOY_DB = 'INVENTOY_DB';
our $STAFF_DB = 'STAFF_DB';
our $COURSE_DB = 'COURSE_DB';
our $TRIAL_DB = 'TRIAL_DB';
our $PROBAND_DB = 'PROBAND_DB';
our $USER_DB = 'USER_DB';
our $INPUT_FIELD_DB = 'INPUT_FIELD_DB';

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
