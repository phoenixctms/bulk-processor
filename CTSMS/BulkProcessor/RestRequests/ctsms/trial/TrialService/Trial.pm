package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial;
use strict;

## no critic

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi

);

use CTSMS::BulkProcessor::RestProcessor qw(
    copy_row
    get_query_string
    override_fields
);

use CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi qw(_get_api);
use CTSMS::BulkProcessor::RestItem qw();



use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    get_ecrffieldmaxselectionsetvaluecount
    get_inquirymaxselectionsetvaluecount
    get_probandlistentrymaxposition

    get_signup_list

    search
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'trial/' . $id;
};
my $get_signuplist_path_query = sub {
    my ($department_id) = @_;
    my %params = ();
    $params{department_id} = $department_id if defined $department_id;

    return 'trial/signup' . get_query_string(\%params);
};

my $get_search_path_query = sub {
    return 'search/trial/search';
};
my $get_ecrffieldmaxselectionsetvaluecount_path_query = sub {
    my ($id) = @_;
    return 'trial/' . $id . '/ecrffieldmaxselectionsetvaluecount';
};
my $get_inquirymaxselectionsetvaluecount_path_query = sub {
    my ($id) = @_;
    return 'trial/' . $id . '/inquirymaxselectionsetvaluecount';
};
my $get_probandlistentrymaxposition_path_query = sub {
    my ($id) = @_;
    return 'trial/' . $id . '/probandlistentrymaxposition';
};

my $fieldnames = [
    "blockingPeriod",
    "blockingPeriodDays",
    "department",
    "description",
    "dutySelfAllocationLocked",
    "dutySelfAllocationLockedFrom",
    "dutySelfAllocationLockedUntil",
    "exclusiveProbands",
    "id",
    "modifiedTimestamp",
    "modifiedUser",
    "name",
    "signupDescription",
    "signupInquiries",
    "signupProbandList",
    "signupRanomize",
    "sponsoring",
    "status",
    "surveyStatus",
    "title",
    "type",
    "randomization",
    "randomizationList",
    "version",
    "deferredDelete",
    "deferredDeleteReason",
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


sub get_ecrffieldmaxselectionsetvaluecount {

    my ($id,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get(&$get_ecrffieldmaxselectionsetvaluecount_path_query($id),$headers);

}

sub get_inquirymaxselectionsetvaluecount {

    my ($id,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get(&$get_inquirymaxselectionsetvaluecount_path_query($id),$headers);

}

sub get_probandlistentrymaxposition {

    my ($id,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return $api->get(&$get_probandlistentrymaxposition_path_query($id),$headers);

}

sub get_signup_list {

    my ($department_id,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_signuplist_path_query($department_id),$p,$sf),$headers),$p),$load_recursive,$restapi);

}

sub search {

    my ($in,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->post($api->get_collection_page_query_uri(&$get_search_path_query(),$p,$sf),$in,$headers),$p),$load_recursive,$restapi);

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

sub locked {
    my $self = shift;
    if ($self->{status}->{lockdown}) {
        return 1;
    }
    return 0;
}

sub transformitem {
    my ($item,$load_recursive,$restapi) = @_;
    if ($load_recursive) {
        $load_recursive = {} unless ref $load_recursive;
        override_fields($item,$load_recursive);
        my $field = "_activeInquiryCount";
        if ($load_recursive->{$field}) {
            my $p = { page_size => 0, };
            my $inquiries = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_trial_list(
                $item->{id},
                undef,
                1,
                1,
                $p,
                undef,
                $load_recursive,$restapi);
            $item->{$field} = $p->{total_count};
            $item->{_inquiriesNa} = (($item->{status}->{inquiryValueInputEnabled} and $item->{signupInquiries} and $item->{_activeInquiryCount} > 0) ? 0 : 1);
        }
    }
}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

sub TO_JSON {

    my $self = shift;
    return { %{$self} };




}

1;
