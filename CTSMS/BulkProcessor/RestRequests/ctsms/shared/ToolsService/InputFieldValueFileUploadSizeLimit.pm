package CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::InputFieldValueFileUploadSizeLimit;
use strict;

## no critic

use HTTP::Status qw(HTTP_NO_CONTENT);

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi
);

use CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi qw(_get_api);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    get_input_field_value_file_upload_size_limit
);

my $default_restapi = \&get_ctsms_restapi;
my $get_limit_path_query = sub {
    return 'tools/inputfieldvaluefileuploadsizelimit';
};

sub get_input_field_value_file_upload_size_limit {

    # the max. size (bytes) of FILE input field values, undef if there is no limit (204 no content).
    # dies if it cannot be retrieved.
    my ($restapi, $headers) = @_;
    my $api = _get_api($restapi, $default_restapi);
    my $limit = $api->get(&$get_limit_path_query(), $headers);
    return undef if $api->response->code == HTTP_NO_CONTENT;
    die("invalid input field value file upload size limit\n") unless (defined $limit and $limit =~ /^\d+$/);
    return int($limit);

}

1;
