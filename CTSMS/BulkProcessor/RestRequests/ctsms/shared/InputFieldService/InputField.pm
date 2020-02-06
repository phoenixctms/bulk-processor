package CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputField;
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


use CTSMS::BulkProcessor::Array qw(array_to_map);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputFieldSelectionSetValue qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::InputFieldType qw(
    $SINGLE_LINE_TEXT
    $MULTI_LINE_TEXT
    $AUTOCOMPLETE

    $SELECT_ONE_DROPDOWN
    $SELECT_ONE_RADIO_H
    $SELECT_ONE_RADIO_V
    $SELECT_MANY_H
    $SELECT_MANY_V

    $SKETCH
);








require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'inputfield/' . $id;
};

my $fieldnames = [
    "booleanPreset",
    "category",
    "comment",
    "commentL10nKey",
    "datePreset",
    "externalId",
    "fieldType",
    "floatLowerLimit",
    "floatPreset",
    "floatUpperLimit",
    "hasImage",
    "height",
    "id",
    "learn",
    "localized",
    "longLowerLimit",
    "longPreset",
    "longUpperLimit",
    "maxDate",
    "maxSelections",
    "maxTime",
    "maxTimestamp",
    "minDate",
    "minSelections",
    "minTime",
    "minTimestamp",
    "modifiedTimestamp",
    "modifiedUser",
    "name",
    "nameL10nKey",
    "regExp",
    "selectionSetValues",
    "strict",
    "textPreset",
    "textPresetL10nKey",
    "timePreset",
    "timestampPreset",
    "title",
    "titleL10nKey",
    "validationErrorMsg",
    "validationErrorMsgL10nKey",
    "version",
    "width",
    "deferredDelete",
    "deferredDeleteReason",
    "userTimeZone",
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
    $item->{selectionSetValues} = CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputFieldSelectionSetValue::builditems_fromrows($item->{selectionSetValues},$load_recursive,$restapi);
    if ($load_recursive) {
        $load_recursive = {} unless ref $load_recursive;
        my $field = "_selectionSetValueMap";
        if ($load_recursive->{$field}) {
            ($item->{$field}, my $ids, my $items) = array_to_map($item->{selectionSetValues},sub { my $item = shift; return $item->{id}; },undef,'last');
        }
    }
}

sub is_select {
    my $self = shift;
    my $fieldtype = $self->{fieldType}->{nameL10nKey};
    if ($SELECT_ONE_RADIO_V eq $fieldtype or $SELECT_ONE_RADIO_H eq $fieldtype
             or $SELECT_ONE_DROPDOWN eq $fieldtype or $SKETCH eq $fieldtype
             or $SELECT_MANY_V eq $fieldtype or $SELECT_MANY_H eq $fieldtype) {
        return 1;
    }
    return 0;
}

sub is_text {
    my $self = shift;
    my $fieldtype = $self->{fieldType}->{nameL10nKey};
    if ($SINGLE_LINE_TEXT eq $fieldtype or $MULTI_LINE_TEXT eq $fieldtype or $AUTOCOMPLETE eq $fieldtype) {
        return 1;
    }
    return 0;
}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

sub TO_JSON {

    my $self = shift;
    return { %{$self} };




}

1;
