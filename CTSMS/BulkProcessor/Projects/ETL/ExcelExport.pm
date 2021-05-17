package CTSMS::BulkProcessor::Projects::ETL::ExcelExport;
use strict;

## no critic
no strict 'refs';

use Spreadsheet::WriteExcel qw();
use Excel::Writer::XLSX qw();
use Encode qw();

use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
);
use CTSMS::BulkProcessor::LogError qw(
    fileerror
    rowprocessingwarn
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    write_workbook
    $xlsextension
    $xlsmimetype
);

our $xlsextension = '.xls';
our $xlsmimetype = 'application/vnd.ms-excel';

our $xlsxextension = '.xlsx';
our $xlsxmimetype = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

sub write_workbook {

    my ($filename,$xslx,@modules) = @_;

    my ($workbook,$header_format,$cell_format) = _create_workbook($filename,$xslx);
    my $result = 0;
    if (defined $workbook) {
        foreach my $module (@modules) {
            my $rows = 0;
            my $sheetname = &{$module . '::gettablename'}();
            my $worksheet = $workbook->add_worksheet($sheetname);

            if (_write_output_table($worksheet,\$rows,$module,$header_format,$cell_format)) {
                processing_info(undef,"$rows rows written to spreadsheet '$sheetname'",getlogger(__PACKAGE__));
                $result = 1;
            } else {
                rowprocessingwarn(undef,"spreadsheet '$sheetname' skipped",getlogger(__PACKAGE__));
            }
        }
        $workbook->close();
    }
    return $result;

}

sub _create_workbook {

    my ($filename,$xslx) = @_;

    my $workbook = ($xslx ?
        Excel::Writer::XLSX->new($filename) :
        Spreadsheet::WriteExcel->new($filename)) or fileerror($!, getlogger(__PACKAGE__));

    my $header_format = $workbook->add_format();
    $header_format->set_bold();

    my $cell_format = undef;

    processing_info(undef,"workbook '$filename' created",getlogger(__PACKAGE__));

    return ($workbook,$header_format,$cell_format);

}

sub _write_output_table {

    my ($worksheet,$row_ref,$module,$header_format,$cell_format) = @_;

    my $col = 0;
    my $colnames = &{$module . '::gettablefieldnames'}();
    return 0 unless defined $colnames;
	foreach my $colname (@$colnames) {
		$worksheet->write_string($$row_ref, $col, $colname, $header_format);
		$col++;
	}
    $$row_ref = $$row_ref + 1;

    return &{$module . '::process_records'}(

        process_code => sub {
            my ($context,$records,$row_offset) = @_;
            my $rownum = $row_offset;
            foreach my $record (@$records) {
                $rownum++;
                $col = 0;
                foreach my $colname (@$colnames) {
                    $worksheet->write_blank( $$row_ref, $col, $cell_format ) unless defined $record->{$colname};
                    $worksheet->write_string($$row_ref, $col, ($context->{is_utf8} ? $record->{$colname} : _mark_utf8($record->{$colname})),$cell_format) if defined $record->{$colname};
                    $col++;
                }
                $$row_ref = $$row_ref + 1;
            }

            return 1;
        },
        init_process_context_code => sub {
            my ($context)= @_;

        },
        uninit_process_context_code => sub {
            my ($context)= @_;

        },
        load_recursive => 0,
        multithreading => 0,
        numofthreads => 0,
    );

}

sub _mark_utf8 {
    return Encode::decode("UTF-8", shift);
}

1;
