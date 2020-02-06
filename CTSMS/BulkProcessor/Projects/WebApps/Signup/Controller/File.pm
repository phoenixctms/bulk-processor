package CTSMS::BulkProcessor::Projects::WebApps::Signup::Controller::File;

use strict;

## no critic

use Dancer qw();

use HTTP::Status qw();

use CTSMS::BulkProcessor::Projects::WebApps::Signup::Utils qw(
    apply_lwp_file_response
    $restapi
);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File qw();

Dancer::get('/file/:file_id',sub {

    my $params = Dancer::params();

    my $file_response;
    eval {
        $file_response = CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::download(
            $params->{file_id},
            $restapi,
        );
    };
    if ($@ or not $file_response) {
        Dancer::status(HTTP::Status::HTTP_NOT_FOUND);
    } else {
        return apply_lwp_file_response($file_response);
    }

});

1;
