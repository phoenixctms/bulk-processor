package CTSMS::BulkProcessor::RestRequests::ctsms::massmail::MassMailService::MassMailRecipient;
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

    add_item
    reset_item
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'massmailrecipient/' . $id;
};
my $get_add_path_query = sub {
    return 'massmailrecipient/';
};
my $get_reset_path_query = sub {
    my ($id,$sent,$version) = @_;
    my %params = ();
    $params{version} = $version;
    $params{sent} = booltostring($sent) if defined $sent;
    return 'massmailrecipient/' . $id . '/reset' . get_query_string(\%params);
};

my $fieldnames = [
    "id",
    "hasMimeMessage",
    "mimeMessageSize",
    "mimeMessageTimestamp",
    "beacon",
    "sent",
    "cancelled",
    "timesProcessed",
    "processedTimestamp",
    "errorMessage",
    "read",
    "readTimestamp",
    "unsubscribed",
    "unsubscribedTimestamp",
    "confirmed",
    "confirmedTimestamp",        
    "modifiedTimestamp",
    "pending",
    "version",
    "massMail",
    "proband",
    "modifiedUser",
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

sub reset_item {

    my ($id,$sent,$version,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->put(&$get_reset_path_query($id,$sent,$version),undef,$headers),$load_recursive,$restapi);

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

1;
