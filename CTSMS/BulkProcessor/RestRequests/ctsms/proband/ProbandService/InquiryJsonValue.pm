package CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryJsonValue;
use strict;

## no critic

use CTSMS::BulkProcessor::RestProcessor qw(
    copy_row
    get_query_string
);

use CTSMS::BulkProcessor::RestItem qw();

use CTSMS::BulkProcessor::Array qw(array_to_map);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputFieldSelectionSetValue qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(

);

my $fieldnames = [
    "booleanValue",
    "dateValue",
    "disabled",
    "floatValue",
    "id",
    "inkValues",
    "inputFieldId",
    "inputFieldName",
    "category",
    "inputFieldSelectionSetValues",
    "inputFieldType",
    "inquiryId",
    "jsOutputExpression",
    "jsValueExpression",
    "jsVariableName",
    "longValue",
    "position",
    "selectionValueIds",
    "textValue",
    "timeValue",
    "timestampValue",
    "userTimeZone",
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

    if ($load_recursive) {
        $load_recursive = {} unless ref $load_recursive;
        my $field = "_inputFieldSelectionSelectionSetValueMap";
        if ($load_recursive->{$field}) {
            ($item->{$field}, my $ids, my $items) = array_to_map($item->{inputFieldSelectionSetValues},sub { my $item = shift; return $item->{id}; },undef,'last');
        }
    }

}

sub TO_JSON {

    my $self = shift;
    return { %{$self} };

}

1;
