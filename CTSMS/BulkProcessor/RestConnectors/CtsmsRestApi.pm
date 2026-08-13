package CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi;
use strict;

## no critic

use threads qw();
use threads::shared 1.51 qw(shared_clone);

use Encode qw();
use URI::Escape qw();

use HTTP::Status qw(:constants :is status_message);
use HTTP::Request::Common qw();

use JSON -support_by_pp, -no_export;

use CTSMS::BulkProcessor::Globals qw(
    $LongReadLen_limit
    $ctsmsrestapi_jwt_validity_secs
);
use CTSMS::BulkProcessor::Logging qw(
    getlogger
    restdebug
    restinfo
);
use CTSMS::BulkProcessor::LogError qw(
    resterror
    restwarn
    restrequesterror
    restresponseerror
    $cli);

use CTSMS::BulkProcessor::RestConnector qw(
    _add_headers
    convert_bools
    _decode_jwt_payload
    $default_jwt_refresh_skew_secs
);

use CTSMS::BulkProcessor::Array qw(contains);

use CTSMS::BulkProcessor::Utils qw(booltostring);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestConnector);
our @EXPORT_OK = qw(
    _get_api
);

my $defaulturi = 'http://127.0.0.1:8080/ctsms-web/rest/';
my $defaultusername = 'user_9qxs_1_1';
my $defaultpassword = 'user_9qxs_1_1';
my $defaultrealm = 'api';
# Large ETL job output uploads (e.g. ~400MB+ SQLite) need more than a few minutes.
my $timeout = 30*60;

my $default_collection_page_size = 10;
my $first_collection_page_num = 1;

my $contenttype = 'application/json';

my $request_charset = 'utf-8';
my $response_charset = 'utf-8';

sub _get_api {
    my @get_rest_apis = @_;
    foreach my $get_api (@get_rest_apis) {
        if (defined $get_api) {
            if ('CODE' eq ref $get_api) {
                return &$get_api();
            } else {
                return $get_api;
            }
        }
    }
    return undef;
}

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::RestConnector->new(@_);

    bless($self,$class);

    $self->setup();

    restdebug($self,__PACKAGE__ . ' connector created',getlogger(__PACKAGE__));

    return $self;

}

