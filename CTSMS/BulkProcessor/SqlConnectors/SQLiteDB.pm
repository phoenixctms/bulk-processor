package CTSMS::BulkProcessor::SqlConnectors::SQLiteDB;
use strict;

## no critic

use CTSMS::BulkProcessor::Globals qw(
    $local_db_path
    $LongReadLen_limit
    $cpucount);
use CTSMS::BulkProcessor::Logging qw(
    getlogger
    dbinfo
    dbdebug
    texttablecreated
    temptablecreated
    indexcreated
    tabletruncated
    tabledropped);
use CTSMS::BulkProcessor::LogError qw(
    dberror
    fieldnamesdiffer
    dbwarn
    fileerror
    filewarn);

use DBI 1.608 qw(:sql_types);
use DBD::SQLite 1.29;
use CTSMS::BulkProcessor::Array qw(arrayeq contains setcontains);

use File::Copy qw();

use CTSMS::BulkProcessor::Utils qw(
    tempfilename
    timestampdigits
    timestamp);

use CTSMS::BulkProcessor::SqlConnectors::SQLiteVarianceAggregate;

use CTSMS::BulkProcessor::SqlConnector;

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::SqlConnector);
our @EXPORT_OK = qw($staticdbfilemode
                    $timestampdbfilemode
                    $temporarydbfilemode
                    $memorydbfilemode
                    $privatedbfilemode
                    get_tableidentifier
                    cleanupdbfiles
                    $mimetype
                    $dbextension);

our $staticdbfilemode = 0; #remains on disk after shutdown
our $timestampdbfilemode = 1; #remains on disk after shutdown
our $temporarydbfilemode = 2; #cleaned on shutdown
our $memorydbfilemode = 3; #never on disk
our $privatedbfilemode = 4; #somewhere on disk, cleaned on shutdown

my $cachesize = 32768; #16384; #40000;
my $pagesize = 4096; #2048; #8192;
my $busytimeout = 90000; #20000; #msecs

our $dbextension = '.db';
my $journalpostfix = '-journal';

my $texttable_encoding = 'UTF-8'; # sqlite returns whats inserted...

$DBD::SQLite::COLLATION{no_accents} = sub {
    my ( $a, $b ) = map lc, @_;
    tr[����������������������������]
      [aaaaaacdeeeeiiiinoooooouuuuy] for $a, $b;
    $a cmp $b;
  };

my $LongReadLen = $LongReadLen_limit; #bytes
my $LongTruncOk = 0;

our $mimetype = 'application/x-sqlite3';

my $rowblock_transactional = 0;

#SQLite transactions are always serializable.

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::SqlConnector->new(@_);

    $self->{filemode} = undef;
    $self->{dbfilename} = undef;

    $self->{drh} = DBI->install_driver('SQLite');

    bless($self,$class);

    dbdebug($self,__PACKAGE__ . ' connector created',getlogger(__PACKAGE__));

    return $self;

}

sub _connectidentifier {

    my $self = shift;
    return _get_connectidentifier($self->{filemode},$self->{dbfilename});

}

sub copydbfile {

    my $self = shift;
    my $target = shift;
    $self->db_disconnect();
    if (File::Copy::copy($self->{dbfilename},$target)) {
      dbinfo($self,"$self->{dbfilename} copied to $target",getlogger(__PACKAGE__));
    } else {
      dberror($self,"copy from $self->{dbfilename} to $target failed: $!",getlogger(__PACKAGE__));
    }

}

sub tableidentifier {

    my $self = shift;
    my $tablename = shift;
    return $tablename;

}

sub _columnidentifier {

    my $self = shift;
    my $columnname = shift;

    return $columnname;

}

sub get_tableidentifier {

    my ($tablename,$filemode, $filename) = @_;
    my $connectionidentifier = _get_connectidentifier($filemode, $filename);
    if (defined $connectionidentifier) {
        return $connectionidentifier . '.' . $tablename;
    } else {
        return $tablename;
    }

}

sub getsafetablename {

    my $self = shift;
    my $tableidentifier = shift;

    return $self->SUPER::getsafetablename($tableidentifier);

}

sub _force_numeric_column {
    my $self = shift;
    my $column = shift;
    return 'CAST(' . $column . ' AS REAL)';
}

