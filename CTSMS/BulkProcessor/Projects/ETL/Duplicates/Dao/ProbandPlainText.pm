package CTSMS::BulkProcessor::Projects::ETL::Duplicates::Dao::ProbandPlainText;
use strict;

## no critic

use CTSMS::BulkProcessor::Projects::ETL::Duplicates::ProjectConnectorPool qw(
    get_sqlite_db
    destroy_all_dbs
);

use CTSMS::BulkProcessor::SqlProcessor qw(
    registertableinfo
    create_targettable
    checktableinfo
    copy_row

    insert_stmt

    process_table
);
use CTSMS::BulkProcessor::SqlRecord qw();



require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::SqlRecord);
our @EXPORT_OK = qw(
    create_table
    gettablename
    check_table
    getinsertstatement

    process_records

    countby_lastnamefirstnamedateofbirth
    findby_lastnamefirstnamedateofbirthprobandid

);



my $tablename = 'proband_plain_text';
my $get_db = \&get_sqlite_db;



my $expected_fieldnames = [
    'first_name',
    'last_name',
    'date_of_birth',
    'proband_id',
    'version',
    'category',
    'comment',

];

# table creation:
my $primarykey_fieldnames = [ 'first_name', 'last_name', 'date_of_birth', 'proband_id' ];
my $indexes = { $tablename . '_proband_id' => [ 'proband_id' ]};



sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::SqlRecord->new($class,$get_db,
                           $tablename,$expected_fieldnames,$indexes);

    copy_row($self,shift,$expected_fieldnames);

    return $self;

}

sub create_table {

    my ($truncate) = @_;

    my $db = &$get_db();

    registertableinfo($db,__PACKAGE__,$tablename,$expected_fieldnames,$indexes,$primarykey_fieldnames);
    return create_targettable($db,__PACKAGE__,$db,__PACKAGE__,$tablename,$truncate,0,undef);

}


















sub findby_lastnamefirstnamedateofbirthprobandid {

    my ($last_name,$first_name,$date_of_birth,$proband_id,$load_recursive) = @_;

    check_table();
    my $db = &$get_db();

    my $table = $db->tableidentifier($tablename);

    my $stmt = 'SELECT * FROM ' . $table . ' WHERE 1=1';
    my @params = ();
    if (defined $last_name) {
        $stmt .= ' AND ' . $db->columnidentifier('last_name') . ' = ?';
        push(@params,$last_name);
    }
    if (defined $first_name) {
        $stmt .= ' AND ' . $db->columnidentifier('first_name') . ' = ?';
        push(@params,$first_name);
    }
    if (defined $date_of_birth) {
        $stmt .= ' AND ' . $db->columnidentifier('date_of_birth') . ' = ?';
        push(@params,$date_of_birth);
    }
    if (defined $proband_id) {
        $stmt .= ' AND ' . $db->columnidentifier('proband_id') . ' = ?';
        push(@params,$proband_id);
    }

    my $rows = $db->db_get_all_arrayref($stmt,@params);
    return buildrecords_fromrows($rows,$load_recursive);

}

sub countby_lastnamefirstnamedateofbirth {

    my ($last_name,$first_name,$date_of_birth) = @_;

    check_table();
    my $db = &$get_db();
    my $table = $db->tableidentifier($tablename);

    my $stmt = 'SELECT COUNT(*) FROM ' . $table . ' WHERE 1=1';
    my @params = ();
    if (defined $last_name) {
        $stmt .= ' AND ' . $db->columnidentifier('last_name') . ' = ?';
        push(@params,$last_name);
    }
    if (defined $first_name) {
        $stmt .= ' AND ' . $db->columnidentifier('first_name') . ' = ?';
        push(@params,$first_name);
    }
    if (defined $date_of_birth) {
        $stmt .= ' AND ' . $db->columnidentifier('date_of_birth') . ' = ?';
        push(@params,$date_of_birth);
    }

    return $db->db_get_value($stmt,@params);

}

sub buildrecords_fromrows {

    my ($rows,$load_recursive) = @_;

    my $item;

    if (defined $rows and ref $rows eq 'ARRAY') {
        my @items = ();
        foreach my $row (@$rows) {
            $item = __PACKAGE__->new($row);

            # transformations go here ...
            transformitem($item,$load_recursive);

            push @items,$item;
        }
        return \@items;
    } elsif (defined $rows and ref $rows eq 'HASH') {
        $item = __PACKAGE__->new($rows);
        transformitem($item,$load_recursive);
        return $item;
    }
    return undef;

}

sub transformitem {
    my ($item,$load_recursive) = @_;

}

sub process_records {

    my %params = @_;
    my ($process_code,
        $static_context,
        $init_process_context_code,
        $uninit_process_context_code,
        $multithreading,
        $numofthreads,
        $load_recursive) = @params{qw/
            process_code
            static_context
            init_process_context_code
            uninit_process_context_code
            multithreading
            numofthreads
            load_recursive
        /};

    check_table();
    my $db = &$get_db();
    my $table = $db->tableidentifier($tablename);

    return process_table(
        get_db                      => $get_db,
        class                       => __PACKAGE__,
        process_code                => sub {
                my ($context,$rowblock,$row_offset) = @_;
                return &$process_code($context,buildrecords_fromrows($rowblock,$load_recursive),$row_offset);
            },
        static_context              => $static_context,
        init_process_context_code   => $init_process_context_code,
        uninit_process_context_code => $uninit_process_context_code,
        destroy_reader_dbs_code     => \&destroy_all_dbs,
        multithreading              => $multithreading,
        tableprocessing_threads     => $numofthreads,
        'select'          => $db->paginate_sort_query('SELECT * FROM ' . $table,undef,undef,[{
                                            column => 'proband_id',
                                            numeric => 1,
                                            dir => 1,
                                        }]),
    );
}

sub getinsertstatement {

    my ($insert_ignore) = @_;
    check_table();
    return insert_stmt($get_db,__PACKAGE__,$insert_ignore);

}



sub gettablename {

    return $tablename;

}

sub check_table {

    return checktableinfo($get_db,
                   __PACKAGE__,$tablename,
                   $expected_fieldnames,
                   $indexes);

}

1;
