package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTag;
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

use CTSMS::BulkProcessor::Utils qw(booltostring zerofill chopstring);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputField qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::RestItem);
our @EXPORT_OK = qw(
    get_item
    get_item_path

    get_trial_list

    get_colnames
);

my $default_restapi = \&get_ctsms_restapi;
my $get_item_path_query = sub {
    my ($id) = @_;
    return 'probandlistentrytag/' . $id;
};
my $get_trial_path_query = sub {
    my ($trial_id,$stratification) = @_;
    my %params = ();
    $params{stratification} = booltostring($stratification) if defined $stratification;
    return 'trial/' . $trial_id . '/list/probandlistentrytag' . get_query_string(\%params);
};

my $fieldnames = [
    "comment",
    "disabled",
    "excelDate",
    "excelValue",
    "ecrfValue",
    "externalId",
    "field",
    "id",
    "jsOutputExpression",
    "jsValueExpression",
    "jsVariableName",
    "modifiedTimestamp",
    "modifiedUser",
    "optional",
    "position",
    "trial",
    "uniqueName",
    "version",
    "stratification",
    "randomize",
    "title",
    "titleL10nKey",
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

sub get_trial_list {

    my ($trial_id,$stratification,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_trial_path_query($trial_id,$stratification),$p,$sf),$headers),$p),$load_recursive,$restapi);

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
    $item->{field} = CTSMS::BulkProcessor::RestRequests::ctsms::shared::InputFieldService::InputField::builditems_fromrows($item->{field},$load_recursive,$restapi);

}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

sub get_colnames {
    my %params = @_;
    my ($listentrytag,
        $get_colname_parts_code,
        $ignore_external_ids,
        $abbreviate_inputfield_name_code,
        $abbreviate_selectionvalue_code,
        $listentrytag_position_digits,
        $col_per_selection_set_value,
        $selectionValues,
        $sanitize_colname_symbols_code) = @params{qw/
            listentrytag
            get_colname_parts_code
            ignore_external_ids
            abbreviate_inputfield_name_code
            abbreviate_selectionvalue_code
            listentrytag_position_digits
            col_per_selection_set_value
            selectionValues
            sanitize_colname_symbols_code
        /};

    $get_colname_parts_code = sub { return (); } unless 'CODE' eq ref $get_colname_parts_code;
    $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; } unless 'CODE' eq ref $abbreviate_selectionvalue_code;
    my $selectionSetValues = $listentrytag->{field}->{selectionSetValues};
    $selectionSetValues = $selectionValues if exists $params{selectionValues};
    $selectionSetValues //= [];
    my @colnames = ();
    my $prefix;
    my @parts = &$get_colname_parts_code($listentrytag);
    unless ((scalar @parts) > 0) {
        my $external_id_used = 0;
        if (not $ignore_external_ids and defined $listentrytag->{externalId} and length($listentrytag->{externalId}) > 0) {
            push(@parts,$listentrytag->{externalId});

            $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; };
            $external_id_used = 1;
        # relying on collisison detection
        } elsif (not $ignore_external_ids and defined $listentrytag->{field}->{externalId} and length($listentrytag->{field}->{externalId}) > 0) {
            push(@parts,$listentrytag->{field}->{externalId});

            $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; };
            $external_id_used = 1;
        } else {
            $abbreviate_inputfield_name_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_inputfield_name_code;
            #$abbreviate_category_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_category_code;
            $listentrytag_position_digits //= 2;
            #push(@parts,&$abbreviate_category_code($inquiry->{category})) if length($inquiry->{category}) > 0;
            push(@parts,zerofill($listentrytag->{position},$listentrytag_position_digits));
            push(@parts,&$abbreviate_inputfield_name_code($listentrytag->{field}->{nameL10nKey},$listentrytag->{field}->{id}));
        }
        $prefix = 'a' unless $external_id_used; # a for proband list Attribute
    }
    if ($col_per_selection_set_value and $listentrytag->{field}->is_select()) {
        foreach my $selectionsetvalue (@$selectionSetValues) {
            push(@colnames,_sanitize_colname(join(' ',@parts,&$abbreviate_selectionvalue_code($selectionsetvalue->{value},$selectionsetvalue->{id})),$sanitize_colname_symbols_code,$prefix));
        }
    } else {
        push(@colnames,_sanitize_colname(join(' ',@parts),$sanitize_colname_symbols_code,$prefix));
    }
    return map { lc($_); } @colnames; # normalize to lowercase, as DBD are case-insensitive in general
}

sub _sanitize_colname {
    my ($colname,$sanitize_colname_symbols_code,$prefix) = @_;

    $colname = &$sanitize_colname_symbols_code($colname) if 'CODE' eq ref $sanitize_colname_symbols_code;

    $colname =~ s/[^0-9a-z_]/_/gi;
    $colname =~ s/_+/_/g;
    return $prefix . $colname if defined $prefix;
    return $colname;
}

1;
