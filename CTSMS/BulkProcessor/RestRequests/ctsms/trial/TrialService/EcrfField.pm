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

    get_export_colnames
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
    $params{sort} = booltostring($sort); # if defined $section;
    return 'trial/' . $trial_id . '/list/ecrffield' . get_query_string(\%params);
};

my $fieldnames = [
    "auditTrail",
    "comment",
    "disabled",
    "ecrf",
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

#sub TO_JSON {
#
#    my $self = shift;
#    return { %{$self} };
#    #    value => $self->{zipcode},
#    #    label => $self->{zipcode},
#    #};
#
#}

sub get_export_colnames {
    my %params = @_;
    my ($ecrffield,
        $index,
        $get_colname_parts_code,
        $ignore_external_ids,
        $abbreviate_ecrf_name_code,
        $abbreviate_visit_code,
        $abbreviate_group_code,
        $abbreviate_section_code,
        $abbreviate_inputfield_name_code,
        $abbreviate_selectionvalue_code,
        $ecrf_position_digits,
        $ecrffield_position_digits,
        $index_digits,
        $selectionValues,
        $sanitize_colname_symbols_code) = @params{qw/
            ecrffield
            index
            get_colname_parts_code
            ignore_external_ids
            abbreviate_ecrf_name_code
            abbreviate_visit_code
            abbreviate_group_code
            abbreviate_section_code
            abbreviate_inputfield_name_code
            abbreviate_selectionvalue_code
            ecrf_position_digits
            ecrffield_position_digits
            index_digits
            selectionValues
            sanitize_colname_symbols_code
        /};
    $get_colname_parts_code = sub { return (); } unless 'CODE' eq ref $get_colname_parts_code;
    $abbreviate_selectionvalue_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_selectionvalue_code;
    my $selectionSetValues = $ecrffield->{field}->{selectionSetValues};
    $selectionSetValues = $selectionValues if exists $params{selectionValues};
    $selectionSetValues //= [];
    my @export_colnames = ();
    my $prefix;
    my @parts = &$get_colname_parts_code($ecrffield,$index);
    unless ((scalar @parts) > 0) {
        unless ($ignore_external_ids) {
            push(@parts,$ecrffield->{ecrf}->{externalId}) if defined $ecrffield->{ecrf}->{externalId} and length($ecrffield->{ecrf}->{externalId}) > 0;
            push(@parts,$ecrffield->{externalId}) if defined $ecrffield->{externalId} and length($ecrffield->{externalId}) > 0;
            push(@parts,$ecrffield->{field}->{externalId}) if defined $ecrffield->{field}->{externalId} and length($ecrffield->{field}->{externalId}) > 0;
        }
        if (defined $ecrffield->{externalId} and length($ecrffield->{externalId}) > 0
            or defined $ecrffield->{field}->{externalId} and length($ecrffield->{field}->{externalId}) > 0) {
            push(@parts,zerofill($index,$index_digits)) if $ecrffield->{series};
            $abbreviate_selectionvalue_code = sub { my ($value,$id) = @_; return $value; };
        } else {
            $prefix = 'p';
            $abbreviate_ecrf_name_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_ecrf_name_code;
            $abbreviate_visit_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_visit_code;
            $abbreviate_group_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_group_code;
            $abbreviate_section_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_section_code;
            $abbreviate_inputfield_name_code = sub { return shift; } unless 'CODE' eq ref $abbreviate_inputfield_name_code;
            $ecrf_position_digits //= 2;
            $ecrffield_position_digits //= 2;
            $index_digits //= 2;
            #$section_digits //= 2;
            #push(@parts,'C');
            push(@parts,&$abbreviate_group_code($ecrffield->{ecrf}->{group}->{token},$ecrffield->{ecrf}->{group}->{title},$ecrffield->{ecrf}->{group}->{id})) if $ecrffield->{ecrf}->{group};
            push(@parts,zerofill($ecrffield->{ecrf}->{position},$ecrf_position_digits));
            push(@parts,&$abbreviate_visit_code($ecrffield->{ecrf}->{visit}->{token},$ecrffield->{ecrf}->{visit}->{title},$ecrffield->{ecrf}->{visit}->{id})) if $ecrffield->{ecrf}->{visit};
            my $ecrf_name = &$abbreviate_ecrf_name_code($ecrffield->{ecrf}->{name},$ecrffield->{ecrf}->{id});
            push(@parts,$ecrf_name) if defined $ecrf_name and length($ecrf_name) > 0;
            #'SECT' . chopstring($ecrffield->{section},2,'')
            push(@parts,&$abbreviate_section_code($ecrffield->{section})) if length($ecrffield->{section}) > 0;
            push(@parts,zerofill($ecrffield->{position},$ecrffield_position_digits));
            push(@parts,&$abbreviate_inputfield_name_code($ecrffield->{field}->{nameL10nKey},$ecrffield->{field}->{id}));
            push(@parts,'i' . zerofill($index,$index_digits)) if $ecrffield->{series};
            #my $fieldtype = $ecrffield->{field}->{fieldType}->{nameL10nKey};
        }
    }
    if ($ecrffield->{field}->is_select()) {
        foreach my $selectionsetvalue (@$selectionSetValues) {
            push(@export_colnames,_sanitize_export_colname(join(' ',@parts,&$abbreviate_selectionvalue_code($selectionsetvalue->{value},$selectionsetvalue->{id})),$sanitize_colname_symbols_code,$prefix));
        }
    } else {
        push(@export_colnames,_sanitize_export_colname(join(' ',@parts),$sanitize_colname_symbols_code,$prefix));
    }
    return @export_colnames;
}

sub _sanitize_export_colname {
    my ($colname,$sanitize_colname_symbols_code,$p_prefix) = @_;

    $colname = &$sanitize_colname_symbols_code($colname) if 'CODE' eq ref $sanitize_colname_symbols_code;

    $colname =~ s/[^0-9a-z_]/_/gi;
    $colname =~ s/_+/_/g;
    return $p_prefix . $colname if defined $p_prefix;
    return $colname;
}

1;
