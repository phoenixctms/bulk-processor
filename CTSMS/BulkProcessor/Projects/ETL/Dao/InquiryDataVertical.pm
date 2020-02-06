package CTSMS::BulkProcessor::Projects::ETL::Dao::InquiryDataVertical;
use strict;

## no critic

use CTSMS::BulkProcessor::Projects::ETL::InquiryConnectorPool qw(
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
);





my $tablename = 'inquiry_data_vertical';
my $get_db = \&get_sqlite_db;


my $expected_fieldnames;
_set_expected_fieldnames();

sub _set_expected_fieldnames {
    my ($option_col_count) = @_;
    $option_col_count //= 0;
    my @fieldnames = (
        'proband_id',











        'inquiry_category',
        'inquiry_id',
        'inquiry_position',
        'inquiry_title',
        'inquiry_external_id',
        'input_field_name',
        'input_field_title',
        'input_field_externals_id',
        'input_field_id',
        'input_field_type',
        'inquiry_optional',


        'horizontal_colnames',
        'value_version',
        'value_user',
        'value_timestamp',
        'value',
        'value_boolean',
        'value_text',
        'value_integer',
        'value_decimal',
        'value_date',
    );
    foreach my $i (1..$option_col_count) {
        push(@fieldnames,'value_option_' . $i);
    }
    $expected_fieldnames = \@fieldnames;
}


my $primarykey_fieldnames = [ 'proband_id','inquiry_category','inquiry_position','value_version' ];
my $indexes = {
    $tablename . '_inquiry_category_position' => [ 'inquiry_category(32)','inquiry_position(32)' ],

};



sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::SqlRecord->new($class,$get_db,
                           $tablename,$expected_fieldnames,$indexes);

    copy_row($self,shift,$expected_fieldnames);

    return $self;

}

sub create_table {

    my ($truncate,$option_col_count) = @_;

    my $db = &$get_db();

    _set_expected_fieldnames($option_col_count);

    registertableinfo($db,__PACKAGE__,$tablename,$expected_fieldnames,$indexes,$primarykey_fieldnames);
    return create_targettable($db,__PACKAGE__,$db,__PACKAGE__,$tablename,$truncate,0,undef);

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

    $static_context //= {};
    $static_context->{is_utf8} = 0;

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
        'select'                    => $db->paginate_sort_query('SELECT * FROM ' . $table,undef,undef,[{
                                            column => 'proband_id',

                                            dir => 1,
                                        }]),
        'selectcount'               => 'SELECT COUNT(*) FROM ' . $table,
    );
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

sub gettablefieldnames {

    my $db = &$get_db();
    if ($db->table_exists($tablename)) {
        $expected_fieldnames = $db->getfieldnames($tablename);
        return $expected_fieldnames;
    }
    return undef;
}

1;
