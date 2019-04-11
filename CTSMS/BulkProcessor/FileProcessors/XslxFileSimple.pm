package CTSMS::BulkProcessor::FileProcessors::XslxFileSimple;
use strict;

## no critic

use Excel::Reader::XLSX qw();

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    fileprocessingstarted
    fileprocessingdone
    lines_read
    processing_lines
);

use CTSMS::BulkProcessor::LogError qw(
    fileprocessingfailed
    fileprocessingwarn
    fileerror
);

use CTSMS::BulkProcessor::Utils qw(threadid);

use CTSMS::BulkProcessor::FileProcessor qw(create_process_context);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::FileProcessor);
our @EXPORT_OK = qw();

#my $default_sheet_name = undef; #'~';
my $default_blocksize = 100;

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::FileProcessor->new(@_);

    #$self->{numofthreads} = shift // $default_numofthreads;
    $self->{custom_formats} = shift;
    #$self->{sheet_name} = shift // $default_sheet_name;
    $self->{header_row} = shift // 0;
    $self->{blocksize} = $default_blocksize;

    bless($self,$class);

    return $self;

}

sub process {

    my $self = shift;

    my %params = @_;
    my ($file,
        $sheet_name,
        $process_code,
        $static_context,
        $skip_errors,
        $init_process_context_code,
        $uninit_process_context_code) = @params{qw/
            file
            sheet_name
            process_code
            static_context
            skip_errors
            init_process_context_code
            uninit_process_context_code
        /};

    fileprocessingstarted($file,getlogger(__PACKAGE__));
    my $result = 0;
    my $tid = threadid();
    my $context = create_process_context($static_context,{ instance => $self,
        filename => $file,
        tid      => $tid,
        sheet_name => $sheet_name,
    });
    eval {
        my $reader = Excel::Reader::XLSX->new();
        my $workbook = $reader->read_file($file);
        #my $workbook = Spreadsheet::Reader::ExcelXML->new($file);
        #    file => $file,
        #    #group_return_type => 'value',
        #    count_from_zero => 0,
        #    values_only => 1,
        #    empty_is_end => 1,
        #    group_return_type => ('HASH' eq ref $self->{custom_formats} ? 'value' : 'xml_value'),
        #    from_the_edge => 0,
        #    empty_return_type => 'undef_string',
        #    spaces_are_empty => 1,
        #    merge_data => 0,
        #    column_formats => 0,
        #);
        if (defined $init_process_context_code and 'CODE' eq ref $init_process_context_code) {
            &$init_process_context_code($context);
        }
        if (not defined $workbook) {
            fileerror('processing file - error reading file ' . $file . ': ' . $reader->error(),getlogger(__PACKAGE__));
        } else {
            my $sheet;
            if ($sheet_name) {
                $sheet = $workbook->worksheet($sheet_name);
                #xls2csvinfo('converting the ' . $sheet->name() . ' worksheet',getlogger(__PACKAGE__));
            } else {
                $sheet = $workbook->worksheet(0);
                #if (@{$workbook->worksheets()} > 1) {
                #    xls2csvinfo('multiple worksheets found, converting ' . $sheet->name(),getlogger(__PACKAGE__));
                #}
            }
            if (not defined $sheet) {
                #fileerror('processing file - error reading file ' . $file . ': ' . $workbook->error(),getlogger(__PACKAGE__));
                fileerror("invalid spreadsheet '$sheet_name'",getlogger(__PACKAGE__));
            } else {
                $result = 1;
                #_info($context,"worksheet '" . $worksheet->get_name() . "' opened");

                #$worksheet->set_custom_formats($self->{custom_formats}) if 'HASH' eq ref $self->{custom_formats};
                #$worksheet->set_custom_formats({
                #    2 =>'yyyy-mm-dd',
                #});
                #$worksheet->set_headers($self->{header_row}) if defined $self->{header_row};
                #if ($worksheet->header_row_set()) {
                #    $worksheet->go_to_or_past_row($worksheet->get_excel_position($worksheet->get_last_header_row()));
                #}

                my $i = 0;
                processing_lines($tid,$i,$self->{blocksize},undef,getlogger(__PACKAGE__));
                #my $value;
                my @rows = ();
                while ($result) {
                    #$value = $worksheet->fetchrow_arrayref;
                    my $row = $sheet->next_row();
                    last unless $row; #if (not $value or 'EOF' eq $value);
                    my @vals = $row->values();
                    #$i++;
                    #next if not ref $value;
                    push(@rows,\@vals);
                    if ((scalar @rows) >= $self->{blocksize}) {
                        $result &= &$process_code($context,\@rows,$i);
                        $i += scalar @rows;
                        processing_lines($tid,$i,$self->{blocksize},undef,getlogger(__PACKAGE__));
                        @rows = ();
                    }
                }
                $result &= &$process_code($context,\@rows,$i);
            }
        }
    };
    my $err = $@;
    eval {
        if (defined $uninit_process_context_code and 'CODE' eq ref $uninit_process_context_code) {
            &$uninit_process_context_code($context);
        }
    };
    if ($err) {
        if ($skip_errors) {
            fileprocessingwarn($file,$err,getlogger(__PACKAGE__));
        } else {
            fileprocessingfailed($file,getlogger(__PACKAGE__));
        }
        $result = 0;
    } else {
        fileprocessingdone($file,getlogger(__PACKAGE__));
    }
    return $result;

}

1;