sub getdatabases {

    my $self = shift;

    my $rdbextension = quotemeta($dbextension);
    my $ucrdbextension = quotemeta(uc($dbextension));

    local *DBDIR;
    if (not opendir(DBDIR, $local_db_path)) {
        fileerror('cannot opendir ' . $local_db_path . ': ' . $!,getlogger(__PACKAGE__));
        return [];
    }
    my @files = grep { /($rdbextension|$ucrdbextension)$/ && -f $local_db_path . $_ } readdir(DBDIR);
    closedir DBDIR;
    my @databases = ();
    foreach my $file (@files) {
        my $databasename = $file;
        $databasename =~ s/($rdbextension|$ucrdbextension)$//g;
        push @databases,$databasename;
    }
    return \@databases;

}

sub _createdatabase {

    my $self = shift;
    my ($filename) = @_;
    my $dbfilename = _getdbfilename($self->{filemode},$filename);

    if ($self->_is_filebased() and not -e $dbfilename) {
        my $dbh = DBI->connect(
            'dbi:SQLite:dbname=' . $dbfilename, '', '',
            {
                PrintError      => 0,
                RaiseError      => 0,
            }
        ) or dberror($self,'error connecting: ' . $self->{drh}->errstr(),getlogger(__PACKAGE__));
        $dbh->disconnect() or dbwarn($self,'error disconnecting: ' . $dbh->errstr(),getlogger(__PACKAGE__));
        dbinfo($self,'database \'' . $dbfilename . '\' created',getlogger(__PACKAGE__));
    }

    return $dbfilename;

}

sub db_connect {

    my $self = shift;
    my ($filemode, $filename) = @_;

    $self->SUPER::db_connect($filemode, $filename);

    $self->{filemode} = $filemode;
    $self->{dbfilename} = $self->_createdatabase($filename);

    my $dbh = DBI->connect(
        'dbi:SQLite:dbname=' . $self->{dbfilename}, '', '',
        {
            PrintError      => 0,
            RaiseError      => 0,
        }
    ) or dberror($self,'error connecting: ' . $self->{drh}->errstr(),getlogger(__PACKAGE__));

    $dbh->{InactiveDestroy} = 1;

    $dbh->{LongReadLen} = $LongReadLen;
    $dbh->{LongTruncOk} = $LongTruncOk;

    $dbh->{AutoCommit} = 1;

    $dbh->sqlite_create_function('now', 0, \&timestamp );
    $dbh->sqlite_create_function('concat', 2, \&_concat );

    $dbh->sqlite_create_aggregate( 'variance', 1, 'SQLiteVarianceAggregate' );

    $dbh->sqlite_busy_timeout($busytimeout);

    $self->{dbh} = $dbh;

    $self->db_do('PRAGMA foreign_keys = OFF');

    $self->db_do('PRAGMA synchronous = OFF');
    $self->db_do('PRAGMA page_size = ' . $pagesize);
    $self->db_do('PRAGMA cache_size = ' . $cachesize);

    $self->db_do('PRAGMA encoding = "' . $texttable_encoding . '"'); # only new databases!
    #PRAGMA locking_mode = NORMAL ... by default
    
    if ($cpucount) {
        $self->db_do('PRAGMA threads = ' . $cpucount);
    }
    if ($local_db_path and ($filemode == $staticdbfilemode or $filemode == $timestampdbfilemode)) {
        $self->db_do("PRAGMA temp_store_directory = '$local_db_path'");
    }

    dbinfo($self,'connected',getlogger(__PACKAGE__));

}

sub _concat {

    return $_[0] . $_[1];

}

sub vacuum {

    my $self = shift;
    my $tablename = shift;

    $self->db_finish();

    if (defined $self->{dbh}) {
        if ($self->{filemode} == $staticdbfilemode or $self->{filemode} == $timestampdbfilemode) {
            $self->db_do('VACUUM');
            dbinfo($self,'VACUUMed',getlogger(__PACKAGE__));
        }
    }

}

