package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValues;
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

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValue qw();
#use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryValue qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagJsonValue qw();
#use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::InquiryJsonValue qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path
    
    get_probandlistentrytagvalues
    get_probandlistentrytagvalues

);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($listentry_id, $tag_id) = @_;
    return 'probandlistentry/' . $listentry_id . '/tagvalue/' . $tag_id;
};
my $get_getprobandlistentrytagvalues_path_query = sub {
    my ($listentry_id, $sort, $load_all_js_values) = @_;
    my %params = ();
    $params{load_all_js_values} = booltostring($load_all_js_values); # if defined $load_all_js_values;
    $params{sort} = booltostring($sort);
    return 'probandlistentry/' . $listentry_id . '/tagvalues' . get_query_string(\%params);
};

my $get_setprobandlistentrytagvalues_path_query = sub {
    return 'probandlistentrytagvalue/';
};

#my $get_renderinquiries_path_query = sub {
#    my ($proband_id, $trial_id, $active, $active_signup, $blank) = @_;
#    my %params = ();
#    $params{blank} = booltostring($blank); # if defined $blank;
#    $params{active} = booltostring($active) if defined $active;
#    $params{active_signup} = booltostring($active_signup) if defined $active_signup;
#    return 'proband/' . $proband_id . '/inquiryvalues/' . $trial_id . '/pdf' . get_query_string(\%params);
#};
#my $get_renderinquiriessignup_path_query = sub {
#    my ($department_id,$proband_id, $active_signup) = @_;
#    my %params = ();
#    $params{department_id} = $department_id if defined $department_id;
#    $params{active_signup} = booltostring($active_signup) if defined $active_signup;
#    return 'proband/' . $proband_id . '/inquiryvalues/signuppdf' . get_query_string(\%params);
#};

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

    my ($listentry_id, $tag_id,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_item_path_query($listentry_id, $tag_id),$headers),$load_recursive,$restapi);

}

sub get_probandlistentrytagvalues {

    my ($listentry_id, $sort, $load_all_js_values, $p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_getprobandlistentrytagvalues_path_query($listentry_id, $sort, $load_all_js_values),$p,$sf),$headers),$p),$load_recursive,$restapi);

}

sub set_probandlistentrytagvalues {

    my ($in,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->put(&$get_setprobandlistentrytagvalues_path_query(),$in,$headers),$load_recursive,$restapi);

}



#sub render_inquiries {
#
#    my ($proband_id,$trial_id,$active, $active_signup,$blank,$restapi,$headers) = @_;
#    my $api = _get_api($restapi,$default_restapi);
#    return $api->get_file(&$get_renderinquiries_path_query($proband_id,$trial_id,$active, $active_signup,$blank),$headers);
#
#}
#
#sub render_inquiries_signup {
#
#    my ($department_id,$proband_id, $active_signup,$restapi,$headers) = @_;
#    my $api = _get_api($restapi,$default_restapi);
#    return $api->get_file(&$get_renderinquiriessignup_path_query($department_id,$proband_id, $active_signup),$headers);
#
#}

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
    
    $item->{rows} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagValue::builditems_fromrows($item->{rows},$load_recursive,$restapi);
    $item->{js_rows} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTagJsonValue::builditems_fromrows($item->{js_rows},$load_recursive,$restapi);   
    
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
