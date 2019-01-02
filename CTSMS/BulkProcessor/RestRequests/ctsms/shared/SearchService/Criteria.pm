package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria;
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
    get_list

    process_items
    get_module
);
#@modules

#our @modules = qw(
#    inventory
#    staff
#    course
#    trial
#    proband
#    inputfield
#    massmail
#    user
#);

sub get_module {
    my ($db_module) = @_;
    $db_module =~ s/_db$//i;
    $db_module =~ s/_//i;
    return lc($db_module);
}

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'search/' . $id;
};
my $get_add_path_query = sub {
    return 'search/';
};
my $get_update_path_query = sub {
    return 'search/';
};
my $get_list_path_query = sub {
    my ($module,$sort) = @_;
    my %params = ();
    $params{a} = 'id' if $sort;
    return 'search/' . $module . get_query_string(\%params);
    #my %params = ();
    #$params{department_id} = $department_id if defined $department_id;
    #return 'trial/signup/' . get_query_string(\%params);
    #return 'search/' . $module;
};

my $fieldnames = [
    "category",
    "comment",
    "criterions",
    "deferredDelete",
    "deferredDeleteReason",
    "id",
    "label",
    "loadByDefault",
    "modifiedTimestamp",
    "modifiedUser",
    "module",
    "version",
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

sub get_list {

    my ($module,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_list_path_query($module),$p,$sf),$headers),$p),$load_recursive,$restapi);

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

sub process_items {

    my %params = @_;
    my ($restapi,
        $module,
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
            module
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
        path_query   => &$get_list_path_query($module,1), #strict order!
        #post_data    => $in,
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
