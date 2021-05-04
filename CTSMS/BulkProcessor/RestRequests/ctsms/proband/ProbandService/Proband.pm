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

use CTSMS::BulkProcessor::Utils qw(booltostring);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    add_item
    update_item
    delete_item
    search
    get_list
    update_category

    process_search_items
    get_inquiry_proband_list
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'proband/' . $id;
};
my $get_list_path_query = sub {
    my ($department_id) = @_;
    my %params = ();
    $params{department_id} = $department_id if defined $department_id;

    return 'proband/' . get_query_string(\%params);
};
my $get_search_path_query = sub {
    my ($sort) = @_;
    my %params = ();
    $params{a} = 'id' if $sort;
    return 'search/proband/search' . get_query_string(\%params);
};
my $get_inquiryproband_path_query = sub {
    my ($trial_id, $active, $active_signup) = @_;
    my %params = ();
    $params{active} = booltostring($active) if defined $active;
    $params{active_signup} = booltostring($active_signup) if defined $active_signup;
    return 'trial/' . $trial_id . '/list/inquiryproband/' . get_query_string(\%params);
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
my $get_delete_path_query = sub {
    my ($id,$force,$reason) = @_;
    my %params = ();
    $params{force} = booltostring($force) if defined $force;
    $params{reason} = $reason if defined $reason;
    return 'proband/' . $id . get_query_string(\%params);
};

my $fieldnames = [
    "person",
    "blinded",
    "alias",
    "age",
    "autoDeleteDeadline",
    "category",
    "children",
    "childrenCount",
    "citizenship",
    "comment",
    "dateOfBirth",
    "decrypted",
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
    "beacon",
    "deferredDelete",
    "deferredDeleteReason",
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

sub delete_item {

    my ($id,$force,$reason,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->delete(&$get_delete_path_query($id,$force,$reason),$headers),$load_recursive,$restapi);

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

sub get_inquiry_proband_list {

    my ($trial_id,$active,$active_signup,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_inquiryproband_path_query($trial_id,$active,$active_signup),$p,$sf),$headers),$p),$load_recursive,$restapi);

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

sub alias {
    my $self = shift;
    if (length($self->{alias})) {
        return $self->{alias};
    } else {
        return $self->{id};
    }
}

sub locked {
    my $self = shift;
    if ($self->{category}->{locked}) {
        return 1;
    }
    return 0;
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




}

1;
