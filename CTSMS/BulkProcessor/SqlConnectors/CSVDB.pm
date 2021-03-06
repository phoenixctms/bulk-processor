package CTSMS::BulkProcessor::SqlConnectors::CSVDB;
use strict;

## no critic

use CTSMS::BulkProcessor::Globals qw(
    $LongReadLen_limit
    $csv_path);

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    dbdebug
    dbinfo
    xls2csvinfo
    texttablecreated
    indexcreated
    tabletruncated
    tabledropped);

use CTSMS::BulkProcessor::LogError qw(
    dberror
    dbwarn
    fieldnamesdiffer
    fileerror
    filewarn
    xls2csverror
    xls2csvwarn);

use CTSMS::BulkProcessor::Array qw(contains setcontains);

use CTSMS::BulkProcessor::Utils qw(makepath changemod chopstring);

use CTSMS::BulkProcessor::SqlConnector;

use DBI;
use DBD::CSV 0.26;
use File::Path qw(remove_tree);
use Locale::Recode;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseExcel::FmtUnicode;
use Excel::Reader::XLSX;
use Text::CSV_XS;
use File::Basename;
use MIME::Parser;
use HTML::PullParser qw();
use HTML::Entities qw(decode_entities);
use IO::Uncompress::Unzip qw(unzip $UnzipError);

use File::Copy qw();

# no debian package yet:
#use DateTime::Format::Excel;

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::SqlConnector);
our @EXPORT_OK = qw(
    cleanupcsvdirs
    xlsbin2csv
    xlsxbin2csv
    sanitize_column_name
    sanitize_spreadsheet_name
    get_tableidentifier
    $csvextension
    $mimetype
);

our $csvextension = '.csv';
our $mimetype = 'text/csv';

my $default_csv_config = { eol         => "\r\n",
                            sep_char    => ';',
                            quote_char  => '"',
                            escape_char => '"',
                          };

my @TABLE_TAGS = qw(table tr td);

my $LongReadLen = $LongReadLen_limit; #bytes
my $LongTruncOk = 0;

my $rowblock_transactional = 0;

my $invalid_excel_spreadsheet_chars_pattern = '[' . quotemeta('[]:*?/\\') . ']';

my $encoding = undef; #"utf8";

sub sanitize_spreadsheet_name { #Invalid character []:*?/\ in worksheet name
    my $spreadsheet_name = shift;
    $spreadsheet_name =~ s/$invalid_excel_spreadsheet_chars_pattern//g;
    return chopstring($spreadsheet_name,31); #Sheetname eventually inconsistent etc. must be <= 31 chars
}

sub sanitize_column_name {
    my $column_name = shift;
    $column_name =~ s/\W/_/g;
    return $column_name;
}

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::SqlConnector->new(@_);

    $self->{db_dir} = undef;
    $self->{f_dir} = undef;
    $self->{csv_tables} = undef;
    $self->{files} = undef;

    $self->{drh} = DBI->install_driver('CSV');

    bless($self,$class);

    dbdebug($self,__PACKAGE__ . ' connector created',getlogger(__PACKAGE__));

    return $self;

}

sub _connectidentifier {

    my $self = shift;
    return $self->{f_dir};

}

sub tableidentifier {

    my $self = shift;
    my $tablename = shift;
    return $tablename;

}

sub _columnidentifier {

    my $self = shift;
    my $columnname = shift;

    return sanitize_column_name($columnname); #actually happens automatically by dbd::csv

}

sub get_tableidentifier {

    my ($tablename,$db_dir) = @_;
    if (defined $db_dir) {
        return $db_dir . '.' . $tablename;
    } else {
        return $tablename;
    }

}

sub getsafetablename {

    my $self = shift;
    my $tableidentifier = shift;
    return lc($self->SUPER::getsafetablename($tableidentifier));

}

sub getdatabases {

    my $self = shift;

    local *DBDIR;
    if (not opendir(DBDIR, $csv_path)) {
        fileerror('cannot opendir ' . $csv_path . ': ' . $!,getlogger(__PACKAGE__));
        return [];
    }
    my @dirs = grep { $_ ne '.' && $_ ne '..' && -d $csv_path . $_ } readdir(DBDIR);
    closedir DBDIR;
    my @databases = ();
    foreach my $dir (@dirs) {
        push @databases,$dir;
    }
    return \@databases;

}

