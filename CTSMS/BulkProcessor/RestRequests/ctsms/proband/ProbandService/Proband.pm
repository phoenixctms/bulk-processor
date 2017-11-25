package CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband;
use strict;

## no critic

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi

);

use CTSMS::BulkProcessor::RestProcessor qw(
    copy_row
    get_query_string
    process_collection
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
    get_list
    update_category

    process_search_items
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'proband/' . $id;
};
my $get_list_path_query = sub {
    my ($department_id) = @_; #,$proband_id) = @_;
    my %params = ();
    $params{department_id} = $department_id if defined $department_id;
    #$params{proband_id} = $proband_id if defined $proband_id;
    return 'proband/' . get_query_string(\%params);
};
my $get_search_path_query = sub {
    my ($sort) = @_;
    my %params = ();
    $params{a} = 'id' if $sort;
    return 'search/proband/search' . get_query_string(\%params);
};
my $get_add_path_query = sub {
    return 'proband/';
};
my $get_update_path_query = sub {
    return 'proband/';
};
my $get_update_category_path_query = sub {
    my ($id) = @_;
    return 'proband/' . $id . '/category/';
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

sub update_category {

    my ($id,$in,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->put(&$get_update_category_path_query($id),$in,$headers),$load_recursive,$restapi);

}

sub get_list {

    my ($department_id,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_list_path_query($department_id),$p,$sf),$headers),$p),$load_recursive,$restapi);

}

sub search {

    my ($in,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->post($api->get_collection_page_query_uri(&$get_search_path_query(0),$p,$sf),$in,$headers),$p),$load_recursive,$restapi);

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

sub process_search_items {

    my %params = @_;
    my ($restapi,
        $in,
        $headers,
        $process_code,
        $static_context,
        $blocksize,
        $init_process_context_code,
        $uninit_process_context_code,
        $multithreading,
        $numofthreads,
        $load_recursive) = @params{qw/
            restapi
            in
            headers
            process_code
            static_context
            blocksize
            init_process_context_code
            uninit_process_context_code
            multithreading
            numofthreads
            load_recursive
        /};

    return process_collection(
        get_restapi  => sub { return _get_api($restapi,$default_restapi); },
        path_query   => &$get_search_path_query(1), #strict order!
        post_data    => $in,
        headers      => $headers,
        extract_collection_items_params => undef,
        process_code => sub {
            my ($context,$rowblock,$row_offset) = @_;
            return &$process_code($context,builditems_fromrows($rowblock,$load_recursive),$row_offset);
        },
        static_context => $static_context,
        blocksize => $blocksize,
        init_process_context_code   => $init_process_context_code,
        uninit_process_context_code => $uninit_process_context_code,
        multithreading => $multithreading,
        collectionprocessing_threads =>$numofthreads,
    );

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
