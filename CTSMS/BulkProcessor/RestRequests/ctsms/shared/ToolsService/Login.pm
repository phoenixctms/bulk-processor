package CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::Login;
use strict;

## no critic

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi
);

use CTSMS::BulkProcessor::RestProcessor qw(
    get_query_string
);

use CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi qw(_get_api);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    issue_rest_api_jwt
);

my $default_restapi = \&get_ctsms_restapi;
my $get_login_path_query = sub {
    my ($validity_secs) = @_;
    my %params = ();
    $params{validity_secs} = int($validity_secs) if defined $validity_secs && $validity_secs > 0;
    return 'tools/login' . get_query_string(\%params);
};

sub issue_rest_api_jwt {

    my ($validity_secs, $restapi, $headers) = @_;
    my $api = _get_api($restapi, $default_restapi);
    return $api->post(&$get_login_path_query($validity_secs), {}, $headers);

}

1;
