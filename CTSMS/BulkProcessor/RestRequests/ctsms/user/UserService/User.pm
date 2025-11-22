package CTSMS::BulkProcessor::RestRequests::ctsms::user::UserService::User;
use strict;

## no critic

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi

);

use CTSMS::BulkProcessor::RestProcessor qw(
    copy_row
    get_query_string
    override_fields
);

use CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi qw(_get_api);
use CTSMS::BulkProcessor::RestItem qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    search
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'user/' . $id;
};
my $get_search_path_query = sub {
    return 'search/user/search';
};

my $fieldnames = [
   "id",
   "name",
   "version",
   "modifiedTimestamp",
   "locked",
   "lockedUntrusted",
   "locale",
   "timeZone",
   "dateFormat",
   "decimalSeparator",
   "theme",
   "authMethod",
   "showTooltips",
   "decrypt",
   "decryptUntrusted",
   "deferredDelete",
   "deferredDeleteReason",
   "enableInventoryModule",
   "enableStaffModule",
   "enableCourseModule",
   "enableTrialModule",
   "enableInputFieldModule",
   "enableProbandModule",
   "enableMassMailModule",
   "enableUserModule",
   "visibleInventoryTabList",
   "visibleStaffTabList",
   "visibleCourseTabList",
   "visibleTrialTabList",
   "visibleProbandTabList",
   "visibleInputFieldTabList",
   "visibleUserTabList",
   "visibleMassMailTabList",
   "identity",
   "department",
   "parent",
   "children",
   "tabOrientation",
   "dutyRosterTurnCalendarFilters",
   "inventoryBookingCalendarFilters",
   "inheritedPropertyList",
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

sub search {

    my ($in,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->post($api->get_collection_page_query_uri(&$get_search_path_query(),$p,$sf),$in,$headers),$p),$load_recursive,$restapi);

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

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

sub TO_JSON {

    my $self = shift;
    return { %{$self} };

}

1;