sub _createdatabase {

    my $self = shift;
    my ($db_dir) = @_;

    my $f_dir;
    if (length($db_dir) > 0) {
        $f_dir = $csv_path . $db_dir . '/';
    } else {
        $f_dir = $csv_path;
    }

    dbinfo($self,'opening csv folder',getlogger(__PACKAGE__));

    makepath($f_dir,\&fileerror,getlogger(__PACKAGE__));

    return $f_dir;
}

sub db_connect {

    my $self = shift;

    my ($db_dir,$csv_tables) = @_;

    $self->SUPER::db_connect($db_dir,$csv_tables);

    $self->{db_dir} = $db_dir;
    $self->{csv_tables} = $csv_tables;
    $self->{f_dir} = $self->_createdatabase($db_dir);

    my $dbh_config = {
            f_schema        => undef,

            cvs_eol         => $default_csv_config->{eol},
            cvs_sep_char    => $default_csv_config->{sep_char},
            cvs_quote_char  => $default_csv_config->{quote_char},
            cvs_escape_char => $default_csv_config->{escape_char},

            csv_null        => 1, # compatibility with CSVFile.pm
            f_encoding      => $encoding,

            PrintError      => 0,
            RaiseError      => 0,
        };
    my $usetabledef = 0;
    if (defined $csv_tables and ref $csv_tables eq 'HASH') {
        $usetabledef = 1;
    } else {
        $dbh_config->{f_dir} = $self->{f_dir};
        $dbh_config->{f_ext} = $csvextension . '/r';

    }

    my $dbh = DBI->connect ('dbi:CSV:','','',$dbh_config) or
        dberror($self,'error connecting: ' . $self->{drh}->errstr(),getlogger(__PACKAGE__));

    $dbh->{InactiveDestroy} = 1;

    $dbh->{LongReadLen} = $LongReadLen;
    $dbh->{LongTruncOk} = $LongTruncOk;

    $self->{dbh} = $dbh;

    if ($usetabledef) {
        my @files = ();
        foreach my $tablename (keys %$csv_tables) {
            $dbh->{csv_tables}->{$tablename} = $csv_tables->{$tablename};
            push @files,$csv_tables->{$tablename}->{file};
            dbinfo($self,'using ' . $csv_tables->{$tablename}->{file},getlogger(__PACKAGE__));
        }
        $self->{files} = \@files;
    } else {
        my @tablenames = $self->_list_tables();
        foreach my $tablename (@tablenames) {
            $dbh->{csv_tables}->{$tablename} = { eol         => $default_csv_config->{eol},
                                                 sep_char    => $default_csv_config->{sep_char},
                                                 quote_char  => $default_csv_config->{quote_char},
                                                 escape_char => $default_csv_config->{escape_char},
                                               }
        }
    }

    dbinfo($self,'connected',getlogger(__PACKAGE__));

}


