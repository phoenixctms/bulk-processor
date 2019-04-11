package CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteInputFieldSelectionSetValueValue;
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
    complete_input_field_selection_set_value_value
);

my $default_restapi = \&get_ctsms_restapi;
my $get_complete_path_query = sub {
    my ($value_infix, $input_field_id, $limit) = @_;
    my %params = ();
    $params{valueInfix} = $value_infix if defined $value_infix;
    $params{inputFieldId} = $input_field_id if defined $input_field_id;
    $params{limit} = $limit if defined $limit;
    return 'tools/complete/inputfieldselectionsetvaluevalue/' . get_query_string(\%params);
};

my $fieldnames = [
    'value',
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub complete_input_field_selection_set_value_value {

    my ($value_infix, $input_field_id, $limit, $load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_complete_path_query($value_infix, $input_field_id, $limit),$headers),$load_recursive,$restapi);

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

sub TO_JSON {

    my $self = shift;
    return {
        value => $self->{value},
        label => $self->{value},
    };

}

1;
