package CTSMS::BulkProcessor::Projects::ETL::Remoc::Dao::DialysisSubstitutionVolume;
use strict;

## no critic

use CTSMS::BulkProcessor::Projects::ETL::ProjectConnectorPool qw(
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

#use CTSMS::BulkProcessor::Array qw(contains);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::SqlRecord);
our @EXPORT_OK = qw(
    create_table
    gettablename
    check_table
    getinsertstatement

    countby_filename
    
    process_records

    $expected_fieldnames_count
);
#getupsertstatement

my $tablename = 'dialysis_substitution_volume';
my $get_db = \&get_sqlite_db;
#my $get_tablename = \&sqlite_db_tableidentifier;


my $expected_fieldnames = [
    'filename',
    'row_id',
    'Patientname',
    'DateOfBirth',
    'TreatmentDate',
    'TreatmentID',
    'EffectiveDiaTime',
    'AvgBloodFlow',
    'AvgDiaFlow',
    'TotalUFVol',
    'HDFSubstVol',
    'KtVTarget',
    'KtVMeasured',
];
our $expected_fieldnames_count = scalar @$expected_fieldnames;

# table creation:
my $primarykey_fieldnames = [ 'TreatmentID' ]; #'filename'
my $indexes = { $tablename . '_TreatmentDate' => [ 'TreatmentDate(10)' ]};
#my $fixtable_statements = [];


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

sub countby_filename {

    my ($filename) = @_;

    check_table();
    my $db = &$get_db();
    my $table = $db->tableidentifier($tablename);

    my $stmt = 'SELECT COUNT(*) FROM ' . $table . ' WHERE 1=1';
    my @params = ();
    if (defined $filename and length($filename) > 0) {
        $stmt .= ' AND ' . $db->columnidentifier('filename') . ' = ?';
        push(@params,$filename);
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
        $sort,
        $load_recursive) = @params{qw/
            process_code
            static_context
            init_process_context_code
            uninit_process_context_code
            multithreading
            numofthreads
            sort
            load_recursive
        /};

    check_table();
    my $db = &$get_db();

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
        ($sort ? ('select'          => $db->paginate_sort_query('SELECT * FROM ' . $db->tableidentifier($tablename),undef,undef,[{
                                            column => 'filename',
                                            numeric => 0,
                                            dir => 1,
                                        },{
                                            column => 'row_id',
                                            numeric => 1,
                                            dir => 1,
                                        }])) : ()),
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
