package CTSMS::BulkProcessor::Service::TestService;
use strict;

## no critic

use CTSMS::BulkProcessor::Logging qw(getlogger servicedebug);

use CTSMS::BulkProcessor::Service qw();

#use test::csv_table; # qw(test_table_bycolumn1);
#use test::mysql_table;
#use test::oracle_table;
#use test::postgres_table;
#use test::sqlite_table;
#use test::sqlserver_table;

use CTSMS::BulkProcessor::Utils; # qw(create_guid);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::Service);
our @EXPORT_OK = qw(
    roundtrip
    sleep_seconds
    noop
    exception
);

#my $logger = getlogger(__PACKAGE__);

my $functions = {
    create_uuid => \&CTSMS::BulkProcessor::Utils::create_guid,
    roundtrip => \&roundtrip,
    noop => \&noop,
    exception => \&exception,
    sleeproundtrip => \&sleep_roundtrip,
    #test_csv_table_bycolumn1 => \&test::csv_table::test_table_bycolumn1,
    #test_mysql_table_bycolumn1 => \&test::mysql_table::test_table_bycolumn1,
    #test_oracle_table_bycolumn1 => \&test::oracle_table::test_table_bycolumn1,
    #test_postgres_table_bycolumn1 => \&test::postgres_table::test_table_bycolumn1,
    #test_sqlite_table_bycolumn1 => \&test::sqlite_table::test_table_bycolumn1
};

sub new {

    my $class = shift;
    my $self = CTSMS::BulkProcessor::Service->new($class,$functions,@_);
    return $self;

}

sub roundtrip {
    return @_;
    #my (@in) = @_;
    ##my $error = 1/0;
    #return @in;
}

sub sleep_roundtrip {
    sleep(shift);
    return @_;
}

sub noop {

}

sub exception {
    return 1/0;
}

#sub _on_start {
#    my $self = shift;
#    print "_on_start\n";
#}

#sub _on_complete {
#    my $self = shift;
#    print "_on_complete\n";
#}

#sub _on_fail {
#    my $self = shift;
#    print "_on_fail\n";
#}

1;