sub setup {

    my $self = shift;
    my ($baseuri,$username,$password,$realm) = @_;
    $self->baseuri($baseuri // $defaulturi);
    $self->{username} = $username // $defaultusername;
    $self->{password} = $password // $defaultpassword;
    $self->{realm} = $realm // $defaultrealm;

}

sub jwt {

    my $self = shift;
    if (@_) {
        my $jwt = shift;
        undef $self->{ua};
        $self->{jwt} = (defined $jwt && length($jwt) > 0) ? $jwt : undef;
        $self->_apply_jwt_claims($self->{jwt});
    }
    return $self->{jwt};

}

sub jwt_refresh_skew_secs {

    my $self = shift;
    if (@_) {
        my $skew = shift;
        $self->{jwt_refresh_skew_secs} = (defined $skew && $skew =~ /^\d+$/) ? int($skew) : $default_jwt_refresh_skew_secs;
    }
    return $self->{jwt_refresh_skew_secs} // $default_jwt_refresh_skew_secs;

}

sub _apply_jwt_claims {

    my $self = shift;
    my ($jwt) = @_;
    $self->{jwt_expires} = undef;
    $self->{jwt_validity_secs} = undef;
    return unless defined $jwt && length($jwt) > 0;
    my $claims = _decode_jwt_payload($jwt);
    return unless defined $claims && 'HASH' eq ref $claims && defined $claims->{exp};
    $self->{jwt_expires} = int($claims->{exp});
    if (defined $claims->{iat}) {
        $self->{jwt_validity_secs} = int($claims->{exp}) - int($claims->{iat});
    } else {
        # Phoenix sets exp XOR iat; remaining lifetime is still a usable duration.
        my $remaining = int($claims->{exp}) - time();
        $self->{jwt_validity_secs} = $remaining if $remaining > 0;
    }

}

sub _snapshot_request_state {
    my $self = shift;
    return {
        req => $self->{req},
        res => $self->{res},
        requestdata => $self->{requestdata},
        responsedata => $self->{responsedata},
    };
}

sub _restore_request_state {
    my ($self,$state) = @_;
    return unless $state;
    $self->{req} = $state->{req};
    $self->{res} = $state->{res};
    $self->{requestdata} = $state->{requestdata};
    $self->{responsedata} = $state->{responsedata};
}

sub _renew_jwt_if_required {

    my $self = shift;
    return 0 unless defined $self->{jwt} && length($self->{jwt}) > 0;
    return 0 unless defined $self->{jwt_expires};
    if (defined $self->{jwt_refresh_cooldown_until} && time() < $self->{jwt_refresh_cooldown_until}) {
        return 0;
    }
    my $skew = $self->jwt_refresh_skew_secs();
    return 0 if time() < ($self->{jwt_expires} - $skew);
    return $self->_renew_jwt();

}

sub _force_renew_jwt {

    my $self = shift;
    return 0 unless defined $self->{jwt} && length($self->{jwt}) > 0;
    undef $self->{jwt_refresh_cooldown_until};
    return $self->_renew_jwt(@_);

}

# Accept only a positive integer lifetime; otherwise use the configured/default 24h.
sub _normalize_explicit_jwt_validity_secs {

    my ($validity_secs) = @_;
    if (defined $validity_secs && !ref($validity_secs) && $validity_secs =~ /^\d+$/ && int($validity_secs) > 0) {
        return int($validity_secs);
    }
    my $fallback = $ctsmsrestapi_jwt_validity_secs;
    if (defined $fallback && !ref($fallback) && $fallback =~ /^\d+$/ && int($fallback) > 0) {
        return int($fallback);
    }
    return 24 * 60 * 60;

}

# Re-issue the current Bearer JWT with an explicit lifetime (used by ETL --auth startup).
# Croaks on failure so jobs do not continue with a short-lived token.
sub extend_jwt_validity {

    my $self = shift;
    my ($validity_secs) = @_;
    unless (defined $self->{jwt} && length($self->{jwt}) > 0) {
        resterror($self, 'rest api jwt extend requires a jwt', getlogger(__PACKAGE__));
    }
    $validity_secs = _normalize_explicit_jwt_validity_secs($validity_secs);
    my $renewed = $self->_force_renew_jwt($validity_secs);
    unless ($renewed) {
        resterror($self, 'rest api jwt extend failed', getlogger(__PACKAGE__));
    }
    $self->{jwt_validity_secs} = $validity_secs;
    restinfo($self, 'rest api jwt validity extended to ' . $validity_secs . 's', getlogger(__PACKAGE__));
    return 1;

}

sub _renew_jwt {

    my $self = shift;
    my $validity_secs;
    if (@_) {
        # Explicit lifetime from extend_jwt_validity / direct callers — never pass through invalid values.
        $validity_secs = _normalize_explicit_jwt_validity_secs($_[0]);
    } else {
        $validity_secs = $self->{jwt_validity_secs};
    }
    my $skew = $self->jwt_refresh_skew_secs();
    my $renewed = 0;
    $self->{_refreshing_jwt} = 1;
    eval {
        # Runtime require avoids a circular use with Login.pm (which uses CtsmsRestApi).
        require CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::Login;
        my $new_jwt = CTSMS::BulkProcessor::RestRequests::ctsms::shared::ToolsService::Login::issue_jwt(
            $validity_secs,
            $self,
        );
        if (defined $new_jwt && !ref $new_jwt && length($new_jwt) > 0) {
            restinfo($self, 'rest api jwt refreshed', getlogger(__PACKAGE__));
            undef $self->{jwt_refresh_cooldown_until};
            $self->jwt($new_jwt);
            $renewed = 1;
        } else {
            $self->{jwt_refresh_cooldown_until} = time() + $skew;
            restwarn($self, 'rest api jwt refresh returned no token', getlogger(__PACKAGE__));
        }
    };
    if ($@) {
        $self->{jwt_refresh_cooldown_until} = time() + $skew;
        restwarn($self, 'rest api jwt refresh failed: ' . $@, getlogger(__PACKAGE__));
    }
    $self->{_refreshing_jwt} = 0;
    return $renewed;

}

sub _ua_request {

    my $self = shift;
    my ($req) = @_;

    # Nested issue_jwt uses the same connector and would otherwise clobber the
    # in-flight request's req/res/responsedata (visible as undef->{rows} after refresh).
    unless ($self->{_refreshing_jwt}) {
        my $state = $self->_snapshot_request_state();
        $self->_renew_jwt_if_required();
        $self->_restore_request_state($state);
    }

    my $res = $self->SUPER::_ua_request($req);

    # Reactive single retry: expired/rejected bearer → refresh once, repeat request once.
    if ($res
        and $res->code() == HTTP_UNAUTHORIZED
        and not $self->{_refreshing_jwt}
        and not $self->{_jwt_auth_retry}
        and defined $self->{jwt}
        and length($self->{jwt})) {
        $self->{_jwt_auth_retry} = 1;
        my $state = $self->_snapshot_request_state();
        my $renewed = $self->_force_renew_jwt();
        $self->_restore_request_state($state);
        if ($renewed) {
            restinfo($self, 'rest api retrying request after jwt refresh', getlogger(__PACKAGE__));
            $res = $self->SUPER::_ua_request($req);
        }
        $self->{_jwt_auth_retry} = 0;
    }

    return $res;

}

sub connectidentifier {

    my $self = shift;
    if ($self->{uri}) {
        if ($self->{username}) {
            return $self->{username} . '@' . $self->{uri};
        } elsif ($self->{jwt}) {
            return 'jwt@' . $self->{uri};
        }
        return $self->{uri};
    } else {
        return undef;
    }

}

sub _setup_ua {

    my $self = shift;
    my ($ua,$netloc) = @_;
    $ua->ssl_opts(
		verify_hostname => 0,
		SSL_verify_mode => 0,
	);
    $ua->timeout($timeout) if $timeout;
    if ($self->{jwt}) {
        $ua->default_header('Authorization' => 'Bearer ' . $self->{jwt});
    } elsif ($self->{username}) {
        $ua->credentials($netloc, $self->{realm}, $self->{username}, $self->{password});
    }
    restdebug($self,"ua configured",getlogger(__PACKAGE__));

}

sub _encode_request_content {
    my $self = shift;
    my ($data) = @_;
    return Encode::encode($request_charset,JSON::to_json($data,{ allow_nonref => 1, allow_blessed => 1, convert_blessed => 1, pretty => 0, }));


}

sub _decode_response_content {
    my $self = shift;
    my ($data) = @_;
    my $decoded =
        ($data ? JSON::from_json(Encode::decode($response_charset,$data),{ allow_nonref => 1, }) : undef);

    convert_bools($decoded);
    return $decoded // $data;
}

sub _add_post_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    _add_headers($req,{
       'Content-Type' => $contenttype,
    });
    # allow providing custom headers to post(),
    # e.g { 'X-Fake-Clienttime' => ... }
    $self->SUPER::_add_post_headers($req,$headers);
}

