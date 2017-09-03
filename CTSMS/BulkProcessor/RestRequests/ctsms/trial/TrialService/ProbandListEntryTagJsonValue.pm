package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagJsonValue;
use strict;

## no critic

#use CTSMS::BulkProcessor::ConnectorPool qw(
#    get_ctsms_restapi
#
#);

use CTSMS::BulkProcessor::RestProcessor qw(
    copy_row
    get_query_string
);

#use CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi qw(_get_api);
use CTSMS::BulkProcessor::RestItem qw();

use CTSMS::BulkProcessor::Array qw(array_to_map);
#use CTSMS::BulkProcessor::Utils qw(booltostring);
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputFieldSelectionSetValue qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    
);
#   get_item
#   get_item_path
 

#my $default_restapi = \&get_ctsms_restapi;
#my $get_item_path_query = sub {
#    my ($id) = @_;
#    return 'inquiryvalue/' . $id;
#};

my $fieldnames = [
    "booleanValue",
    "dateValue",
    "disabled",
    "floatValue",
    "id",
    "inkValues",
    "inputFieldId",
    "inputFieldName",
    "inputFieldSelectionSetValues",
    "inputFieldType",
    "tagId",
    "jsOutputExpression",
    "jsValueExpression",
    "jsVariableName",
    "longValue",
    "position",
    "selectionValueIds",
    "textValue",
    "timeValue",
    "timestampValue",
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

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
    #$item->{inputFieldSelectionSetValues} = CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputFieldSelectionSetValue::builditems_fromrows($item->{inputFieldSelectionSetValues},$load_recursive,$restapi);
    #$item->{inkValues} = utf8bytes_to_string($item->{inkValues});
    if ($load_recursive) {
        $load_recursive = {} unless ref $load_recursive;
        my $field = "_inputFieldSelectionSelectionSetValueMap";
        if ($load_recursive->{$field}) {
            ($item->{$field}, my $ids, my $items) = array_to_map($item->{inputFieldSelectionSetValues},sub { my $item = shift; return $item->{id}; },undef,'last');
        }
    }

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
