package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::MimeType;
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

    $INPUT_FIELD_VALUE_FILE_MODULE
);

our $INPUT_FIELD_VALUE_FILE_MODULE = 'INPUT_FIELD_VALUE_FILE';

my $default_restapi = \&get_ctsms_restapi;
my $get_items_path_query = sub {
    my ($module) = @_;
    my %params = ();
    $params{module} = $module if defined $module;
    return 'selectionset/mimetypes' . get_query_string(\%params);
};

my $fieldnames = [
    "id",
    "mimeType",
    "module",
    "fileNameExtensions",
    "image",
    "nodeStyleClass",
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

sub TO_JSON {

    my $self = shift;
    return { %{$self} };

}

1;
