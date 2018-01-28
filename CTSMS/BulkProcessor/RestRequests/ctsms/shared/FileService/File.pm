package CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File;
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

use CTSMS::BulkProcessor::Utils qw(booltostring);


require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    get_item
    get_trialfiles
    download
    upload

    $TRIAL_FILE_MODULE
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($file_id) = @_;
    return 'file/' . $file_id . '/head';
};
my $download_path_query = sub {
    my ($file_id) = @_;
    return 'file/' . $file_id;
};
my $upload_path_query = sub {
    return 'file/';
};
my $get_trialfiles_path_query = sub {
    my ($trial_id) = @_;
    #my %params = ();
    #$params{active} = booltostring($active) if defined $active;
    #$params{active_signup} = booltostring($active_signup) if defined $active_signup;
    #$params{sort} = booltostring($sort); # if defined $sort;
    #$params{load_all_js_values} = booltostring($load_all_js_values); # if defined $load_all_js_values;
    return 'trial/' . $trial_id . '/files'; # . get_query_string(\%params);
};

my $fieldnames = [
    "active",
    "publicFile",
    "comment",
    "contentType",
    "course",
    "decrypted",
    "externalFile",
    "fileName",
    "id",
    "inventory",
    "logicalPath",
    "md5",
    "modifiedTimestamp",
    "modifiedUser",
    "module",
    "proband",
    "size",
    "staff",
    "title",
    "trial",
    "version",
];

our $TRIAL_FILE_MODULE = 'TRIAL_DOCUMENT';

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub get_item {

    my ($file_id,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_item_path_query($file_id),$headers),$load_recursive,$restapi);

}

sub get_trialfiles {

    my ($trial_id, $p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_trialfiles_path_query($trial_id),$p,$sf),$headers),$p),$load_recursive,$restapi);

}

sub download {

    my ($file_id,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get_file(&$download_path_query($file_id),$headers);

}

sub upload {

    my ($in,$file,$filename,$content_type,$content_encoding,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->post_file(&$upload_path_query(),$in,$file,$filename,$content_type,$content_encoding,$headers),$load_recursive,$restapi);

}

sub builditems_fromrows {

    my ($rows,$load_recursive,$restapi) = @_;

    my $item;

    if (defined $rows and ref $rows eq 'ARRAY') {
        my @items = ();
        foreach my $row (@$rows) {
            $item = __PACKAGE__->new($row);

            # transformations go here ...
            transformitem($item,$load_recursive,$restapi);

            push @items,$item;
        }
        return \@items;
    } elsif (defined $rows and ref $rows eq 'HASH') {
        $item = __PACKAGE__->new($rows);
        transformitem($item,$load_recursive,$restapi);
        return $item;
    }
    return undef;

}

sub transformitem {
    my ($item,$load_recursive,$restapi) = @_;
    #$item->{rows} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValue::builditems_fromrows($item->{rows},$load_recursive,$restapi);
    #$item->{js_rows} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryJsonValue::builditems_fromrows($item->{js_rows},$load_recursive,$restapi);
}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

#sub TO_JSON {
#
#    my $self = shift;
#    return { %{$self} };
#    #    value => $self->{zipcode},
#    #    label => $self->{zipcode},
#    #};
#
#}

1;
