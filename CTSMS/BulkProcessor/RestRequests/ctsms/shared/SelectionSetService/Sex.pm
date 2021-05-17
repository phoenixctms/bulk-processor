package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::Sex;
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

    $NOT_KNOWN
    $MALE
    $FEMALE
    $TRANSGENDER_MALE
    $TRANSGENDER_FEMALE
    $NOT_APPLICABLE
);

our $NOT_KNOWN = 'NOT_KNOWN'; # ("0"),
our $MALE = 'MALE'; # ("1"),
our $FEMALE = 'FEMALE'; # ("2"),
our $TRANSGENDER_MALE = 'TRANSGENDER_MALE'; # ("3"),
our $TRANSGENDER_FEMALE = 'TRANSGENDER_FEMALE'; # ("4"),
our $NOT_APPLICABLE = 'NOT_APPLICABLE'; # ("9");

my $default_restapi = \&get_ctsms_restapi;
my $get_items_path_query = sub {
    return 'selectionset/sexes/';
};

my $fieldnames = [
    "sex",
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
