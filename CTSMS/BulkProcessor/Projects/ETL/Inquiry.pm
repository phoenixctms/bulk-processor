package CTSMS::BulkProcessor::Projects::ETL::Inquiry;
use strict;

## no critic

use Tie::IxHash;

use CTSMS::BulkProcessor::Projects::ETL::InquirySettings qw(

    $skip_errors
    
    $active
    $active_signup    

    $inquiry_data_api_inquiries_page_size

    %colname_abbreviation
    inquiry_data_include_inquiry
    $col_per_selection_set_value

    $show_page_progress
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

use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry qw();

use CTSMS::BulkProcessor::Array qw(array_to_map);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    get_horizontal_cols
    get_category_map


);

my $max_colname_length_warn = 64;

sub get_horizontal_cols {
    my ($context,$import) = @_;
    my @columns = ();
    foreach my $category (keys %{$context->{category_map}}) {
        foreach my $inquiry (@{$context->{category_map}->{$category}}) {
            my @colnames = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_colnames(
                inquiry => $inquiry,

                col_per_selection_set_value => $col_per_selection_set_value,
                %colname_abbreviation,
            );
            my @selectionSetValues = @{$inquiry->{field}->{selectionSetValues} // []};
            #push(@selectionSetValues,undef) unless scalar @selectionSetValues;
            for (my $i = 0; $i <= $#colnames; $i++) {
                my $column = {
                    inquiry => $inquiry,
                    colname => $colnames[$i],
                };
                if ($col_per_selection_set_value and $inquiry->{field}->is_select_many()) {
                    $column->{colnames} = \@colnames;
                    $column->{selection_set_value} = $selectionSetValues[$i];
                }
                push(@columns,$column);
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
        $dupe_colname_label = "duplicate column name: $colname ($dupe_map{$colname}->{inquiry}->{uniqueName}, $column->{inquiry}->{uniqueName})" if exists $dupe_map{$colname};
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

sub get_category_map {
    my ($context) = @_;

    my %category_map = ();
    tie(%category_map, 'Tie::IxHash');
    
    array_to_map(_get_inquiries($context),sub {
        my $item = shift;
        return $item->{category};
    },undef,'group',\%category_map);
    
    return \%category_map;

}

sub _get_inquiries {
    my ($context) = @_;
    my $api_inquiries_page = [];
    my $api_inquiries_page_num = 0;
    my $api_inquiries_page_total_count;
    my @inquiries;
    while (1) {
        if ((scalar @$api_inquiries_page) == 0) {
            my $p = { page_size => $inquiry_data_api_inquiries_page_size , page_num => $api_inquiries_page_num + 1, total_count => undef };
            my $sf = {};

            my $first = $api_inquiries_page_num * $inquiry_data_api_inquiries_page_size;
            _info($context,"fetch inquiries page: " . $first . '-' . ($first + $inquiry_data_api_inquiries_page_size) . ' of ' . (defined $api_inquiries_page_total_count ? $api_inquiries_page_total_count : '?'),not $show_page_progress);
            $api_inquiries_page = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_trial_list($context->{inquiry_trial}->{id}, $active, $active_signup, 1, $p, $sf, { _selectionSetValueMap => 1 });
            $api_inquiries_page_total_count = $p->{total_count};
            $api_inquiries_page_num += 1;
        }
        my $inquiry = shift @$api_inquiries_page;
        last unless $inquiry;
        push(@inquiries,$inquiry) if inquiry_data_include_inquiry($inquiry);
    }
    return \@inquiries;
}


#sub get_section_blank {
#    
#    my ($context,$column) = @_;
#    
#    my $result = 1;
#    
#    my @colnames = map {
#        CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Inquiry::get_colnames(
#            ecrffield => $_,
#            ecrf => $_->{ecrf},
#            visit => ((defined $context->{visit} or not defined $column->{visit}) ? undef : $column->{visit}),
#            index => $column->{index}, col_per_selection_set_value => $col_per_selection_set_value, %colname_abbreviation,
#        );
#    } @{$context->{ecrf_map}->{$column->{ecrffield}->{ecrf}->{id}}->{sections}->{$column->{ecrffield}->{section}}->{fields}};
#    
#    foreach my $colname (@colnames) {
#        if (length($context->{record}->{$colname})) {
#            $result = 0;
#            last;
#        }
#    }
#    
#    return $result;
#    
#}

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
