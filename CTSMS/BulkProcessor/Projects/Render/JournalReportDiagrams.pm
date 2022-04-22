package CTSMS::BulkProcessor::Projects::Render::JournalReportDiagrams;
use strict;

## no critic

use threads::shared qw();

use Tie::IxHash;


use CTSMS::BulkProcessor::Projects::Render::Settings qw(
    $output_path

    $journal_heatmap_filename
    $journal_heatmap_span_days
    $journal_heatmap_start_date
    $journal_heatmap_end_date
    $journal_heatmap_dimension

    $logon_heatmap_filename
    $logon_heatmap_span_days
    $logon_heatmap_start_date
    $logon_heatmap_end_date
    $logon_heatmap_dimension

    $journal_histogram_filename
    $journal_histogram_dimension
    $journal_histogram_interval
    $journal_histogram_year
    $journal_histogram_month
);

use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
    processing_debug
);
use CTSMS::BulkProcessor::LogError qw(
    rowprocessingerror
    rowprocessingwarn
);



use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_db
    destroy_dbs
);

use CTSMS::BulkProcessor::Projects::Render::GnuPlot qw(
    plot
    convert
);

use CTSMS::BulkProcessor::Utils qw(threadid tempfilename zerofill datestamp get_year);
use CTSMS::BulkProcessor::Calendar qw(weeks_of_year days_of_year days_of_month add_days date_delta split_date);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    create_journal_heatmap
    create_logon_heatmap
    create_journal_histogram
);

my %journal_entry_history_root_entities = ();
tie(%journal_entry_history_root_entities, 'Tie::IxHash',
    'inventory' => { label => 'inventory', color => '#4169e1' },
    'staff' => { label => '"person/organisation"', color => '#ffbbff' },
    'course' => { label => 'course', color => '#ffff00' },
    'trial' => { label => 'trial', color => '#00FF00' },
    'proband' => { label => 'proband', color => '#dcdcdc' },
    'input_field' => { label => '"input field"', color => '#ff4500' },
    'user' => { label => 'user', color => '#b22222' },
);

sub create_journal_heatmap {
    _create_journalentry_24hheatmap(

        title => "hourly data modifications",
        span_days => $journal_heatmap_span_days,
        start_date => $journal_heatmap_start_date,
        end_date => $journal_heatmap_end_date,
        colorboxlabel => "journal records created",
        filename => $journal_heatmap_filename,

        dpi => 300,
        dimension => $journal_heatmap_dimension,
    );
}

sub create_logon_heatmap {
    _create_journalentry_24hheatmap(
        filter => "(left(title,22)='erfolgreiche Anmeldung' or left(title,16)='successful logon')",
        title => "logins per hour",
        span_days => $logon_heatmap_span_days,
        start_date => $logon_heatmap_start_date,
        end_date => $logon_heatmap_end_date,
        colorboxlabel => "successful logins",
        filename => $logon_heatmap_filename,

        dpi => 300,
        dimension => $logon_heatmap_dimension,
    );
}

sub create_journal_histogram {
    _create_journalentry_histogram(

        title => "data modification histogram",
        year => $journal_histogram_year,
        month => $journal_histogram_month,
        interval => $journal_histogram_interval,
        filename => $journal_histogram_filename,

        dpi => 300,
        dimension => $journal_histogram_dimension,
    );
}


