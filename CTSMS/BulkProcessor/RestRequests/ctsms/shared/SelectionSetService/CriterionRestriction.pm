package CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CriterionRestriction;
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

#use CTSMS::BulkProcessor::Utils qw(booltostring);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_items
    
    $ID_EQ
    $ID_NE
    $EQ
    $NE
    $GT
    $GE
    $LT
    $LE
    $LIKE
    $ILIKE
    $IS_EMPTY
    $IS_NOT_EMPTY
    $IS_NULL
    $IS_NOT_NULL
    $SIZE_EQ
    $SIZE_NE
    $SIZE_GT
    $SIZE_GE
    $SIZE_LT
    $SIZE_LE
    $IS_EQ_TODAY
    $IS_NE_TODAY
    $IS_GT_TODAY
    $IS_GE_TODAY
    $IS_LT_TODAY
    $IS_LE_TODAY
    $IS_EQ_NOW
    $IS_NE_NOW
    $IS_GT_NOW
    $IS_GE_NOW
    $IS_LT_NOW
    $IS_LE_NOW
    $IS_EQ_CONTEXT_USER_ID
    $IS_NE_CONTEXT_USER_ID
    $IS_ID_EQ_CONTEXT_USER_ID
    $IS_ID_NE_CONTEXT_USER_ID
    $IS_EQ_CONTEXT_USER_DEPARTMENT_ID
    $IS_NE_CONTEXT_USER_DEPARTMENT_ID
    $IS_ID_EQ_CONTEXT_USER_DEPARTMENT_ID
    $IS_ID_NE_CONTEXT_USER_DEPARTMENT_ID
    $IS_EQ_CONTEXT_IDENTITY_ID
    $IS_NE_CONTEXT_IDENTITY_ID
    $IS_ID_EQ_CONTEXT_IDENTITY_ID
    $IS_ID_NE_CONTEXT_IDENTITY_ID
    $IS_EQ_CONTEXT_IDENTITY_DEPARTMENT_ID
    $IS_NE_CONTEXT_IDENTITY_DEPARTMENT_ID
    $IS_ID_EQ_CONTEXT_IDENTITY_DEPARTMENT_ID
    $IS_ID_NE_CONTEXT_IDENTITY_DEPARTMENT_ID
    $TRUE
    $IS_GT_TODAY_PLUS_PERIOD
    $IS_GE_TODAY_PLUS_PERIOD
    $IS_EQ_TODAY_PLUS_PERIOD
    $IS_NE_TODAY_PLUS_PERIOD
    $IS_LT_TODAY_PLUS_PERIOD
    $IS_LE_TODAY_PLUS_PERIOD
    $IS_GT_TODAY_MINUS_PERIOD
    $IS_GE_TODAY_MINUS_PERIOD
    $IS_EQ_TODAY_MINUS_PERIOD
    $IS_NE_TODAY_MINUS_PERIOD
    $IS_LT_TODAY_MINUS_PERIOD
    $IS_LE_TODAY_MINUS_PERIOD
    $IS_GT_NOW_PLUS_PERIOD
    $IS_GE_NOW_PLUS_PERIOD
    $IS_EQ_NOW_PLUS_PERIOD
    $IS_NE_NOW_PLUS_PERIOD
    $IS_LT_NOW_PLUS_PERIOD
    $IS_LE_NOW_PLUS_PERIOD
    $IS_GT_NOW_MINUS_PERIOD
    $IS_GE_NOW_MINUS_PERIOD
    $IS_EQ_NOW_MINUS_PERIOD
    $IS_NE_NOW_MINUS_PERIOD
    $IS_LT_NOW_MINUS_PERIOD
    $IS_LE_NOW_MINUS_PERIOD
    $HOUR_EQ
    $HOUR_GE
    $HOUR_GT
    $HOUR_LE
    $HOUR_LT
    $HOUR_NE
    $MINUTE_EQ
    $MINUTE_GE
    $MINUTE_GT
    $MINUTE_LE
    $MINUTE_LT
    $MINUTE_NE    
);

