package CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValues;
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

use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValue qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryJsonValue qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    get_inquiryvalues
    set_inquiryvalues
    render_inquiries
    render_inquiries_signup
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($proband_id, $inquiry_id) = @_;
    return 'proband/' . $proband_id . '/inquiryvalue/' . $inquiry_id;
};
my $get_getinquiryvalues_path_query = sub {
    my ($proband_id, $trial_id, $active, $active_signup, $sort, $load_all_js_values) = @_;
    my %params = ();
    $params{active} = booltostring($active) if defined $active;
    $params{active_signup} = booltostring($active_signup) if defined $active_signup;
    $params{sort} = booltostring($sort);
    $params{load_all_js_values} = booltostring($load_all_js_values);
    return 'proband/' . $proband_id . '/inquiryvalues/' . $trial_id . get_query_string(\%params);
};
my $get_setinquiryvalues_path_query = sub {
    my ($force) = @_;
    my %params = ();
    $params{force} = booltostring($force) if defined $force;
    return 'inquiryvalue/' . get_query_string(\%params);
};
my $get_renderinquiries_path_query = sub {
    my ($proband_id, $trial_id, $active, $active_signup, $blank) = @_;
    my %params = ();
    $params{blank} = booltostring($blank);
    $params{active} = booltostring($active) if defined $active;
    $params{active_signup} = booltostring($active_signup) if defined $active_signup;
    return 'proband/' . $proband_id . '/inquiryvalues/' . $trial_id . '/pdf' . get_query_string(\%params);
};
my $get_renderinquiriessignup_path_query = sub {
    my ($department_id,$proband_id, $active_signup) = @_;
    my %params = ();
    $params{department_id} = $department_id if defined $department_id;
    $params{active_signup} = booltostring($active_signup) if defined $active_signup;
    return 'proband/' . $proband_id . '/inquiryvalues/signuppdf' . get_query_string(\%params);
};

my $fieldnames = [
    "rows",
    "js_rows",
];

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub get_item {

    my ($proband_id,$inquiry_id,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_item_path_query($proband_id,$inquiry_id),$headers),$load_recursive,$restapi);

}

sub get_inquiryvalues {

    my ($proband_id,$trial_id,$active,$active_signup, $sort, $load_all_js_values, $p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_getinquiryvalues_path_query($proband_id,$trial_id,$active,$active_signup, $sort, $load_all_js_values),$p,$sf),$headers),$p),$load_recursive,$restapi);

}

sub set_inquiryvalues {

    my ($in,$force,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->put(&$get_setinquiryvalues_path_query($force),$in,$headers),$load_recursive,$restapi);

}

sub render_inquiries {

    my ($proband_id,$trial_id,$active, $active_signup,$blank,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get_file(&$get_renderinquiries_path_query($proband_id,$trial_id,$active, $active_signup,$blank),$headers);

}

sub render_inquiries_signup {

    my ($department_id,$proband_id, $active_signup,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get_file(&$get_renderinquiriessignup_path_query($department_id,$proband_id, $active_signup),$headers);

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
    $item->{rows} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValue::builditems_fromrows($item->{rows},$load_recursive,$restapi);
    $item->{js_rows} = CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryJsonValue::builditems_fromrows($item->{js_rows},$load_recursive,$restapi);
}

#sub get_item_path {
#
#    my ($id) = @_;
#    return &$get_item_path_query($id);
#
#}

1;