sub _db_disconnect {

    my $self = shift;

    $self->SUPER::_db_disconnect();

    if ($self->{filemode} == $temporarydbfilemode and defined $self->{dbfilename} and -e $self->{dbfilename}) {
        if ((unlink $self->{dbfilename}) > 0) {
            dbinfo($self,'db file removed',getlogger(__PACKAGE__));
        } else {
            dbwarn($self,'cannot remove db file: ' . $!,getlogger(__PACKAGE__));
        }
        my $journalfilename = $self->{dbfilename} . '-journal';
        if (-e $journalfilename) {
            if ((unlink $journalfilename) > 0) {
                dbinfo($self,'journal file removed',getlogger(__PACKAGE__));
            } else {
                dbwarn($self,'cannot remove journal file: ' . $!,getlogger(__PACKAGE__));
            }
        }
    }

}


sub cleanupdbfiles {

    my (@remainingdbfilenames) = @_;
    my $rdbextension = quotemeta($dbextension);
    my $ucrdbextension = quotemeta(uc($dbextension));
    my $rjournalpostfix = quotemeta($journalpostfix);
    local *DBDIR;
    if (not opendir(DBDIR, $local_db_path)) {
        fileerror('cannot opendir ' . $local_db_path . ': ' . $!,getlogger(__PACKAGE__));
        return;
    }
    my @files = grep { /($rdbextension|$ucrdbextension)($rjournalpostfix)?$/ && -f $local_db_path . $_ } readdir(DBDIR);
    closedir DBDIR;
    my @remainingdbfiles = ();
    foreach my $filename (@remainingdbfilenames) {
        push @remainingdbfiles,$local_db_path . $filename . $dbextension;
        push @remainingdbfiles,$local_db_path . $filename . $dbextension . $journalpostfix;
        push @remainingdbfiles,$local_db_path . uc($filename . $dbextension) . $journalpostfix;
    }
    foreach my $file (@files) {
        my $filepath = $local_db_path . $file;
        if (not contains($filepath,\@remainingdbfiles)) {
            if ((unlink $filepath) == 0) {
                filewarn('cannot remove ' . $filepath . ': ' . $!,getlogger(__PACKAGE__));
            }
        }
    }

}

sub getfieldnames {

    my $self = shift;
    my $tablename = shift;

    my @fieldnames = ();
    foreach my $field (@{$self->db_get_all_arrayref('PRAGMA table_info(' . $tablename . ')')}) {
        push(@fieldnames,$field->{name});
    }
    return \@fieldnames;

}

sub getprimarykeycols {

    my $self = shift;
    my $tablename = shift;

    my @keycols = ();
    foreach my $field (@{$self->db_get_all_arrayref('PRAGMA table_info(' . $tablename . ')')}) {
        if ($field->{'pk'}) {
            push(@keycols,$field->{name});
        }
    }

    return \@keycols;

}

sub create_primarykey {

    my $self = shift;
    my ($tablename,$keycols,$fieldnames) = @_;

    #not supported by sqlite

    return 0;
}

sub create_indexes {
    my $self = shift;
    my ($tablename,$indexes,$keycols) = @_;

    my $index_count = 0;
    if (length($tablename) > 0) {

        if (defined $indexes and ref $indexes eq 'HASH' and scalar keys %$indexes > 0) {
            foreach my $indexname (keys %$indexes) {
                my $indexcols = $self->_extract_indexcols($indexes->{$indexname});
                if (not arrayeq($indexcols,$keycols,1)) {
                    $self->db_do('CREATE INDEX ' . $indexname . ' ON ' . $self->tableidentifier($tablename) . ' (' . join(', ',map { local $_ = $_; $_ = $self->columnidentifier($_); $_; } @$indexcols) . ')');
                    indexcreated($self,$tablename,$indexname,getlogger(__PACKAGE__));
                }
            }
        }

    }

    return $index_count;
}

sub create_temptable {

    my $self = shift;
    my $select_stmt = shift;
    my $indexes = shift;

    my $index_tablename = $self->_gettemptablename();
    my $temp_tablename = $self->tableidentifier($index_tablename);

    $self->db_do('CREATE TEMPORARY TABLE ' . $temp_tablename . ' AS ' . $select_stmt);

    temptablecreated($self,$index_tablename,getlogger(__PACKAGE__));

    if (defined $indexes and ref $indexes eq 'HASH' and scalar keys %$indexes > 0) {
        foreach my $indexname (keys %$indexes) {
            my $indexcols = $self->_extract_indexcols($indexes->{$indexname});
            $indexname = lc($index_tablename) . '_' . $indexname;
            $self->db_do('CREATE INDEX ' . $indexname . ' ON ' . $temp_tablename . ' (' . join(', ',map { local $_ = $_; $_ = $self->columnidentifier($_); $_; } @$indexcols) . ')');
            indexcreated($self,$index_tablename,$indexname,getlogger(__PACKAGE__));
        }
    }

    return $temp_tablename;

}

