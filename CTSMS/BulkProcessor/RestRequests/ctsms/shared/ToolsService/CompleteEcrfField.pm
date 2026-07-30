package CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::CompleteEcrfField;
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
    complete_ecrf_field
);

my $default_restapi = \&get_ctsms_restapi;
my $get_complete_path_query = sub {
    my ($name_infix, $limit) = @_;
    my %params = ();
    $params{nameInfix} = $name_infix if defined $name_infix;
    $params{limit} = $limit if defined $limit;
    return 'tools/complete/ecrffield/' . get_query_string(\%params);
};

my $fieldnames = [
    'id',
    'name',
    'uniqueName',
    'title',
    'titleL10nKey',
    'externalId',
    'value',
    'label',
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub complete_ecrf_field {

    my ($name_infix, $limit, $load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_complete_path_query($name_infix, $limit),$headers),$load_recursive,$restapi);

}

sub builditems_fromrows {

    my ($rows,$load_recursive,$restapi) = @_;

    my $item;

    if (defined $rows and ref $rows eq 'ARRAY') {
        my @items = ();
        foreach my $row (@$rows) {
            $item = __PACKAGE__->new($row);
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
    my $label = $self->{label} // $self->{uniqueName} // $self->{title} // $self->{name} // $self->{id};
    my $value = $self->{value} // $self->{id};
    return {
        value => $value,
        label => $label,
    };

}

1;
