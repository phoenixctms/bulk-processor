package CTSMS::BulkProcessor::RestConnectors::CTSMSRestApi;
use strict;

## no critic

use threads qw();
use threads::shared qw(shared_clone);

use HTTP::Status qw(:constants :is status_message);

use JSON qw();

use CTSMS::BulkProcessor::Globals qw($LongReadLen_limit);
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

use CTSMS::BulkProcessor::RestConnector qw(_add_headers);

use CTSMS::BulkProcessor::FakeTime qw(get_fake_now_string);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestConnector);
our @EXPORT_OK = qw(
    $ITEM_REL_PARAM
);

my $defaulturi = 'https://127.0.0.1:443';
my $defaultusername = 'administrator';
my $defaultpassword = 'administrator';
my $defaultrealm = 'api_admin_http';
my $timeout = 60;

my $default_collection_page_size = 10;
my $first_page_num = 1;

my $contenttype = 'application/json';
my $patchcontenttype = 'application/json-patch+json';

my $defaultfaketime = 0;
my $faketime_header = 'X-Fake-Clienttime';

our $ITEM_REL_PARAM = 'item_rel';
#my $logger = getlogger(__PACKAGE__);

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
    my ($baseuri,$username,$password,$realm,$faketime) = @_;
    $self->baseuri($baseuri // $defaulturi);
    $self->{username} = $username // $defaultusername;
    $self->{password} = $password // $defaultpassword;
    $self->{realm} = $realm // $defaultrealm;
    $self->{faketime} = $faketime // $defaultfaketime;

}

sub connectidentifier {

    my $self = shift;
    if ($self->{uri}) {
        return ($self->{username} ? $self->{username} . '@' : '') . $self->{uri};
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
    $ua->ssl_opts($timeout);
    if ($self->{username}) {
        $ua->credentials($netloc, $self->{realm}, $self->{username}, $self->{password});
    }
    restdebug($self,"ua configured",getlogger(__PACKAGE__));

}

sub _encode_request_content {
    my $self = shift;
    my ($data) = @_;
    return JSON::to_json($data);
}

sub _decode_response_content {
    my $self = shift;
    my ($data) = @_;
    return ($data ? JSON::from_json($data) : undef);
}

sub _add_post_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    _add_headers($req,{
       'Content-Type' => $contenttype,
       ($self->{faketime} ? ($faketime_header => get_fake_now_string()) : ()),
    });
    # allow providing custom headers to post(),
    # e.g { 'X-Fake-Clienttime' => ... }
    $self->SUPER::_add_post_headers($req,$headers);
}

sub _add_get_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    _add_headers($req,{
       ($self->{faketime} ? ($faketime_header => get_fake_now_string()) : ()),
    });
    $self->SUPER::_add_get_headers($req,$headers);
}

sub _add_patch_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    _add_headers($req,{
       'Prefer' => 'return=representation',
       'Content-Type' => $patchcontenttype,
       ($self->{faketime} ? ($faketime_header => get_fake_now_string()) : ()),
    });
	$self->SUPER::_add_patch_headers($req,$headers);
}

sub _encode_patch_content {
    my $self = shift;
    my ($data) = @_;
    return JSON::to_json(
		[ map { local $_ = $_; { op => 'replace', path => '/'.$_ , value => $data->{$_} }; } keys %$data ]
	);
}

sub _add_put_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    _add_headers($req,{
       'Prefer' => 'return=representation',
       'Content-Type' => $contenttype,
       ($self->{faketime} ? ($faketime_header => get_fake_now_string()) : ()),
    });
	$self->SUPER::_add_put_headers($req,$headers);
}

sub _add_delete_headers {
    my $self = shift;
    my ($req,$headers) = @_;
    _add_headers($req,{
       ($self->{faketime} ? ($faketime_header => get_fake_now_string()) : ()),
    });
    $self->SUPER::_add_delete_headers($req,$headers);
}

sub _get_page_num_query_param {
    my $self = shift;
    my ($page_num) = @_;
    if (defined $page_num) {
        $page_num += $first_page_num;
    } else {
        $page_num = $first_page_num;
    }
    return 'page=' . $page_num;
}

sub _get_page_size_query_param {
    my $self = shift;
    my ($page_size) = @_;
    $page_size //= $default_collection_page_size;
    return 'size=' . $page_size;
}

sub _get_total_count_expected_query_param {
    my $self = shift;
    my ($total_count_expected) = @_;
    return undef;
}

#sub _get_sf_query_param {
#    my $self = shift;
#    my ($sf) = @_;
#    notimplementederror((ref $self) . ': ' . (caller(0))[3] . ' not implemented',getlogger(__PACKAGE__));
#}

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
    #my ($data,$page_size,$page_num,$params) = @_;
    my $result = undef;
    if (defined $data and 'HASH' eq ref $data) {
        if (defined $p and exists $data->{total_count}) {
            $p->{total_count} = $data->{total_count};
        }
        if (defined $data->{'_embedded'} and 'HASH' eq ref $data->{'_embedded'}) {
            $result = $data->{'_embedded'}->{$params->{$ITEM_REL_PARAM}};
            if ('ARRAY' eq ref $result) {
    
            } elsif ('HASH' eq ref $result) {
                $result = [ $result ];
            } else {
                undef $result;
            }
        }
    }
    $result //= [];
    return shared_clone($result);
}

sub get_defaultcollectionpagesize {
    my $self = shift;
    return $default_collection_page_size;
}

sub _request_error {
    my $self = shift;
    my $msg = undef;
    if (defined $self->responsedata()
        and 'HASH' eq ref $self->responsedata()) {
        $msg = $self->responsedata()->{'message'};
    }
    if ($cli) {
        resterror($self,$self->response->code . ' ' . $self->response->message .
              (defined $msg && length($msg) > 0 ? ': ' . $msg : ''),getlogger(__PACKAGE__));
    } else {
        resterror($self,defined $msg && length($msg) > 0 ? $msg : $self->response->code . ' ' . $self->response->message,getlogger(__PACKAGE__));        
    }
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
    if ($self->_get(@_)->code() != HTTP_OK) {
        $self->_request_error();
        return undef;
    } else {
        return $self->responsedata();
    }
}

sub post {
    my $self = shift;
    if ($self->_post(@_)->code() != HTTP_CREATED) {
        $self->_request_error();
        return ();
    } else {
        return $self->_extract_ids_from_response_location();
    }
}

sub post_get {
    my $self = shift;
    my ($path_query,$post_headers,$get_headers) = @_;
    if ($self->_post($path_query,$post_headers)->code() != HTTP_CREATED) {
        $self->_request_error();
        return undef;
    } else {
        return $self->get($self->response()->header('Location'),$get_headers);
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

sub patch {
    my $self = shift;
    if ($self->_patch(@_)->code() != HTTP_OK) {
        $self->_request_error();
        return undef;
    } else {
        return $self->responsedata();
    }
}

sub delete {
    my $self = shift;
    if ($self->_delete(@_)->code() != HTTP_NO_CONTENT) {
        $self->_request_error();
        return 0;
    } else {
        return 1;
    }
}

sub faketime {
    my $self = shift;
    if (@_) {
        $self->{faketime} = shift;
        restdebug($self,"fake time " . ($self->{faketime} ? 'enabled' : 'disabled'),getlogger(__PACKAGE__));
    }
    return $self->{faketime};
}

1;
