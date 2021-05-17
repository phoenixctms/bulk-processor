package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry;
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
    return 'inquiry/' . $id;
};
my $get_trial_path_query = sub {
    my ($trial_id, $active, $active_signup, $sort) = @_;
    my %params = ();
    $params{active} = booltostring($active) if defined $active;
    $params{activeSignup} = booltostring($active_signup) if defined $active_signup;
    $params{sort} = booltostring($sort);
    return 'trial/' . $trial_id . '/list/inquiry' . get_query_string(\%params);
};

my $fieldnames = [
    "active",
    "activeSignup",
    "category",
    "comment",
    "disabled",
    "excelDate",
    "excelValue",
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
    "deferredDelete",
    "deferredDeleteReason",
    "externalId",
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

    my ($trial_id,$active,$active_signup,$sort,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_trial_path_query($trial_id,$active,$active_signup,$sort),$p,$sf),$headers),$p),$load_recursive,$restapi);

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

sub TO_JSON {

    my $self = shift;
    return { %{$self} };

}

sub get_colnames {
    my %params = @_;
    my ($inquiry,
        $get_colname_parts_code,
        $ignore_external_ids,
        $abbreviate_category_code,
        $abbreviate_inputfield_name_code,
        $abbreviate_selectionvalue_code,
        $inquiry_position_digits,
        $col_per_selection_set_value,
        $selectionValues,
        $sanitize_colname_symbols_code) = @params{qw/
            inquiry
            get_colname_parts_code
            ignore_external_ids
            abbreviate_category_code
            abbreviate_inputfield_name_code
            abbreviate_selectionvalue_code
            inquiry_position_digits
            col_per_selection_set_value
            selectionValues
            sanitize_colname_symbols_code
        /};

    $get_colname_parts_code = sub { return (); } unless 'CODE' eq ref $get_colname_parts_code;
    $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; } unless 'CODE' eq ref $abbreviate_selectionvalue_code;
    my $selectionSetValues = $inquiry->{field}->{selectionSetValues};
    $selectionSetValues = $selectionValues if exists $params{selectionValues};
    $selectionSetValues //= [];
    my @colnames = ();
    my $prefix;
    my @parts = &$get_colname_parts_code($inquiry);
    unless ((scalar @parts) > 0) {
        my $external_id_used = 0;
        if (not $ignore_external_ids and defined $inquiry->{externalId} and length($inquiry->{externalId}) > 0) {
            push(@parts,$inquiry->{externalId});

            $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; };
            $external_id_used = 1;
        # relying on collisison detection
        } elsif (not $ignore_external_ids and defined $inquiry->{field}->{externalId} and length($inquiry->{field}->{externalId}) > 0) {
            push(@parts,$inquiry->{field}->{externalId});

            $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; };
            $external_id_used = 1;
        } else {
            $abbreviate_inputfield_name_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_inputfield_name_code;
            $abbreviate_category_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_category_code;
            $inquiry_position_digits //= 2;
            push(@parts,&$abbreviate_category_code($inquiry->{category})) if length($inquiry->{category}) > 0;
            push(@parts,zerofill($inquiry->{position},$inquiry_position_digits));
            push(@parts,&$abbreviate_inputfield_name_code($inquiry->{field}->{nameL10nKey},$inquiry->{field}->{id}));
        }
        $prefix = 'i' unless $external_id_used; # i for Inquiry
    }
    if ($col_per_selection_set_value and $inquiry->{field}->is_select()) {
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