sub create_texttable {

    my $self = shift;
    my ($tablename,$fieldnames,$keycols,$indexes,$truncate,$defer_indexes) = @_;

    if (length($tablename) > 0 and defined $fieldnames and ref $fieldnames eq 'ARRAY') {
        my $created = 0;
        if ($self->table_exists($tablename) == 0) {
            my $statement = 'CREATE TABLE ' . $self->tableidentifier($tablename) . ' (';
            $statement .= join(' TEXT, ',map { local $_ = $_; $_ = $self->columnidentifier($_); $_; } @$fieldnames) . ' TEXT'; # sqlite_unicode off... outcoming strings not marked utf8
            if (defined $keycols and ref $keycols eq 'ARRAY' and scalar @$keycols > 0 and setcontains($keycols,$fieldnames,1)) {
                $statement .= ', PRIMARY KEY (' . join(', ',map { local $_ = $_; $_ = $self->columnidentifier($_); $_; } @$keycols) . ')';
            }
            $statement .= ')';

            $self->db_do($statement);
            texttablecreated($self,$tablename,getlogger(__PACKAGE__));

            if (not $defer_indexes and defined $indexes and ref $indexes eq 'HASH' and scalar keys %$indexes > 0) {
                foreach my $indexname (keys %$indexes) {
                    my $indexcols = $self->_extract_indexcols($indexes->{$indexname});
                    if (not arrayeq($indexcols,$keycols,1)) {
                        $self->db_do('CREATE INDEX ' . $indexname . ' ON ' . $self->tableidentifier($tablename) . ' (' . join(', ',map { local $_ = $_; $_ = $self->columnidentifier($_); $_; } @$indexcols) . ')');
                        indexcreated($self,$tablename,$indexname,getlogger(__PACKAGE__));
                    }
                }
            }
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
    return 1;

}

sub rowblock_transactional {

    my $self = shift;
    return $rowblock_transactional;

}

sub insert_ignore_phrase {

    my $self = shift;

    return 'OR IGNORE';

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

    return $self->db_get_value('SELECT COUNT(*) FROM sqlite_master WHERE type = \'table\' AND name = ?',$tablename);

}

sub drop_table {

    my $self = shift;
    my $tablename = shift;

    if ($self->table_exists($tablename) > 0) {
        $self->db_do('DROP TABLE ' . $self->tableidentifier($tablename));
        tabledropped($self,$tablename,getlogger(__PACKAGE__));
        return 1;
    }
    return 0;

}

sub _get_connectidentifier {

    my ($filemode, $filename) = @_;
    if ($filemode == $staticdbfilemode and defined $filename) {
        return $filename;
    } elsif ($filemode == $timestampdbfilemode) {
        return $filename;
    } elsif ($filemode == $temporarydbfilemode) {
        return $filename;
    } elsif ($filemode == $memorydbfilemode) {
        return '<InMemoryDB>';
    } elsif ($filemode == $privatedbfilemode) {
        return '<PrivateDB>';
    } else {
        return undef;
    }

}

sub _getdbfilename {

    my ($filemode,$filename) = @_;
    if ($filemode == $staticdbfilemode and defined $filename) {
        return $local_db_path . $filename . $dbextension;
    } elsif ($filemode == $timestampdbfilemode) {
        return $local_db_path . timestampdigits() . $dbextension;
    } elsif ($filemode == $temporarydbfilemode) {
        return tempfilename('XXXX',$local_db_path,$dbextension);
    } elsif ($filemode == $memorydbfilemode) {
        return ':memory:';
    } elsif ($filemode == $privatedbfilemode) {
        return '';
    }

}

sub _is_filebased {

    my $self = shift;
    if ($self->{filemode} == $staticdbfilemode or $self->{filemode} == $timestampdbfilemode or $self->{filemode} == $temporarydbfilemode) {
        return 1;
    } else {
        return 0;
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

1;
