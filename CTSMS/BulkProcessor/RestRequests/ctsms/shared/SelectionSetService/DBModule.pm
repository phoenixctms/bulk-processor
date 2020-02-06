package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule;
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

    $INVENTORY_DB
    $STAFF_DB
    $COURSE_DB
    $TRIAL_DB
    $PROBAND_DB
    $USER_DB
    $INPUT_FIELD_DB
    $MASS_MAIL_DB

    @DB_MODULES
);

our @DB_MODULES = ();
our $INVENTORY_DB = 'INVENTORY_DB';
push(@DB_MODULES,$INVENTORY_DB);
our $STAFF_DB = 'STAFF_DB';
push(@DB_MODULES,$STAFF_DB);
our $COURSE_DB = 'COURSE_DB';
push(@DB_MODULES,$COURSE_DB);
our $TRIAL_DB = 'TRIAL_DB';
push(@DB_MODULES,$TRIAL_DB);
our $PROBAND_DB = 'PROBAND_DB';
push(@DB_MODULES,$PROBAND_DB);
our $USER_DB = 'USER_DB';
push(@DB_MODULES,$USER_DB);
our $INPUT_FIELD_DB = 'INPUT_FIELD_DB';
push(@DB_MODULES,$INPUT_FIELD_DB);
our $MASS_MAIL_DB = 'MASS_MAIL_DB';
push(@DB_MODULES,$MASS_MAIL_DB);

my $default_restapi = \&get_ctsms_restapi;
my $get_items_path_query = sub {
    return 'selectionset/dbmodules/';
};


my $fieldnames = [
    "module",
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
