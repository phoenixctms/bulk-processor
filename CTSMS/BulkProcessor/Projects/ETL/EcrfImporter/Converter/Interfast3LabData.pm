package Converter::Interfast3LabData;
use strict;

## no critic

use File::Basename qw(basename);

use CTSMS::BulkProcessor::FileProcessors::CSVFileSimple qw();

use CTSMS::BulkProcessor::Projects::ETL::EcrfSettings qw(
    get_proband_columns
    get_probandlistentry_columns
);
use CTSMS::BulkProcessor::Projects::ETL::EcrfConnectorPool qw(
    get_csv_db
    destroy_all_dbs
);
use CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal qw();
use CTSMS::BulkProcessor::Projects::ETL::Job qw(
    @job_file
);

use CTSMS::BulkProcessor::SqlConnectors::CSVDB qw(
    $mimetype
    sanitize_column_name
);

use CTSMS::BulkProcessor::Utils qw(trim);
use CTSMS::BulkProcessor::Logging qw(
    getlogger
    processing_info
    scriptinfo
);
use CTSMS::BulkProcessor::LogError qw(
    rowprocessingerror
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    convert
    process
);

# Interfast3 lab exports: metadata line, then header, then data. Separator is ';'.
# Qualifier columns KZ1/KZ2/VKZ repeat after each analyte — rename to <analyte>_KZ1 etc.

sub process {
    return convert(@_);
}

sub convert {
    my ($file) = @_;

    rowprocessingerror(undef,'no input file specified',getlogger(__PACKAGE__)) unless length($file);
    scriptinfo("Interfast3LabData: converting $file",getlogger(__PACKAGE__));

    my $result = 1;
    my $outfile;
    my $header_found = 0;

    my $processor = CTSMS::BulkProcessor::FileProcessors::CSVFileSimple->new(
        field_separator => ';',
        numofthreads => 1,
        blocksize => 100,
    );

    $result = $processor->process(
        file => $file,
        multithreading => 0,
        static_context => { header_found_ref => \$header_found },
        process_code => sub {
            my ($context,$rows,$row_offset) = @_;
            my @out = ();

            foreach my $row (@$rows) {
                next unless (scalar @$row);
                next unless (scalar grep { length(trim($_ // '')) > 0; } @$row);

                unless ($context->{colnames}) {
                    next unless _is_header_row($row);
                    my @colnames = _normalize_colnames($row);
                    $context->{colnames} = \@colnames;
                    ${$context->{header_found_ref}} = 1;
                    $context->{prefix_count} = _prefix_column_count();
                    $context->{db} = &get_csv_db();
                    unless (CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal::create_table(1,\@colnames,{})) {
                        rowprocessingerror($context->{tid},'failed to create ecrf_data_horizontal intermediate table',getlogger(__PACKAGE__));
                        return 0;
                    }
                    processing_info($context->{tid},'created intermediate table with ' . (scalar @colnames) . ' value column(s)',getlogger(__PACKAGE__));
                    next;
                }

                my $col_count = scalar @{$context->{colnames}};
                my @values = ();
                for (my $i = 0; $i < $col_count; $i++) {
                    push(@values,trim($row->[$i] // ''));
                }
                my @out_row = ((undef) x $context->{prefix_count}, @values);
                push(@out,\@out_row);
            }

            if ((scalar @out) > 0) {
                eval {
                    $context->{db}->db_do_begin(CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal::getinsertstatement(0));
                    $context->{db}->db_do_rowblock(\@out);
                    $context->{db}->db_finish();
                };
                my $err = $@;
                if ($err) {
                    eval {
                        $context->{db}->db_finish(1);
                    };
                    rowprocessingerror($context->{tid},$err,getlogger(__PACKAGE__));
                    return 0;
                }
                processing_info($context->{tid},(scalar @out) . ' row(s) written',getlogger(__PACKAGE__));
            }

            return 1;
        },
        init_process_context_code => sub {
            my ($context) = @_;
            $context->{colnames} = undef;
            $context->{prefix_count} = 0;
            $context->{db} = undef;
        },
        uninit_process_context_code => sub {
            my ($context) = @_;
            undef $context->{db};
        },
    );

    unless ($result and $header_found) {
        destroy_all_dbs();
        rowprocessingerror(undef,'Interfast3LabData: no AnfoNr header row found in ' . $file,getlogger(__PACKAGE__))
            unless $header_found;
        return undef;
    }

    my $db = &get_csv_db();
    $outfile = $db->_gettablefilename(CTSMS::BulkProcessor::Projects::ETL::Dao::EcrfDataHorizontal::gettablename());
    destroy_all_dbs();
    @job_file = (
        $outfile,
        basename($outfile),
        $mimetype,
    );
    scriptinfo("Interfast3LabData: intermediate file $outfile",getlogger(__PACKAGE__));

    return $outfile;
}

sub _prefix_column_count {
    return 1 + (scalar get_proband_columns()) + (scalar get_probandlistentry_columns());
}

sub _is_header_row {
    my ($row) = @_;
    return (trim($row->[0] // '') =~ /^AnfoNr$/i) ? 1 : 0;
}

sub _normalize_colnames {
    my ($header) = @_;
    my @colnames = ();
    my %seen = ();
    my $last_analyte;

    foreach my $raw (@$header) {
        my $name = trim($raw // '');
        $name = 'col' unless length($name);

        if ($name =~ /^(KZ[12]|VKZ)$/i and length($last_analyte)) {
            $name = $last_analyte . '_' . $name;
        } elsif ($name !~ /^(KZ[12]|VKZ)$/i) {
            $last_analyte = $name;
        }

        $name = sanitize_column_name($name);

        my $base = $name;
        my $n = 1;
        while (exists $seen{lc($name)}) {
            $n++;
            $name = $base . '_' . $n;
        }
        $seen{lc($name)} = 1;
        push(@colnames,$name);
    }

    return @colnames;
}

1;