sub _create_journalentry_24hheatmap {

    my %params = @_;
    my ($filter,
        $title,
        $span_days,
        $start_date,
        $end_date,
        $colorboxlabel,
        $filename,
        $rotate,
        $dpi,
        $dimension) = @params{qw/
            filter
            title
            span_days
            start_date
            end_date
            colorboxlabel
            filename
            rotate
            dpi
            dimension
        /};

    my $db = get_ctsms_db();

    my $filter_where = (defined $filter and length($filter) > 0 ? ' where ' . $filter : '');
    my $statement;
    if ($start_date and $end_date) {

    } elsif (not $start_date and $end_date) {
        if ($span_days) {
            $start_date = add_days(split_date($end_date),-1 * $span_days);
        } else {
            $statement = "select date_trunc('day',min(modified_timestamp)) from journal_entry" . $filter_where;
            $start_date = substr($db->db_get_value($statement),0,10);
        }
    } elsif ($start_date and not $end_date) {
        if ($span_days) {
            $end_date = add_days(split_date($start_date),$span_days);
        } else {
            $end_date = datestamp();
        }
    } else {
        $end_date = datestamp();
        if ($span_days) {
            $start_date = add_days(split_date($end_date),-1 * $span_days);
        } else {
            $statement = "select date_trunc('day',min(modified_timestamp)) from journal_entry" . $filter_where;
            $start_date = substr($db->db_get_value($statement),0,10);
        }
    }
    my $days = date_delta($start_date,$end_date) + 1;

    _info('start date: ' . $start_date . ', end date: ' . $end_date . ', days: ' . $days);

    my $tempfilename = tempfilename('24hheatmap_XXXX',$output_path,undef);
    my $datafile = $tempfilename . '.txt';
    my $epsfile = $tempfilename . '.eps';
    my $pltfile = $tempfilename . '.plt';
    my @tmp_files = ($tempfilename);

    eval {
        local *DATA_FILE;
        open DATA_FILE, ">", $datafile or _error($!);
        _info('gnuplot data file created: ' . $datafile);
        push(@tmp_files,$datafile);
        my $start = $start_date;
        my $stop = add_days(split_date($start),1);

        my $max = 0;

        my $filter_and = (defined $filter and length($filter) > 0 ? $filter . ' and' : '');
        for (my $day = 0; $day <= $days; $day++) {
    	    for (my $hour = 0; $hour <= 23; $hour++) {
    		    $statement = "select count(*) from journal_entry where" . $filter_and . " modified_timestamp >= ? and modified_timestamp < ? and EXTRACT(HOUR FROM modified_timestamp) = ?";
    		    my $count = $db->db_get_value($statement, $start . ' 00:00:00', $stop . ' 00:00:00', $hour);
    		    print DATA_FILE substr($start,0,10) . "\t" . $hour . "\t" . $count . "\n";
    		    $max = $count > $max ? $count : $max;
    	    }
    	    $start = $stop;
    	    $stop = add_days(split_date($start),1);
    	    print DATA_FILE "\n";
        }
        close DATA_FILE;
        _info('hourly max: ' . $max);
        #https://fossies.org/diffs/gnuplot/4.6.6_vs_5.0.0/demo/heatmaps.dem-diff.html
        #gnuplot v5 does not work!
        #my $blah = join(',',map { local $_ = $_; '"" "'.$_.'"'; } @dates);
        local *PLT_FILE;
        open PLT_FILE, ">", $pltfile or _error($!);
        _info('gnuplot plt file created: ' . $pltfile);
        push(@tmp_files,$pltfile);
        print PLT_FILE <<"END_24HHEATMAP_PLT";
set term postscript eps color size 7,1.8
set output '$epsfile'
#clear
#reset
unset key
set view map
set title "$title"
#palfuncparam 5000,0.001
#set term postscript eps color size 7,1.8
#set output '$epsfile'

#set xlabel "time"
set timefmt "%Y-%m-%d"
set xdata time
set format x "%b %d\\n%Y"
set xtics border out scale default autofreq
set xrange [ "$start_date" : "$end_date" ] noreverse nowriteback
#set xtics add (blah)

#set ylabel "hour"
set yrange [ -0.500000 : 23.50000 ] reverse nowriteback
set ytics border out scale default ('00:00 - 01:00' 0, '06:00 - 07:00' 6, '12:00 - 13:00' 12, '18:00 - 19:00' 18, '23:00 - 24:00' 23 1)
set ytics add ( '' 1 1, '' 2 1, '' 3 1, '' 4 1, '' 5 1, '' 7 1, '' 8 1, '' 9 1, '' 10 1, '' 11 1, '' 13 1, '' 14 1, '' 15 1, '' 16 1, '' 17 1, '' 19 1, '' 20 1, '' 21 1, '' 22 1)

#set palette model RGB
set cblabel "$colorboxlabel"
set cbrange [ 0.00000 : $max ] noreverse nowriteback
set palette defined (0 "#3860FF", 1 "green", 2 "yellow", 4 "orange", 10 "red") #model RGB
plot '$datafile' using 1:2:3 with image
END_24HHEATMAP_PLT

        close PLT_FILE;

        _info('gnuplot eps file: ' . $epsfile);
        push(@tmp_files,$epsfile);
        plot($pltfile,'postscript');
        _info('output image: ' . $filename);
        convert($epsfile,$filename,$rotate, $dpi, $dimension);

    };
    my $err = $@;
    _cleanup_tmp_files(@tmp_files);
    if ($err) {
        _error($err);
    }

}




