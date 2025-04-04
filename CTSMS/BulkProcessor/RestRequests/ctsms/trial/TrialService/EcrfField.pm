package CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField;
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

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf qw();
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
    return 'ecrffield/' . $id;
};
my $get_trial_path_query = sub {
    my ($trial_id,$ecrf_id,$sort) = @_;
    my %params = ();
    $params{ecrfId} = $ecrf_id if defined $ecrf_id;
    $params{sort} = booltostring($sort);
    return 'trial/' . $trial_id . '/list/ecrffield' . get_query_string(\%params);
};

my $fieldnames = [
    "auditTrail",
    "comment",
    "disabled",
    "ecrf",
    "ref",
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
    "reasonForChangeRequired",
    "section",
    "series",
    "trial",
    "uniqueName",
    "version",
    "deferredDelete",
    "deferredDeleteReason",
    "notify",
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

    my ($trial_id,$ecrf_id,$sort,$p,$sf,$load_recursive,$restapi,$headers) = @_;
    my $api = _get_api($restapi,$default_restapi);
    return builditems_fromrows($api->extract_collection_items($api->get($api->get_collection_page_query_uri(&$get_trial_path_query($trial_id,$ecrf_id,$sort),$p,$sf),$headers),$p),$load_recursive,$restapi);

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
    $item->{ecrf} = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf::builditems_fromrows($item->{ecrf},$load_recursive,$restapi);

}

sub get_item_path {

    my ($id) = @_;
    return &$get_item_path_query($id);

}

sub get_colnames {
    my %params = @_;
    my ($ecrffield,
        $ecrf,
        $visit,
        $index,
        $get_colname_parts_code,
        $ignore_external_ids,
        $abbreviate_ecrf_name_code,
        $abbreviate_ecrf_revision_code,
        $abbreviate_visit_code,
        $abbreviate_section_code,
        $abbreviate_inputfield_name_code,
        $abbreviate_selectionvalue_code,
        $ecrffield_position_digits,
        $index_digits,
        $col_per_selection_set_value,
        $selectionValues,
        $sanitize_colname_symbols_code) = @params{qw/
            ecrffield
            ecrf
            visit
            index
            get_colname_parts_code
            ignore_external_ids
            abbreviate_ecrf_name_code
            abbreviate_ecrf_revision_code
            abbreviate_visit_code
            abbreviate_section_code
            abbreviate_inputfield_name_code
            abbreviate_selectionvalue_code
            ecrffield_position_digits
            index_digits
            col_per_selection_set_value
            selectionValues
            sanitize_colname_symbols_code
        /};
    $get_colname_parts_code = sub { return (); } unless 'CODE' eq ref $get_colname_parts_code;
    $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; } unless 'CODE' eq ref $abbreviate_selectionvalue_code;
    my $selectionSetValues = $ecrffield->{field}->{selectionSetValues};
    $selectionSetValues = $selectionValues if exists $params{selectionValues};
    $selectionSetValues //= [];
    my @colnames = ();
    my $prefix;
    my @parts = &$get_colname_parts_code($ecrffield,$visit,$index);
    unless ((scalar @parts) > 0) {
        my $external_id_used = 0;
        #$ecrf //= $ecrffield->{ecrf};
        if (defined $ecrf) {
            if (not $ignore_external_ids and defined $ecrf->{externalId} and length($ecrf->{externalId}) > 0) {
                push(@parts,$ecrf->{externalId});
                $external_id_used = 1;
            } else {
                $abbreviate_ecrf_name_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_ecrf_name_code;
                $abbreviate_ecrf_revision_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_ecrf_revision_code;
                my $ecrf_name = &$abbreviate_ecrf_name_code($ecrf->{name},$ecrf->{revision},$ecrf->{id});
                push(@parts,$ecrf_name) if defined $ecrf_name and length($ecrf_name) > 0;
                my $ecrf_revision = &$abbreviate_ecrf_revision_code($ecrf->{revision});
                push(@parts,$ecrf_revision) if defined $ecrf_revision and length($ecrf_revision) > 0;
            }
        }
        if (defined $visit) {
            $abbreviate_visit_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_visit_code;
            my $visit_token = &$abbreviate_visit_code($visit->{token},$visit->{title},$visit->{id});
            push(@parts,$visit_token) if defined $visit_token and length($visit_token) > 0;
        }
        $index_digits //= 2;
        if (not $ignore_external_ids and defined $ecrffield->{externalId} and length($ecrffield->{externalId}) > 0) {
            push(@parts,$ecrffield->{externalId});
            push(@parts,zerofill($index,$index_digits)) if $ecrffield->{series};
            $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; };
            $external_id_used = 1;
        # relying on collisison detection
        } elsif (not $ignore_external_ids and defined $ecrffield->{field}->{externalId} and length($ecrffield->{field}->{externalId}) > 0) {
            push(@parts,$ecrffield->{field}->{externalId});
            push(@parts,zerofill($index,$index_digits)) if $ecrffield->{series};
            $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; };
            $external_id_used = 1;
        } else {
            $abbreviate_inputfield_name_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_inputfield_name_code;
            $abbreviate_section_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_section_code;
            $ecrffield_position_digits //= 2;
            push(@parts,&$abbreviate_section_code($ecrffield->{section})) if length($ecrffield->{section}) > 0;
            push(@parts,zerofill($ecrffield->{position},$ecrffield_position_digits));
            push(@parts,&$abbreviate_inputfield_name_code($ecrffield->{field}->{nameL10nKey},$ecrffield->{field}->{id}));
            push(@parts,'i' . zerofill($index,$index_digits)) if $ecrffield->{series};

        }
        $prefix = 'e' unless $external_id_used; # e for Ecrffield
    }
    if ($col_per_selection_set_value and $ecrffield->{field}->is_select_many()) {
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
