package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfFieldValue;
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

use CTSMS::BulkProcessor::Utils qw(utf8bytes_to_string booltostring);
use CTSMS::BulkProcessor::Array qw(array_to_map);

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputFieldSelectionSetValue qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path
    
    clear
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'ecrffieldvalue/' . $id;
};
my $get_clear_path_query = sub {
    my ($listentry_id, $ecrf_id) = @_;
    return 'ecrfstatusentry/' . $listentry_id . '/' . $ecrf_id . '/ecrffieldvalues';
};

my $fieldnames = [
    "booleanValue",
    "changeComment",
    "dateValue",
    "ecrfField",
    "floatValue",
    "id",
    "index",
    "inkValues",
    "lastFieldStatus",
    "lastUnresolvedFieldStatusEntry",
    "listEntry",
    "longValue",
    "modifiedTimestamp",
    "modifiedUser",
    "reasonForChange",
    "selectionValues",
    "textValue",
    "timeValue",
    "timestampValue",
    "version",

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

sub clear {

    my ($listentry_id, $ecrf_id, $restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->delete(&$get_clear_path_query($listentry_id, $ecrf_id),$headers));

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
    $item->{ecrfField} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::builditems_fromrows($item->{ecrfField},$load_recursive,$restapi);
    $item->{inkValues} = utf8bytes_to_string($item->{inkValues});
    $item->{selectionValues} = CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputFieldSelectionSetValue::builditems_fromrows($item->{selectionValues},$load_recursive,$restapi);
    if ($load_recursive) {
        $load_recursive = {} unless ref $load_recursive;
        my $field = "_selectionValueMap";
        if ($load_recursive->{$field}) {
            ($item->{$field}, my $ids, my $items) = array_to_map($item->{selectionValues},sub { my $item = shift; return $item->{id}; },undef,'last');
        }
        $field = "_value";
        if ($load_recursive->{$field}) {
            $item->{$field} = _get_item_value($item);
        }
    }
    
}

sub _get_item_value {
    my $item = shift;
    my $fieldtype = $item->{ecrfField}->{field}->{fieldType}->{nameL10nKey};
    if ('CHECKBOX' eq $fieldtype) {
        return booltostring($item->{booleanValue});
    } elsif ('DATE' eq $fieldtype) {
        return $item->{dateValue};
    } elsif ('TIME' eq $fieldtype) {
        return $item->{timeValue};
    } elsif ('TIMESTAMP' eq $fieldtype) {
        return $item->{timestampValue};        
    } elsif ('FLOAT' eq $fieldtype) {
        return $item->{floatValue};
    } elsif ('INTEGER' eq $fieldtype) {
        return $item->{longValue};
    } elsif ($item->{ecrfField}->{field}->is_text()) {
        return $item->{textValue};
    } elsif ($item->{ecrfField}->{field}->is_select()) {
        return join(',', map { local $_ = $_; $_->{value}; } @{$item->{selectionValues}}) if defined $item->{selectionValues};
    }
    return undef;  
}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

#sub TO_JSON {
#    
#    my $self = shift;
#    return { %{$self} };
#    #    value => $self->{zipcode},
#    #    label => $self->{zipcode},
#    #};
#
#}

1;