sub _create_journalentry_histogram {

    my %params = @_;
    my ($filter,
        $title,
        $year,
        $month,
        $interval,
        $filename,
        $rotate,
        $dpi,
        $dimension) = @params{qw/
            filter
            title
            year
            month
            interval
            filename
            rotate
            dpi
            dimension
        /};



    my $db = get_ctsms_db();

    $year //= get_year();
    my @root_entities = keys %journal_entry_history_root_entities;
    my $pivot = '"' . $root_entities[0] . '".' . $interval;
    my $statement = 'select ' . $pivot . ' as ' . $interval . ',' . join(',',map { local $_ = $_; '"'.$_.'".count as '.$_.'_count'; } @root_entities);
    $statement .= ' from '. join(',',map { local $_ = $_; _histogram_stmt_part($_,$year,$month,$interval,$filter) } @root_entities);
    shift @root_entities;
    if ((scalar @root_entities) > 0) {
        $statement .= ' where ' . join(' and ',map { local $_ = $_; $pivot . ' = "' . $_ . '".' . $interval; } @root_entities);
    }
    _info('year ' . $year . (defined $month ? ' month ' . $month : '') . ' interval ' . $interval);

    my $tempfilename = tempfilename('histogram_XXXX',$output_path,undef);
    my $datafile = $tempfilename . '.txt';
    my $epsfile = $tempfilename . '.eps';
    my $pltfile = $tempfilename . '.plt';
    my @tmp_files = ($tempfilename);

    eval {
        local *DATA_FILE;
        open DATA_FILE, ">", $datafile or _error($!);
        _info('gnuplot data file created: ' . $datafile);
        push(@tmp_files,$datafile);
        print DATA_FILE $interval . "\t" . join("\t",map { local $_ = $_; $_->{label}; } values %journal_entry_history_root_entities) . "\n";
        foreach my $row (@{ $db->db_get_all_arrayref($statement) }) {
            my $xlabel;
            if ('day' eq $interval) {
                if ($month) {
                    $xlabel = $year . '-' . zerofill($month,2) . '-' . zerofill($row->{$interval},2);
                } else {
                    $xlabel = add_days($year,1,1,$row->{$interval} - 1);
                }
            } elsif ('week' eq $interval) {
                $xlabel = '"' . zerofill($row->{$interval},2) . '/' . $year . '"';
            }
            print DATA_FILE $xlabel . "\t" . join("\t",map { local $_ = $_; $row->{$_ . '_count'}; } keys %journal_entry_history_root_entities) . "\n";
    	}
        close DATA_FILE;
        local *PLT_FILE;
        open PLT_FILE, ">", $pltfile or _error($!);
        _info('gnuplot plt file created: ' . $pltfile);
        push(@tmp_files,$pltfile);
        my $max_root_entity_col_index = (scalar keys %journal_entry_history_root_entities) + 1;
        my @line_styles = ();
        my $col_index = 2;
        foreach my $col (keys %journal_entry_history_root_entities) {
            push(@line_styles,'set style line ' . $col_index . ' lc rgb "' .
                $journal_entry_history_root_entities{$col}->{color} . '" lt 1 lw 2 pt 7 ps 1.5');
            $col_index++;
        }
        my $linestyles = join("\n",@line_styles);
        my $xtics = ((!defined $month and $interval eq 'day') ? 'xtic(int($0)%10==9 ? strcol(1):"")' : 'xticlabels(1)');
        #plot for loops require 4.4 https://stackoverflow.com/questions/14946530/loop-structure-inside-gnuplot
        print PLT_FILE <<"END_HISTOGRAM_PLT";
set term postscript eps size 7,3.5 color
#font 'Helvetica,20' linewidth 2
set output '$epsfile'
#clear
#reset
set title "$title"
#unset key
# Make the x axis labels easier to read.
set xtics rotate out
# Select histogram data
set style data histogram
# Give the bars a plain fill pattern, and draw a solid line around them.
set style fill solid border
set autoscale y
#set autoscale y
#set xlabel "time (week number)"
#set ylabel "journal entry records (system messages)"
#set term postscript eps size 7,3.5 color
##font 'Helvetica,20' linewidth 2
#set output '$epsfile'

set xtics border nomirror out scale default
#set xtics add ("" "2013-02-01","" "2013-04-01","" "2013-06-01","" "2013-08-01","" "2013-10-01","" "2013-12-01","" "2014-02-01","" "2014-04-01","" "2014-06-01")
set ytics border out scale default autofreq

set grid
#set key font ",10"
#set xtics font ", 10"
#set ytics font ", 10"
set key left top
set format y "%gk"
set yrange [ 0 : * ]

$linestyles

set style histogram rowstacked
set boxwidth 0.6 relative
plot for [COL=2:$max_root_entity_col_index] '$datafile' using (column(COL)/1000):$xtics title columnheader ls COL
END_HISTOGRAM_PLT

        close PLT_FILE;

        _info('gnuplot eps file: ' . $epsfile);
        push(@tmp_files,$epsfile);
        plot($pltfile,'postscript');
        _info('output image: ' . $filename);
        convert($epsfile,$filename,$rotate, $dpi, $dimension);

    };
    my $err = $@;
    _cleanup_tmp_files(@tmp_files);
    if ($err) {
        _error($err);
    }

}