sub _list_tables {
    my $self = shift;
    my @table_list;

    eval {
        @table_list = map { local $_ = $_; s/^\.\///g; $_; } $self->{dbh}->func('list_tables');
    };
    if ($@) {
        my @tables;
        eval {
            @tables = $self->{dbh}->func("get_avail_tables") or return;
        };
        if ($@) {
              dberror($self,'error listing csv tables: ' . $@,getlogger(__PACKAGE__));
        } else {
            foreach my $ref (@tables) {
                if (defined $ref) {
                    if (ref $ref eq 'ARRAY') {
                        push @table_list, $ref->[2];


                    }
                }
            }
        }
    }

    return @table_list;
}

sub _db_disconnect {

    my $self = shift;

    $self->SUPER::_db_disconnect();

}

sub vacuum {

    my $self = shift;
    my $tablename = shift;

}

sub cleanupcsvdirs {

    my (@remainingdbdirs) = @_;
    local *DBDIR;
    if (not opendir(DBDIR, $csv_path)) {
        fileerror('cannot opendir ' . $csv_path . ': ' . $!,getlogger(__PACKAGE__));
        return;
    }
    my @dirs = grep { $_ ne '.' && $_ ne '..' && -d $csv_path . $_ } readdir(DBDIR);
    closedir DBDIR;
    my @remainingdbdirectories = ();
    foreach my $dirname (@remainingdbdirs) {
        push @remainingdbdirectories,$csv_path . $dirname . '/';
    }
    foreach my $dir (@dirs) {

        my $dirpath = $csv_path . $dir . '/';
        if (not contains($dirpath,\@remainingdbdirectories)) {
            remove_tree($dirpath, {
                'keep_root' => 0,
                'verbose' => 1,
                'error' => \my $err });
            if (@$err) {
                for my $diag (@$err) {
                    my ($file, $message) = %$diag;
                    if ($file eq '') {
                        filewarn("cleanup: $message",getlogger(__PACKAGE__));
                    } else {
                        filewarn("problem unlinking $file: $message",getlogger(__PACKAGE__));
                    }
                }
            }
        }
    }

}

sub getfieldnames {

    my $self = shift;
    my $tablename = shift;

    my $fieldnames = [];

    if (defined $self->{dbh}) {

        my $query = 'SELECT * FROM ' . $self->tableidentifier($tablename) . ' LIMIT 1';
        dbdebug($self,'getfieldnames: ' . $query,getlogger(__PACKAGE__));
        my $sth = $self->{dbh}->prepare($query) or $self->_prepare_error($query);
        $sth->execute() or $self->_execute_error($query,$sth,());
        $fieldnames = $sth->{NAME};
        $sth->finish();

    }

    return $fieldnames;

}

sub getprimarykeycols {

    my $self = shift;
    my $tablename = shift;
    return [];

}

sub create_primarykey {

    my $self = shift;
    my ($tablename,$keycols,$fieldnames) = @_;

    return 0;
}
sub create_indexes {

    my $self = shift;
    my ($tablename,$indexes,$keycols) = @_;

    return 0;
}

sub _gettablefilename {

    my $self = shift;
    my $tablename = shift;
    return $self->{f_dir} . $tablename . $csvextension;

}

sub copytablefile {

    my $self = shift;
    my $tablename = shift;
    my $target = shift;
    my $tablefilename = $self->_gettablefilename($tablename);
    $self->db_disconnect();
    if (File::Copy::copy($tablefilename,$target)) {
      dbinfo($self,"$tablefilename copied to $target",getlogger(__PACKAGE__));
    } else {
      dberror($self,"copy from $tablefilename to $target failed: $!",getlogger(__PACKAGE__));
    }

}

sub create_texttable {

    my $self = shift;
    my ($tablename,$fieldnames,$keycols,$indexes,$truncate) = @_;

    if (length($tablename) > 0 and defined $fieldnames and ref $fieldnames eq 'ARRAY') {

        my $created = 0;
        if ($self->table_exists($tablename) == 0) {

            if (not exists $self->{dbh}->{csv_tables}->{$tablename}) {
                $self->{dbh}->{csv_tables}->{$tablename} = { eol         => $default_csv_config->{eol},
                                                             sep_char    => $default_csv_config->{sep_char},
                                                             quote_char  => $default_csv_config->{quote_char},
                                                             escape_char => $default_csv_config->{escape_char},
                                                           };
            }

            my $statement = 'CREATE TABLE ' . $self->tableidentifier($tablename) . ' (';
            $statement .= join(' TEXT, ',map { local $_ = $_; $_ = $self->columnidentifier($_); $_; } @$fieldnames) . ' TEXT';
            $statement .= ')';

            $self->db_do($statement);

            changemod($self->_gettablefilename($tablename));

            texttablecreated($self,$tablename,getlogger(__PACKAGE__));

            $created = 1;
        } else {
            my $fieldnamesfound = $self->getfieldnames($tablename);
            if (not setcontains($fieldnames,$fieldnamesfound,1)) {
                fieldnamesdiffer($self,$tablename,$fieldnames,$fieldnamesfound,getlogger(__PACKAGE__));
                return 0;
            }
        }

        if (not $created and $truncate) {
            $self->truncate_table($tablename);
        }
        return 1;
    } else {
        return 0;
    }

}

sub multithreading_supported {

    my $self = shift;
    return 0;

}

sub rowblock_transactional {

    my $self = shift;
    return $rowblock_transactional;

}

sub truncate_table {

    my $self = shift;
    my $tablename = shift;

    $self->db_do('DELETE FROM ' . $self->tableidentifier($tablename));
    tabletruncated($self,$tablename,getlogger(__PACKAGE__));

}

sub table_exists {

    my $self = shift;
    my $tablename = shift;

    if (defined $self->{dbh}) {
        my @tables = $self->_list_tables();
        return contains($tablename,\@tables);
    }

    return undef;

}

sub drop_table {

    my $self = shift;
    my $tablename = shift;

    if ($self->table_exists($tablename) > 0) {
        $self->db_do('DROP TABLE ' . $self->tableidentifier($tablename));
        delete $self->{dbh}->{csv_tables}->{$tablename};
        tabledropped($self,$tablename,getlogger(__PACKAGE__));
        return 1;
    }
    return 0;

}

sub db_begin {

    my $self = shift;
    if (defined $self->{dbh}) {
        dbdebug($self, "transactions not supported",getlogger(__PACKAGE__));
    }

}

sub db_commit {

    my $self = shift;
    if (defined $self->{dbh}) {
        dbdebug($self, "transactions not supported",getlogger(__PACKAGE__));
    }

}

sub db_rollback {

    my $self = shift;
    if (defined $self->{dbh}) {
        dbdebug($self, "transactions not supported",getlogger(__PACKAGE__));
    }

}

sub db_do_begin {

    my $self = shift;
    my $query = shift;


    $self->SUPER::db_do_begin($query,$rowblock_transactional,@_);

}

sub db_get_begin {

    my $self = shift;
    my $query = shift;


    $self->SUPER::db_get_begin($query,$rowblock_transactional,@_);

}

sub db_finish {

    my $self = shift;
    my $rollback = shift;

    $self->SUPER::db_finish($rowblock_transactional,$rollback);

}

sub xlsbin2csv {

    my ($inputfile,$outputfile,$worksheetname,$sourcecharset) = @_;

    return _convert_xlsbin2csv($inputfile,
                            $worksheetname,
                            $sourcecharset,
                            $outputfile,
                            'UTF-8',
                            $default_csv_config->{quote_char},
                            $default_csv_config->{escape_char},
                            $default_csv_config->{sep_char},
                            $default_csv_config->{eol});

}

sub _convert_xlsbin2csv {

    my ($SourceFilename,$worksheet,$SourceCharset,$DestFilename,$DestCharset,$quote_char,$escape_char,$sep_char,$eol) = @_;

    my $csvlinecount = 0;

    xls2csvinfo('start converting ' . $SourceFilename . ' (worksheet ' . $worksheet . ') to ' . $DestFilename . ' ...',getlogger(__PACKAGE__));

    $SourceCharset = 'UTF-8' unless $SourceCharset;
    $DestCharset = $SourceCharset unless $DestCharset;

    xls2csvinfo('reading ' . $SourceFilename . ' as ' . $SourceCharset,getlogger(__PACKAGE__));

    my $XLS = new IO::File;
    if (not $XLS->open('<' . $SourceFilename)) {
        fileerror('cannot open file ' . $SourceFilename . ': ' . $!,getlogger(__PACKAGE__));
        return 0;
    }

    my $Formatter = Spreadsheet::ParseExcel::FmtUnicode->new(Unicode_Map => $SourceCharset);

    my $parser   = Spreadsheet::ParseExcel->new();
    my $Book = $parser->parse($XLS,$Formatter);

    if ( !defined $Book ) {
        xls2csverror($parser->error(),getlogger(__PACKAGE__));
        $XLS->close();
        return 0;
    }

    my $Sheet;
    if ($worksheet) {

    $Sheet = $Book->Worksheet($worksheet);
    if (!defined $Sheet) {
            xls2csverror('invalid spreadsheet',getlogger(__PACKAGE__));
            return 0;
        }
        xls2csvinfo('converting the ' . $Sheet->{Name} . ' worksheet',getlogger(__PACKAGE__));
    } else {
    ($Sheet) = @{$Book->{Worksheet}};
    if ($Book->{SheetCount}>1) {

            xls2csvinfo('multiple worksheets found, converting ' . $Sheet->{Name},getlogger(__PACKAGE__));
    }
    }

    unlink $DestFilename;
    local *CSV;
    if (not open(CSV,'>' . $DestFilename)) {
        fileerror('cannot open file ' . $DestFilename . ': ' . $!,getlogger(__PACKAGE__));
        $XLS->close();
        return 0;
    }
    binmode CSV;

    my $Csv = Text::CSV_XS->new({
            'quote_char'  => $quote_char,
            'escape_char' => $escape_char,
            'sep_char'    => $sep_char,
            'binary'      => 1,
    });

    my $Recoder;
    if ($DestCharset) {
    $Recoder = Locale::Recode->new(from => $SourceCharset, to => $DestCharset);
    }

    for (my $Row = $Sheet->{MinRow}; defined $Sheet->{MaxRow} && $Row <= $Sheet->{MaxRow}; $Row++) {
    my @Row;
    for (my $Col = $Sheet->{MinCol}; defined $Sheet->{MaxCol} && $Col <= $Sheet->{MaxCol}; $Col++) {
        my $Cell = $Sheet->{Cells}[$Row][$Col];

        my $Value = "";
            if ($Cell) {
        $Value = $Cell->Value;
        if ($Value eq 'GENERAL') {
            # Sometimes numbers are read incorrectly as "GENERAL".
                    # In this case, the correct value should be in ->{Val}.
                    $Value = $Cell->{Val};
        }
        if ($DestCharset) {
            $Recoder->recode($Value);
        }
        }

            # We assume the line is blank if there is nothing in the first column.
            last if $Col == $Sheet->{MinCol} and !$Value;

            push(@Row,$Value);
    }

    next unless @Row;

    my $Status = $Csv->combine(@Row);

    if (!defined $Status) {
            xls2csvwarn('csv error: ' . $Csv->error_input(),getlogger(__PACKAGE__));
    }

    if (defined $Status) {
            print CSV $Csv->string();
            if ($Row < $Sheet->{MaxRow}) {
        print CSV $eol;
            }
            $csvlinecount++;
    }
    }

    close CSV;
    $XLS->close;

    xls2csvinfo($csvlinecount . ' line(s) converted',getlogger(__PACKAGE__));

    return $csvlinecount;

}

sub xlsxbin2csv {

    my ($inputfile,$outputfile,$worksheetname) = @_;

    return _convert_xlsxbin2csv($inputfile,
                            $worksheetname,
                            $outputfile,
                            'UTF-8',
                            $default_csv_config->{quote_char},
                            $default_csv_config->{escape_char},
                            $default_csv_config->{sep_char},
                            $default_csv_config->{eol});

}

sub _convert_xlsxbin2csv {
    my ($SourceFilename,$worksheet,$DestFilename,$DestCharset,$quote_char,$escape_char,$sep_char,$eol) = @_;

    my $csvlinecount = 0;

    xls2csvinfo('start converting ' . $SourceFilename . ' (worksheet ' . $worksheet . ') to ' . $DestFilename . ' ...',getlogger(__PACKAGE__));

    my $XLS = new IO::File;
    if (not $XLS->open('<' . $SourceFilename)) {
        fileerror('cannot open file ' . $SourceFilename . ': ' . $!,getlogger(__PACKAGE__));
        return 0;
    } else {
        $XLS->close();
    }

    my $reader   = Excel::Reader::XLSX->new();
    my $workbook = $reader->read_file($SourceFilename);

    my $SourceCharset = $workbook->{_reader}->encoding();
    $DestCharset = $SourceCharset unless $DestCharset;

    xls2csvinfo('reading ' . $SourceFilename . ' as ' . $SourceCharset,getlogger(__PACKAGE__));

    if ( !defined $workbook ) {
        xls2csverror($reader->error(),getlogger(__PACKAGE__));


        return 0;
    }

    my $sheet;
    if ($worksheet) {
        $sheet = $workbook->worksheet($worksheet);
        if (!defined $sheet) {
            xls2csverror('invalid spreadsheet',getlogger(__PACKAGE__));
            return 0;
        }
        xls2csvinfo('converting the ' . $sheet->name() . ' worksheet',getlogger(__PACKAGE__));
    } else {
        $sheet = $workbook->worksheet(0);
        if (@{$workbook->worksheets()} > 1) {
            xls2csvinfo('multiple worksheets found, converting ' . $sheet->name(),getlogger(__PACKAGE__));
        }
    }

    unlink $DestFilename;
    local *CSV;
    if (not open(CSV,'>' . $DestFilename)) {
        fileerror('cannot open file ' . $DestFilename . ': ' . $!,getlogger(__PACKAGE__));

        return 0;
    }
    binmode CSV;

    my $csv = Text::CSV_XS->new({
            'quote_char'  => $quote_char,
            'escape_char' => $escape_char,
            'sep_char'    => $sep_char,
            'binary'      => 1,
    });

    my $Recoder;
    if ($DestCharset) {
    $Recoder = Locale::Recode->new(from => $SourceCharset, to => $DestCharset);
    }

    while ( my $row = $sheet->next_row() ) {
        foreach my $value ($row->values()) {
            $Recoder->recode($value);
        }

        my $status = $csv->combine($row->values());
        if (!defined $status) {
            xls2csvwarn('csv error: ' . $csv->error_input(),getlogger(__PACKAGE__));
        }

        if (defined $status) {
            if ($row->row_number() > 0) {
                print CSV $eol;
            }
            print CSV $csv->string();
            $csvlinecount++;
        }
    }

    close CSV;

    xls2csvinfo($csvlinecount . ' line(s) converted',getlogger(__PACKAGE__));

    return $csvlinecount;

}

1;