sub _add_get_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    $self->SUPER::_add_get_headers($req,$headers);
}

sub _add_head_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    $self->SUPER::_add_head_headers($req,$headers);
}

sub _add_put_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    _add_headers($req,{
       'Content-Type' => $contenttype,
    });
	$self->SUPER::_add_put_headers($req,$headers);
}

sub _add_delete_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    $self->SUPER::_add_delete_headers($req,$headers);
}

sub _get_page_num_query_param {
    my $self = shift;
    my ($page_num) = @_;
    if (defined $page_num and length($page_num) > 0) {
        return 'p=' . $page_num;
    }
    return undef;
}

sub _get_page_size_query_param {
    my $self = shift;
    my ($page_size) = @_;
    if (defined $page_size and length($page_size) > 0) {
        return 's=' . $page_size;
    }
    return undef;
}

sub _get_total_count_expected_query_param {
    my $self = shift;
    my ($total_count_expected) = @_;
    return 'c=' . booltostring($total_count_expected);
}

sub _get_sf_query_param {
    my $self = shift;
    my ($sf) = @_;
    if ('HASH' eq ref $sf) {
        my %sorting_filtering = %$sf;
        my @params = ();
        if (my $sort_by = delete $sorting_filtering{sort_by}) {
            my $sort_dir = (delete $sorting_filtering{sort_dir}) // '';
            if ('desc' eq $sort_dir) {
                push(@params,'d=' . $sort_by);
            } else {
                push(@params,'a=' . $sort_by);
            }
        }
        #filtertimezone is applied through ?tz= parameter
        foreach my $param (keys %sorting_filtering) {
            push(@params, URI::Escape::uri_escape($param) . '=' . URI::Escape::uri_escape_utf8($sorting_filtering{$param}));
        }
        return join('&',@params);
    }
    return undef;
}

