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
    $proband_criteria_in
    proband_criteria_active
    resolve_proband_criteria
    search_proband_page
);

our $proband_criteria_label;
our $proband_criteria_in;

my $criteria_page_size = 100;

sub proband_criteria_active {
    return defined $proband_criteria_label && length($proband_criteria_label) > 0;
}

sub _split_query_name {
    my ($name) = @_;
    if (defined $name and $name =~ m{^([^/]+)/(.+)$}) {
        return ($1, $2);
    }
    return (undef, $name);
}

sub resolve_proband_criteria {
    return unless proband_criteria_active();

    my ($category, $label) = _split_query_name($proband_criteria_label);
    my $module = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_module($PROBAND_DB);
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
            next unless defined $item->{label} and $item->{label} eq $label;
            if (defined $category) {
                next unless defined $item->{category} and $item->{category} eq $category;
            }
            next if $seen{$item->{id}}++;
            push(@matches, $item);
        }
        last if @$items < $criteria_page_size;
    }

    my $logger = getlogger(__PACKAGE__);
    my $query_name = defined $category ? "$category/$label" : $label;
    if ((scalar @matches) == 0) {
        scripterror("no proband query named '$query_name'", $logger);
    } elsif ((scalar @matches) > 1) {
        my $ids = join(', ', map { $_->{id}; } @matches);
        scripterror("proband query '$query_name' is not unique (ids: $ids)", $logger);
    }

    my $criteria = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criteria::get_item($matches[0]->{id});
    scripterror("error loading proband query '$query_name'", $logger) unless $criteria;
    my $criterions = $criteria->{criterions};
    if (not defined $criterions or 'ARRAY' ne ref $criterions) {
        $criterions = CTSMS::BulkProcessor::RestRequests::ctsms::shared::SearchService::Criterion::get_items($criteria->{id}) // [];
    }

    $proband_criteria_in = {
        module => $PROBAND_DB,
        criterions => [ map { _criterion_in($_); } @$criterions ],
    };
    my $category = (defined $criteria->{category} and length($criteria->{category})) ? ", category '$criteria->{category}'" : '';
    scriptinfo("proband query '$criteria->{label}' (id $criteria->{id}$category), " . scalar(@{$proband_criteria_in->{criterions}}) . ' criterion(s)', $logger);
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
    foreach my $field (qw(booleanValue dateValue floatValue longValue stringValue timeValue timestampValue)) {
        $in{$field} = $criterion->{$field} if defined $criterion->{$field};
    }
    return \%in;
}

sub _ref_id {
    my ($obj, $id) = @_;
    return $obj->{id} if ref $obj;
    return $id;
}

1;
