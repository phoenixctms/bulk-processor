package CTSMS::BulkProcessor::Projects::ETL::ProbandCriteria;
use strict;

## no critic

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    scriptinfo
);
use CTSMS::BulkProcessor::LogError qw(
    scripterror
);

use CTSMS::BulkProcessor::Utils qw(
    booltostring
);

use Encode qw();

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criterion qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::DBModule qw(
    $PROBAND_DB
);
use CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    $proband_criteria_label
    $proband_criteria_category
    $proband_criteria_in
    proband_criteria_active
    resolve_proband_criteria
    search_proband_page
);

our $proband_criteria_label;
our $proband_criteria_category;
our $proband_criteria_in;

my $criteria_page_size = 100;

sub proband_criteria_active {
    return defined $proband_criteria_label && length($proband_criteria_label) > 0;
}

sub _query_option_supplied {
    return defined $proband_criteria_label;
}

sub _same_text {
    my ($left, $right) = @_;
    return defined $left && defined $right && lc($left) eq lc($right);
}

# Job and shell arguments arrive as raw UTF-8 bytes. uri_escape_utf8 encodes a
# character string, so leaving the bytes unmarked would encode them a second time.
sub _utf8_characters {
    my ($value) = @_;
    return $value unless defined $value;
    return $value if Encode::is_utf8($value);
    my $characters = $value;
    eval {
        $characters = Encode::decode('UTF-8', $value, Encode::FB_CROAK);
    };
    return $characters;
}

sub _find_proband_queries {
    my ($module, $category, $label) = @_;
    my @matches = ();
    my %seen = ();
    my $page_num = 0;
    my $total_count;

    while (1) {
        last if defined $total_count and $page_num * $criteria_page_size >= $total_count;
        my $p = {
            page_size => $criteria_page_size,
            page_num => $page_num + 1,
            total_count => undef,
            total_count_expected => not defined $total_count,
        };
        my $sf = {
            sort_by => 'id',
            sort_dir => 'asc',
            label => $label,
            deferredDelete => booltostring(0),
        };
        $sf->{category} = $category if defined $category;
        my $items = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_list($module, $p, $sf) // [];
        $total_count = $p->{total_count} if defined $p->{total_count};
        $page_num += 1;
        last unless @$items;
        foreach my $item (@$items) {
            next if $item->{deferredDelete};
            next unless _same_text($item->{label}, $label);
            if (defined $category) {
                next unless _same_text($item->{category}, $category);
            }
            next if $seen{$item->{id}}++;
            push(@matches, $item);
        }
        last if @$items < $criteria_page_size;
    }
    return @matches;
}

sub resolve_proband_criteria {
    my $logger = getlogger(__PACKAGE__);
    $proband_criteria_label = _utf8_characters($proband_criteria_label);
    $proband_criteria_category = _utf8_characters($proband_criteria_category);
    if (_query_option_supplied() and not proband_criteria_active()) {
        scripterror('--query requires a value', $logger);
    }
    if (defined $proband_criteria_category and length($proband_criteria_category) == 0) {
        scripterror('--query-category requires a value', $logger);
    }
    if (defined $proband_criteria_category and not proband_criteria_active()) {
        scripterror('--query-category requires --query', $logger);
    }
    return unless proband_criteria_active();

    my $label = $proband_criteria_label;
    my $category = $proband_criteria_category;
    my $module = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_module($PROBAND_DB);
    my @matches = _find_proband_queries($module, $category, $label);
    my $named = defined $category ? "'$label' in category '$category'" : "'$label'";
    if ((scalar @matches) == 0) {
        scripterror("no proband query named $named", $logger);
    } elsif ((scalar @matches) > 1) {
        my $ids = join(', ', map { $_->{id}; } @matches);
        scripterror("proband query $named is not unique (ids: $ids)", $logger);
    }

    my $criteria = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_item($matches[0]->{id});
    scripterror("error loading proband query $named", $logger) unless $criteria;
    my $criterions = $criteria->{criterions};
    if (not defined $criterions or 'ARRAY' ne ref $criterions) {
        $criterions = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criterion::get_items($criteria->{id}) // [];
    }

    $proband_criteria_in = {
        module => $PROBAND_DB,
        criterions => [ map { _criterion_in($_); } @$criterions ],
    };
    my $loaded_category = (defined $criteria->{category} and length($criteria->{category})) ? ", category '$criteria->{category}'" : '';
    scriptinfo("proband query '$criteria->{label}' (id $criteria->{id}$loaded_category), " . scalar(@{$proband_criteria_in->{criterions}}) . ' criterion(s)', $logger);
}

sub search_proband_page {
    my ($p, $sf) = @_;
    return CTSMS::BulkProcessor::RestRequests::ctsms::proband::ProbandService::Proband::search($proband_criteria_in, $p, $sf);
}

sub _criterion_in {
    my ($criterion) = @_;
    my %in = (
        position => $criterion->{position},
        tieId => _ref_id($criterion->{tie}, $criterion->{tieId}),
        propertyId => _ref_id($criterion->{property}, $criterion->{propertyId}),
        restrictionId => _ref_id($criterion->{restriction}, $criterion->{restrictionId}),
    );
    foreach my $field (qw(dateValue floatValue longValue stringValue timeValue timestampValue)) {
        $in{$field} = $criterion->{$field} if defined $criterion->{$field};
    }
    # Responses turn JSON true/false into 0/1. A bare number is rejected for booleanValue.
    if (defined $criterion->{booleanValue}) {
        $in{booleanValue} = $criterion->{booleanValue} ? \1 : \0;
    }
    return \%in;
}

sub _ref_id {
    my ($obj, $id) = @_;
    return $obj->{id} if ref $obj;
    return $id;
}

1;