my $default_restapi = \&get_ctsms_restapi;
my $get_items_path_query = sub {
    return 'selectionset/allcriteriarestrictions';
};
#my $collection_path_query = 'api/' . $resource . '/';

my $fieldnames = [
    "id",
    "name",
    "nameL10nKey",
    "restriction",
];

our $ID_EQ = 'ID_EQ';
our $ID_NE = 'ID_NE';
our $EQ = 'EQ';
our $NE = 'NE';
our $GT = 'GT';
our $GE = 'GE';
our $LT = 'LT';
our $LE = 'LE';
our $LIKE = 'LIKE';
our $ILIKE = 'ILIKE';
our $IS_EMPTY = 'IS_EMPTY';
our $IS_NOT_EMPTY = 'IS_NOT_EMPTY';
our $IS_NULL = 'IS_NULL';
our $IS_NOT_NULL = 'IS_NOT_NULL';
our $SIZE_EQ = 'SIZE_EQ';
our $SIZE_NE = 'SIZE_NE';
our $SIZE_GT = 'SIZE_GT';
our $SIZE_GE = 'SIZE_GE';
our $SIZE_LT = 'SIZE_LT';
our $SIZE_LE = 'SIZE_LE';
our $IS_EQ_TODAY = 'IS_EQ_TODAY';
our $IS_NE_TODAY = 'IS_NE_TODAY';
our $IS_GT_TODAY = 'IS_GT_TODAY';
our $IS_GE_TODAY = 'IS_GE_TODAY';
our $IS_LT_TODAY = 'IS_LT_TODAY';
our $IS_LE_TODAY = 'IS_LE_TODAY';
our $IS_EQ_NOW = 'IS_EQ_NOW';
our $IS_NE_NOW = 'IS_NE_NOW';
our $IS_GT_NOW = 'IS_GT_NOW';
our $IS_GE_NOW = 'IS_GE_NOW';
our $IS_LT_NOW = 'IS_LT_NOW';
our $IS_LE_NOW = 'IS_LE_NOW';
our $IS_EQ_CONTEXT_USER_ID = 'IS_EQ_CONTEXT_USER_ID';
our $IS_NE_CONTEXT_USER_ID = 'IS_NE_CONTEXT_USER_ID';
our $IS_ID_EQ_CONTEXT_USER_ID = 'IS_ID_EQ_CONTEXT_USER_ID';
our $IS_ID_NE_CONTEXT_USER_ID = 'IS_ID_NE_CONTEXT_USER_ID';
our $IS_EQ_CONTEXT_USER_DEPARTMENT_ID = 'IS_EQ_CONTEXT_USER_DEPARTMENT_ID';
our $IS_NE_CONTEXT_USER_DEPARTMENT_ID = 'IS_NE_CONTEXT_USER_DEPARTMENT_ID';
our $IS_ID_EQ_CONTEXT_USER_DEPARTMENT_ID = 'IS_ID_EQ_CONTEXT_USER_DEPARTMENT_ID';
our $IS_ID_NE_CONTEXT_USER_DEPARTMENT_ID = 'IS_ID_NE_CONTEXT_USER_DEPARTMENT_ID';
our $IS_EQ_CONTEXT_IDENTITY_ID = 'IS_EQ_CONTEXT_IDENTITY_ID';
our $IS_NE_CONTEXT_IDENTITY_ID = 'IS_NE_CONTEXT_IDENTITY_ID';
our $IS_ID_EQ_CONTEXT_IDENTITY_ID = 'IS_ID_EQ_CONTEXT_IDENTITY_ID';
our $IS_ID_NE_CONTEXT_IDENTITY_ID = 'IS_ID_NE_CONTEXT_IDENTITY_ID';
our $IS_EQ_CONTEXT_IDENTITY_DEPARTMENT_ID = 'IS_EQ_CONTEXT_IDENTITY_DEPARTMENT_ID';
our $IS_NE_CONTEXT_IDENTITY_DEPARTMENT_ID = 'IS_NE_CONTEXT_IDENTITY_DEPARTMENT_ID';
our $IS_ID_EQ_CONTEXT_IDENTITY_DEPARTMENT_ID = 'IS_ID_EQ_CONTEXT_IDENTITY_DEPARTMENT_ID';
our $IS_ID_NE_CONTEXT_IDENTITY_DEPARTMENT_ID = 'IS_ID_NE_CONTEXT_IDENTITY_DEPARTMENT_ID';
our $TRUE = 'TRUE';
our $IS_GT_TODAY_PLUS_PERIOD = 'IS_GT_TODAY_PLUS_PERIOD';
our $IS_GE_TODAY_PLUS_PERIOD = 'IS_GE_TODAY_PLUS_PERIOD';
our $IS_EQ_TODAY_PLUS_PERIOD = 'IS_EQ_TODAY_PLUS_PERIOD';
our $IS_NE_TODAY_PLUS_PERIOD = 'IS_NE_TODAY_PLUS_PERIOD';
our $IS_LT_TODAY_PLUS_PERIOD = 'IS_LT_TODAY_PLUS_PERIOD';
our $IS_LE_TODAY_PLUS_PERIOD = 'IS_LE_TODAY_PLUS_PERIOD';
our $IS_GT_TODAY_MINUS_PERIOD = 'IS_GT_TODAY_MINUS_PERIOD';
our $IS_GE_TODAY_MINUS_PERIOD = 'IS_GE_TODAY_MINUS_PERIOD';
our $IS_EQ_TODAY_MINUS_PERIOD = 'IS_EQ_TODAY_MINUS_PERIOD';
our $IS_NE_TODAY_MINUS_PERIOD = 'IS_NE_TODAY_MINUS_PERIOD';
our $IS_LT_TODAY_MINUS_PERIOD = 'IS_LT_TODAY_MINUS_PERIOD';
our $IS_LE_TODAY_MINUS_PERIOD = 'IS_LE_TODAY_MINUS_PERIOD';
our $IS_GT_NOW_PLUS_PERIOD = 'IS_GT_NOW_PLUS_PERIOD';
our $IS_GE_NOW_PLUS_PERIOD = 'IS_GE_NOW_PLUS_PERIOD';
our $IS_EQ_NOW_PLUS_PERIOD = 'IS_EQ_NOW_PLUS_PERIOD';
our $IS_NE_NOW_PLUS_PERIOD = 'IS_NE_NOW_PLUS_PERIOD';
our $IS_LT_NOW_PLUS_PERIOD = 'IS_LT_NOW_PLUS_PERIOD';
our $IS_LE_NOW_PLUS_PERIOD = 'IS_LE_NOW_PLUS_PERIOD';
our $IS_GT_NOW_MINUS_PERIOD = 'IS_GT_NOW_MINUS_PERIOD';
our $IS_GE_NOW_MINUS_PERIOD = 'IS_GE_NOW_MINUS_PERIOD';
our $IS_EQ_NOW_MINUS_PERIOD = 'IS_EQ_NOW_MINUS_PERIOD';
our $IS_NE_NOW_MINUS_PERIOD = 'IS_NE_NOW_MINUS_PERIOD';
our $IS_LT_NOW_MINUS_PERIOD = 'IS_LT_NOW_MINUS_PERIOD';
our $IS_LE_NOW_MINUS_PERIOD = 'IS_LE_NOW_MINUS_PERIOD';
our $HOUR_EQ = 'HOUR_EQ';
our $HOUR_GE = 'HOUR_GE';
our $HOUR_GT = 'HOUR_GT';
our $HOUR_LE = 'HOUR_LE';
our $HOUR_LT = 'HOUR_LT';
our $HOUR_NE = 'HOUR_NE';
our $MINUTE_EQ = 'MINUTE_EQ';
our $MINUTE_GE = 'MINUTE_GE';
our $MINUTE_GT = 'MINUTE_GT';
our $MINUTE_LE = 'MINUTE_LE';
our $MINUTE_LT = 'MINUTE_LT';
our $MINUTE_NE = 'MINUTE_NE';

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::RestItem->new($class,$fieldnames);

    copy_row($self,shift,$fieldnames);

    return $self;

}

sub get_items {

    my ($load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->get(&$get_items_path_query(),$headers),$load_recursive,$restapi);

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


1;
