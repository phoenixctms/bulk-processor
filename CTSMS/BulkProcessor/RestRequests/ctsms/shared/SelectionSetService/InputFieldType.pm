package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::InputFieldType;
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

    $SINGLE_LINE_TEXT
    $MULTI_LINE_TEXT
    $AUTOCOMPLETE
    $CHECKBOX
    $DATE
    $TIME
    $TIMESTAMP
    $SELECT_ONE_DROPDOWN
    $SELECT_ONE_RADIO_H
    $SELECT_ONE_RADIO_V
    $SELECT_MANY_H
    $SELECT_MANY_V
    $INTEGER
    $SKETCH
    $FLOAT
);

our $SINGLE_LINE_TEXT = 'SINGLE_LINE_TEXT';
our $MULTI_LINE_TEXT = 'MULTI_LINE_TEXT';
our $AUTOCOMPLETE = 'AUTOCOMPLETE';
our $CHECKBOX = 'CHECKBOX';
our $DATE = 'DATE';
our $TIME = 'TIME';
our $TIMESTAMP = 'TIMESTAMP';
our $SELECT_ONE_DROPDOWN = 'SELECT_ONE_DROPDOWN';
our $SELECT_ONE_RADIO_H = 'SELECT_ONE_RADIO_H';
our $SELECT_ONE_RADIO_V = 'SELECT_ONE_RADIO_V';
our $SELECT_MANY_H = 'SELECT_MANY_H';
our $SELECT_MANY_V = 'SELECT_MANY_V';
our $INTEGER = 'INTEGER';
our $SKETCH = 'SKETCH';
our $FLOAT = 'FLOAT';

my $default_restapi = \&get_ctsms_restapi;
my $get_items_path_query = sub {
    return 'selectionset/inputfieldtypes/';
};

my $fieldnames = [
    "type",
    "name",
    "nameL10nKey",
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub get_items {

    my ($load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_items_path_query(),$headers),$load_recursive,$restapi);

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
