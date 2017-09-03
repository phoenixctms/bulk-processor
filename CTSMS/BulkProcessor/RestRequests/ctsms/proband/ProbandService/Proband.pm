package CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband;
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

#use CTSMS::BulkProcessor::Utils qw(booltostring);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path
    
    add_item
    update_item
    search
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'proband/' . $id;
};
my $get_search_path_query = sub {
    return 'search/proband/search';
};
my $get_add_path_query = sub {
    return 'proband/';
};
my $get_update_path_query = sub {
    return 'proband/';
};

my $fieldnames = [
    "person",
    "blinded",
    "age",
    "autoDeleteDeadline",
    "category",
    "children",
    "childrenCount",
    "citizenship",
    "comment",
    "dateOfBirth",
    "decrypted",
    "deferredDelete",
    "department",
    "firstName",
    "gender",
    "hasImage",
    "id",
    "initials",
    "lastName",
    "modifiedTimestamp",
    "modifiedUser",
    "name",
    "nameWithTitles",
    "parents",
    "parentsCount",
    "postpositionedTitle1",
    "postpositionedTitle2",
    "postpositionedTitle3",
    "prefixedTitle1",
    "prefixedTitle2",
    "prefixedTitle3",
    "privacyConsentStatus",
    "version",
    "yearOfBirth",
    "physician",
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

sub add_item {

    my ($in,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->post(&$get_add_path_query(),$in,$headers),$load_recursive,$restapi);

}

sub update_item {

    my ($in,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->put(&$get_update_path_query(),$in,$headers),$load_recursive,$restapi);

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

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

sub TO_JSON {
    
    my $self = shift;
    return { %{$self} };
    #    value => $self->{zipcode},
    #    label => $self->{zipcode},
    #};

}

1;