sub _cleanup_tmp_files {
    foreach my $file (@_) {
        unlink $file;
        _info('cleanup: ' . $file);
    }
}

sub _histogram_stmt_part {
    my ($root_entity,$year,$month,$interval,$filter) = @_;
    my $extract;
    my $intervals;
    if ('day' eq $interval) {
        if ($month) {
            $extract = 'day';
        } else {
            $extract = 'doy';
        }
    } elsif ('week' eq $interval) {
        $extract = 'week';
    } else {
        _error('unknonw interval ' . $interval);
    }
    my $restriction = "and extract(year from je.modified_timestamp) = $year";
    if ($month) {
        $restriction .= " and extract(month from je.modified_timestamp) = $month";
        $intervals = days_of_month($month,$year) if ('day' eq $interval);
        _error('week interval for month period not supported') if ('week' eq $interval);
    } else {
        $intervals = days_of_year($year) if ('day' eq $interval);
        $intervals = weeks_of_year($year) if ('week' eq $interval);
    }
    $intervals = join(', ',map { local $_ = $_; '(' . $_ . ', 0)'; } (1 .. $intervals));
    $filter = (defined $filter and length($filter) > 0 ? ' and ' . $filter : '');
    my $journal_module = uc($root_entity) . '_JOURNAL';
    my $db_module = uc($root_entity) . '_DB';
    my $statement = <<"END_STATEMENT";
(
 select
   sub.i as $interval,
   max(sub.cnt) as count
 from
   (
     (
       select
         extract($extract from je.modified_timestamp) as i,
         count(*) as cnt
       from
         journal_entry as je
         left join criteria as q on je.criteria_fk=q.id
       where
         je.system_message='t'
         $restriction
         and (je.system_message_module = '$journal_module' or (je.system_message_module = 'CRITERIA_JOURNAL' and q.module = '$db_module'))
         $filter
       group by i
     )
   union
     values $intervals
   ) as sub
 group by $interval order by $interval asc
) as "$root_entity"
END_STATEMENT

    return $statement;
}


sub _error {

    my ($message) = @_;

    rowprocessingerror(threadid(),$message,getlogger(__PACKAGE__));

}

sub _warn {

    my ($message) = @_;

    rowprocessingwarn(threadid(),$message,getlogger(__PACKAGE__));

}

sub _info {

    my ($message,$debug) = @_;
    if ($debug) {
        processing_debug(threadid(),$message,getlogger(__PACKAGE__));
    } else {
        processing_info(threadid(),$message,getlogger(__PACKAGE__));
    }
}

1;
