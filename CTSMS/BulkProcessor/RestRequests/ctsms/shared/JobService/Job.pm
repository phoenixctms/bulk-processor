package CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job;
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
    get_item
    get_item_path

    get_item
    download_job_file
    update_item

    $PROCESSING_JOB_STATUS
    $FAILED_JOB_STATUS
    $OK_JOB_STATUS
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($job_id) = @_;
    return 'job/' . $job_id;
};
my $download_job_file_path_query = sub {
    my ($job_id) = @_;
    return 'job/' . $job_id . '/file';
};
my $get_update_path_query = sub {
    return 'job/';
};

my $fieldnames = [
"criteria",
"emailRecipients",
"encryptedFile",
"hasFile",
"id",
"inputField",
"jobOutput",
"modifiedTimestamp",
"modifiedUser",
"proband",
"status",
"trial",
"type",
"version",
];

our $PROCESSING_JOB_STATUS = 'PROCESSING';
our $FAILED_JOB_STATUS = 'FAILED';
our $OK_JOB_STATUS = 'OK';

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

sub download_job_file {

    my ($file_id,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get_file(&$download_job_file_path_query($file_id),$headers);

}

sub update_item {

    my ($in,$file,$filename,$content_type,$content_encoding,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    if (defined $file) {
        return builditems_fromrows($api->put_file(&$get_update_path_query(),$in,$file,$filename,$content_type,$content_encoding,$headers),$load_recursive,$restapi);
    } else {
        return builditems_fromrows($api->put(&$get_update_path_query(),$in,$headers),$load_recursive,$restapi);
    }

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
}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}











1;