sub extract_collection_items {
    my $self = shift;
    my $data = shift;
    my $page_size;
    my $page_num;
    my $p;
    my $sf;
    my $params;
    if (ref $_[0]) {
        $page_size = $p->{page_size};
        $page_num = $p->{page_num};
        ($p,$sf,$params) = @_;
    } else {
        ($page_size,$page_num,$params) = @_;
    }

    my $result = undef;
    if (defined $data and 'HASH' eq ref $data) {
        if (defined $p and defined $data->{psf} and 'HASH' eq ref $data->{psf}
                and defined $data->{psf}->{totalCount}
                and ($p->{total_count_expected} // 1)) {
            $p->{total_count} = $data->{psf}->{totalCount};
        }
        if (defined $data->{rows} and 'ARRAY' eq ref $data->{rows}) {
            $result = $data->{rows};
        }
        if (defined $data->{js_rows} and 'ARRAY' eq ref $data->{js_rows}) {
            $result = { rows => $result // [], js_rows => $data->{js_rows} // [], };
        }
    }
    $result //= [];
    return shared_clone($result);
}

sub get_defaultcollectionpagesize {
    my $self = shift;
    return $default_collection_page_size;
}

sub get_firstcollectionpagenum {
    my $self = shift;
    return $first_collection_page_num;
}

sub _request_error {
    my $self = shift;
    my $msg = undef;
    if (defined $self->responsedata()
        and 'HASH' eq ref $self->responsedata()) {
        $msg = $self->responsedata()->{'message'};
    }
    if ($cli) {
        $msg = $self->response->code . ' ' . $self->response->message . (defined $msg && length($msg) > 0 ? ': ' . $msg : '');
    } else {
        $msg = (defined $msg && length($msg) > 0 ? $msg : $self->response->code) . ' ' . $self->response->message;
    }

    #if ($self->{_silent}) {
        restdebug($self,$msg,getlogger(__PACKAGE__));
        die($msg);
    #} else {
    #    resterror($self,$msg,getlogger(__PACKAGE__));
    #}

}

sub _extract_ids_from_response_location {

    my $self = shift;
    my $location = $self->response()->header('Location');
    my @ids = ();
    foreach my $segment (split('/',$location)) {
        push(@ids,$segment) if $segment =~ /^\d+$/;
    }
    return @ids;

}

sub get {
    my $self = shift;
    if (not contains($self->_get(@_)->code(), [ HTTP_OK, HTTP_NO_CONTENT ])) {
        $self->_request_error();
        return undef;
    } else {
        return $self->responsedata();
    }
}

sub get_file {
    my $self = shift;
    if ($self->_get_raw(@_)->code() != HTTP_OK) {
        $self->_request_error();
        return undef;
    } else {
        my $res = $self->{res};
        $self->{res} = undef;
        return $res;
    }
}

sub head {
    my $self = shift;
    if (not contains($self->_head(@_)->code(), [ HTTP_OK, HTTP_NO_CONTENT ])) {
        $self->_request_error();
        return undef;
    } else {
        return $self->responsedata();
    }
}

sub post {
    my $self = shift;
    if ($self->_post(@_)->code() != HTTP_OK) {
        $self->_request_error();
        return ();
    } else {
        return $self->responsedata();

    }
}

sub post_file {
    my $self = shift;
    my ($path_query,$data,$file,$filename,$content_type,$content_encoding,$headers) = @_;

    my $json;
	eval {
        $json = $self->_encode_post_content($data);
    };
    if ($@) {
        restrequesterror($self,'error encoding POST request content: ' . $@,undef,$data,getlogger(__PACKAGE__));
    }

    my %file_part_headers = ();
    $file_part_headers{'Content-Type'} = $content_type if defined $content_type;
    $file_part_headers{'Content-Encoding'} = $content_encoding if defined $content_encoding;
    my $req = HTTP::Request::Common::POST($self->_get_request_uri($path_query),
        Content_Type    => 'form-data',
        Content         => [
            json    => $json,
            data    => ('SCALAR' eq ref $file ? [ undef, $filename, 'Content' => $$file, %file_part_headers, ] :
                       [ $file, $filename, %file_part_headers, ] )
        ],
    );
    _add_headers($req,$headers);

    if ($self->_post_raw($req,undef,undef)->code() != HTTP_OK) {
        $self->_request_error();
        return undef;
    } else {
        return $self->responsedata();
    }
}

sub put {
    my $self = shift;
    if ($self->_put(@_)->code() != HTTP_OK) {
        $self->_request_error();
        return undef;
    } else {
        return $self->responsedata();
    }
}

sub put_file {
    my $self = shift;
    my ($path_query,$data,$file,$filename,$content_type,$content_encoding,$headers) = @_;

    my $json;
	eval {
        $json = $self->_encode_put_content($data);
    };
    if ($@) {
        restrequesterror($self,'error encoding PUT request content: ' . $@,undef,$data,getlogger(__PACKAGE__));
    }

    my %file_part_headers = ();
    $file_part_headers{'Content-Type'} = $content_type if defined $content_type;
    $file_part_headers{'Content-Encoding'} = $content_encoding if defined $content_encoding;
    my $req = HTTP::Request::Common::PUT($self->_get_request_uri($path_query),
        Content_Type    => 'form-data',
        Content         => [
            json    => $json,
            data    => ('SCALAR' eq ref $file ? [ undef, $filename, 'Content' => $$file, %file_part_headers, ] :
                       [ $file, $filename, %file_part_headers, ] )
        ],
    );
    _add_headers($req,$headers);

    if ($self->_put_raw($req,undef,undef)->code() != HTTP_OK) {
        $self->_request_error();
        return undef;
    } else {
        return $self->responsedata();
    }
}

sub delete {
    my $self = shift;
    if ($self->_delete(@_)->code() != HTTP_OK) {
        $self->_request_error();
        return 0;
    } else {

        return $self->responsedata();
    }
}

sub get_last_error {
    my $self = shift;
    if (defined $self->responsedata()
        and 'HASH' eq ref $self->responsedata()) {
        return $self->responsedata()->{'errorCode'};
    }
    return undef;
}

1;
