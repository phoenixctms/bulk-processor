package CTSMS::BulkProcessor::Projects::ETL::Ecrf;
use strict;

## no critic

use Tie::IxHash;

use CTSMS::BulkProcessor::Projects::ETL::EcrfSettings qw(

    $skip_errors

    $ecrf_data_api_ecrffields_page_size
    $ecrf_data_api_probandlistentrytags_page_size


    %colname_abbreviation
    ecrf_data_include_ecrffield
    $col_per_selection_set_value

    $show_page_progress
    $listentrytag_map_mode
);
#$ecrf_data_listentrytags

use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
    processing_debug
);
use CTSMS::BulkProcessor::LogError qw(
    rowprocessingwarn
    rowprocessingerror
    runerror
);

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTag qw();

use CTSMS::BulkProcessor::Array qw(array_to_map itemcount);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    get_ecrf_map
    get_horizontal_cols
    get_probandlistentrytag_map
    get_probandlistentrytag_colname
);

my $max_colname_length_warn = 64;

sub get_horizontal_cols {
    my ($context,$series_section_maxindex) = @_;
    my @columns = ();
    my $import = 0;
    $import = 1 if defined $series_section_maxindex;
    my $ecrf_map = $context->{ecrf_map};
    my @ecrfids = ();
    if (defined $context->{ecrf}) {
        push(@ecrfids,$context->{ecrf}->{id});
    } else {
        @ecrfids = keys %$ecrf_map;
    }
    foreach my $ecrfid (@ecrfids) {
        my @visits = ();
        if (defined $context->{visit}) {
            push(@visits,$context->{visit});
        } else {
            @visits = @{$ecrf_map->{$ecrfid}->{ecrf}->{visits} // []};
            push(@visits,{ id => undef, }) unless scalar @visits;
        }
        foreach my $visit (@visits) {
            foreach my $section (keys %{$ecrf_map->{$ecrfid}->{sections}}) {
                my $section_info = $ecrf_map->{$ecrfid}->{sections}->{$section};
                my $maxindex = 0;
                if ($section_info->{series}) {
                    if ($import) {
                        $maxindex = $series_section_maxindex;
                    } else {
                        $maxindex = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Ecrf::get_getecrffieldvaluessectionmaxindex($ecrfid, $visit->{id}, $section);
                        $maxindex = 0 unless length($maxindex);
                    }
                }
                foreach my $index (0..$maxindex) {
                    foreach my $ecrffield (@{$section_info->{fields}}) {
                        my @colnames = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_colnames(
                                ecrffield => $ecrffield,
                                ecrf => (defined $context->{ecrf} ? undef : $ecrffield->{ecrf}),
                                visit => ((defined $context->{visit} or not defined $visit->{id}) ? undef : $visit),
                                index => $index, col_per_selection_set_value => $col_per_selection_set_value, %colname_abbreviation,
                            );
                        my @selectionSetValues = @{$ecrffield->{field}->{selectionSetValues} // []};
                        #push(@selectionSetValues,undef) unless scalar @selectionSetValues;
                        for (my $i = 0; $i <= $#colnames; $i++) {
                            my $column = {
                                ecrffield => $ecrffield,
                                visit => (defined $visit->{id} ? $visit : undef),
                                colname => $colnames[$i],
                                index => ($ecrffield->{series} ? $index : undef),
                            };
                            if ($col_per_selection_set_value and $ecrffield->{field}->is_select_many()) {
                                $column->{colnames} = \@colnames;
                                $column->{selection_set_value} = $selectionSetValues[$i];
                            }
                            push(@columns,$column);
                        }

                        #for (my $i = 0; $i < $#colnames; $i++) {
                        #    push(@columns,{
                        #        ecrffield => $ecrffield,
                        #        visit => (defined $visit->{id} ? $visit : undef),
                        #        index => $index,
                        #        colname => $colnames[$i],
                        #        selection_set_value => $selectionSetValues[$i],
                        #        colnames => \@colnames,
                        #    });
                        #}
                    }
                }
            }
        }
    }
    my $max_colname_length = 0;
    my %dupe_map = ();
    foreach my $column (@columns) {
        my $colname = $column->{colname};
        my $length = length($colname);
        $max_colname_length = length($colname) if $length > $max_colname_length;
        my $dupe_colname_label;
        $dupe_colname_label = "duplicate column name: $colname ($dupe_map{$colname}->{ecrffield}->{uniqueName}, $column->{ecrffield}->{uniqueName})" if exists $dupe_map{$colname};
        if ($import) {
            _error($context,$dupe_colname_label) if exists $dupe_map{$colname};
        } else {
            _warn($context,"$colname length: $length") if $length > $max_colname_length_warn;
            _warn($context,$dupe_colname_label) if exists $dupe_map{$colname};
        }
        $dupe_map{$colname} = $column;
    }
    if ($import) {
        _info($context,'dictionary created for ' . (scalar @columns) . ' columns',1);
    } else {
        _info($context,(scalar @columns) . " columns, max column name length: $max_colname_length",0);
    }
    return \@columns;
}

sub get_ecrf_map {
    my ($context,$all) = @_;
    my %ecrf_map = ();
    tie(%ecrf_map, 'Tie::IxHash',
    );
    array_to_map(_get_ecrffields($context,$all),sub {
        my $item = shift;
        return $item->{ecrf}->{id};
    },undef,'group',\%ecrf_map);
    foreach my $ecrfid (keys %ecrf_map) {
        my %section_map = ();
        tie(%section_map, 'Tie::IxHash',
        );
        array_to_map($ecrf_map{$ecrfid},sub {
            my $item = shift;
            return $item->{section};
        },undef,'group',\%section_map);
        my $ecrf = undef;
        foreach my $section (keys %section_map) {
            my $series = $section_map{$section}->[0]->{series};
            $ecrf = $section_map{$section}->[0]->{ecrf} unless defined $ecrf;
            $section_map{$section} = {
                series => $series,
                fields => $section_map{$section},
            };
        }
        $ecrf_map{$ecrfid} = { ecrf => $ecrf, sections => \%section_map };
    }
    return \%ecrf_map;
}

sub _get_ecrffields {
    my ($context, $all) = @_;
    my $api_ecrffields_page = [];
    my $api_ecrffields_page_num = 0;
    my $api_ecrffields_page_total_count;
    my @ecrffields;
    while (1) {
        if ((scalar @$api_ecrffields_page) == 0) {
            my $p = { page_size => $ecrf_data_api_ecrffields_page_size , page_num => $api_ecrffields_page_num + 1, total_count => undef };
            my $sf = {};

            my $first = $api_ecrffields_page_num * $ecrf_data_api_ecrffields_page_size;
            _info($context,"fetch eCRF fields page: " . $first . '-' . ($first + $ecrf_data_api_ecrffields_page_size) . ' of ' . (defined $api_ecrffields_page_total_count ? $api_ecrffields_page_total_count : '?'),not $show_page_progress);
            $api_ecrffields_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::EcrfField::get_trial_list($context->{ecrf_data_trial}->{id}, undef,1, $p, $sf, { _selectionSetValueMap => 1 });
            $api_ecrffields_page_total_count = $p->{total_count};
            $api_ecrffields_page_num += 1;
        }
        my $ecrffield = shift @$api_ecrffields_page;
        last unless $ecrffield;
        push(@ecrffields,$ecrffield) if ($all or ecrf_data_include_ecrffield($ecrffield));
    }
    return \@ecrffields;
}

sub _get_probandlistentrytags {
    my ($context,$all) = @_;
    my $api_listentrytags_page = [];
    my $api_listentrytags_page_num = 0;
    my $api_listentrytags_page_total_count;
    my @listentrytags;
    while (1) {
        if ((scalar @$api_listentrytags_page) == 0) {
            my $p = { page_size => $ecrf_data_api_probandlistentrytags_page_size , page_num => $api_listentrytags_page_num + 1, total_count => undef };
            my $sf = { sort_by => 'position', sort_dir => 'asc', };

            my $first = $api_listentrytags_page_num * $ecrf_data_api_probandlistentrytags_page_size;
            _info($context,"fetch proband list attribute page: " . $first . '-' . ($first + $ecrf_data_api_probandlistentrytags_page_size) . ' of ' . (defined $api_listentrytags_page_total_count ? $api_listentrytags_page_total_count : '?'),not $show_page_progress);
            $api_listentrytags_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTag::get_trial_list($context->{ecrf_data_trial}->{id}, undef, $p, $sf, { _selectionSetValueMap => 1 });
            $api_listentrytags_page_total_count = $p->{total_count};
            $api_listentrytags_page_num += 1;
        }
        my $listentrytag = shift @$api_listentrytags_page;
        last unless $listentrytag;
        push(@listentrytags,$listentrytag) if ($all or $listentrytag->{ecrfValue});
    }
    return \@listentrytags;
}

sub get_probandlistentrytag_colname {
    my $item = shift;
    my ($colname) = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::ProbandListEntryTag::get_colnames(
        listentrytag => $item, col_per_selection_set_value => 0, %colname_abbreviation,
    );
    return $colname;
}

sub get_probandlistentrytag_map {
    my ($context) = @_;

    my %listentrytag_map = ();
    tie(%listentrytag_map, 'Tie::IxHash',
    );

    my @tag_cols = ();
    array_to_map(_get_probandlistentrytags($context), sub { my $item = shift;
            my $colname = get_probandlistentrytag_colname($item);
            push(@tag_cols,$colname);
            return $colname;
        },undef,$listentrytag_map_mode,\%listentrytag_map);
    foreach my $tag_col (keys %listentrytag_map) {
        _warn($context,"multiple proband list attributes '$tag_col', using $listentrytag_map_mode",getlogger(__PACKAGE__)) if itemcount($tag_col,\@tag_cols) > 1;
    }

    return \%listentrytag_map;
}

sub _warn_or_error {
    my ($context,$message) = @_;
    if ($skip_errors) {
        _warn($context,$message);
    } else {
        _error($context,$message);
    }
}

sub _error {

    my ($context,$message) = @_;
    $context->{error_count} = $context->{error_count} + 1;
    rowprocessingerror($context->{tid},$message,getlogger(__PACKAGE__));

}

sub _warn {

    my ($context,$message) = @_;
    $context->{warning_count} = $context->{warning_count} + 1;
    rowprocessingwarn($context->{tid},$message,getlogger(__PACKAGE__));

}

sub _info {

    my ($context,$message,$debug) = @_;
    if ($debug) {
        processing_debug($context->{tid},$message,getlogger(__PACKAGE__));
    } else {
        processing_info($context->{tid},$message,getlogger(__PACKAGE__));
    }
}

1;
