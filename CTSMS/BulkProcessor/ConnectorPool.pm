package CTSMS::BulkProcessor::ConnectorPool;
use strict;

## no critic

use CTSMS::BulkProcessor::Globals qw(

    $ctsms_databasename
    $ctsms_username
    $ctsms_password
    $ctsms_host
    $ctsms_port

    $ctsmsrestapi_uri
    $ctsmsrestapi_username
    $ctsmsrestapi_password
    $ctsmsrestapi_realm

);


use CTSMS::BulkProcessor::Logging qw(getlogger);
use CTSMS::BulkProcessor::LogError qw(dbclustererror dbclusterwarn);



use CTSMS::BulkProcessor::SqlConnectors::PostgreSQLDB;




use CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi;

use CTSMS::BulkProcessor::SqlProcessor qw(cleartableinfo);

use CTSMS::BulkProcessor::Utils qw(threadid);

use CTSMS::BulkProcessor::Array qw(
    filter
    mergearrays
    getroundrobinitem
    getrandomitem
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    get_ctsms_db
    ctsms_db_tableidentifier

    get_ctsms_restapi
    get_ctsms_restapi_last_error

    destroy_dbs
    get_connectorinstancename
    get_cluster_db

    ping_dbs
    ping
);

my $connectorinstancenameseparator = '_';



# thread connector pools:
my $ctsms_dbs = {};

my $ctsms_restapis = {};

sub get_ctsms_db {

    my ($instance_name,$reconnect) = @_;
    my $name = get_connectorinstancename($instance_name);
    if (!defined $ctsms_dbs->{$name}) {
        $ctsms_dbs->{$name} = CTSMS::BulkProcessor::SqlConnectors::PostgreSQLDB->new($instance_name);
        if (!defined $reconnect) {
            $reconnect = 1;
        }
    }
    if ($reconnect) {
        $ctsms_dbs->{$name}->db_connect($ctsms_databasename,$ctsms_username,$ctsms_password,$ctsms_host,$ctsms_port);
    }
    return $ctsms_dbs->{$name};

}

sub ctsms_db_tableidentifier {

    my ($get_target_db,$tablename) = @_;
    my $target_db = (ref $get_target_db eq 'CODE') ? &$get_target_db() : $get_target_db;
    return $target_db->getsafetablename(CTSMS::BulkProcessor::SqlConnectors::PostgreSQLDB::get_tableidentifier($tablename,$ctsms_databasename));

}

sub get_ctsms_restapi {

    my ($instance_name,$uri,$username,$password,$realm) = @_;
    my $name = get_connectorinstancename($instance_name);
    if (!defined $ctsms_restapis->{$name}) {
        $ctsms_restapis->{$name} = CTSMS::BulkProcessor::RestConnectors::CtsmsRestApi->new($instance_name);
        $ctsms_restapis->{$name}->setup($uri // $ctsmsrestapi_uri,$username // $ctsmsrestapi_username,$password // $ctsmsrestapi_password,$realm // $ctsmsrestapi_realm);
    }
    return $ctsms_restapis->{$name};

}

sub get_ctsms_restapi_last_error {
    my ($instance_name) = @_;
    my $name = get_connectorinstancename($instance_name);
    return $ctsms_restapis->{$name}->get_last_error() if $ctsms_restapis->{$name};
    return undef;
}

sub get_connectorinstancename {
    my ($name) = @_;
    my $instance_name = threadid();
    if (length($name) > 0) {
        $instance_name .= $connectorinstancenameseparator . $name;
    }
    return $instance_name;
}

sub ping_dbs {

    ping($ctsms_dbs);

}

sub ping {

    my $dbs = shift;
    my $this_tid = threadid();
    foreach my $instance_name (keys %$dbs) {
        my ($tid,$name) = split(quotemeta($connectorinstancenameseparator),$instance_name,2);
        next unless ($this_tid == $tid and defined $dbs->{$instance_name});
        my $result = 0;
        eval {
            $result = $dbs->{$instance_name}->ping();
        };
        undef $dbs->{$instance_name} unless $result;
    }

}

sub destroy_dbs {


    foreach my $name (keys %$ctsms_dbs) {
        cleartableinfo($ctsms_dbs->{$name});
        undef $ctsms_dbs->{$name};
        delete $ctsms_dbs->{$name};
    }




}

sub get_cluster_db { # oracle RAC and the like ...

    my ($cluster,$instance_name,$reconnect) = @_;

        my $node = undef;
        my $tid = threadid();
        if ((!defined $cluster->{scheduling_vars}) or ref $cluster->{scheduling_vars} ne 'HASH') {
            $cluster->{scheduling_vars} = {};
        }
        my $scheduling_vars = $cluster->{scheduling_vars};
        if ((!defined $scheduling_vars->{$tid}) or ref $scheduling_vars->{$tid} ne 'HASH') {
            $scheduling_vars->{$tid} = {};
        }
        $scheduling_vars = $scheduling_vars->{$tid};
        my $nodes;
        if (!defined $scheduling_vars->{nodes}) {
            $nodes = {};
            foreach my $node (@{$cluster->{nodes}}) {
                if (defined $node and ref $node eq 'HASH') {
                    if ($node->{active}) {
                        $nodes->{$node->{label}} = $node;
                    }
                } else {
                    dbclustererror($cluster->{name},'node configuration error',getlogger(__PACKAGE__));
                }
            }
            $scheduling_vars->{nodes} = $nodes;
        } else {
            $nodes = $scheduling_vars->{nodes};
        }
        my @active_nodes = @{$nodes}{sort keys(%$nodes)};
        if (defined $cluster->{scheduling_code} and ref $cluster->{scheduling_code} eq 'CODE') {
            my $cluster_instance_name;
            if (length($instance_name) > 0) {
                $cluster_instance_name = $cluster->{name} . $connectorinstancenameseparator . $instance_name;
            } else {
                $cluster_instance_name = $cluster->{name};
            }
            ($node,$scheduling_vars->{node_index}) = &{$cluster->{scheduling_code}}(\@active_nodes,$scheduling_vars->{node_index});
            if (defined $node) {
                my $get_db = $node->{get_db};
                if (defined $get_db and ref $get_db eq 'CODE') {
                    my $db = undef;
                    eval {
                        $db = &{$get_db}($cluster_instance_name,$reconnect,$cluster);
                    };
                    if ($@) {
                        dbclusterwarn($cluster->{name},'node ' . $node->{label} . ' inactive',getlogger(__PACKAGE__));
                        delete $nodes->{$node->{label}};
                        return get_cluster_db($cluster,$instance_name,$reconnect);
                    } else {

                        return $db;
                    }
                } else {
                    dbclustererror($cluster->{name},'node ' . $node->{label} . ' configuration error',getlogger(__PACKAGE__));
                    delete $nodes->{$node->{label}};
                    return get_cluster_db($cluster,$instance_name,$reconnect);
                }
            }
        } else {
            dbclustererror($cluster->{name},'scheduling configuration error',getlogger(__PACKAGE__));
            return undef;
        }


    dbclustererror($cluster->{name},'cannot switch to next active node',getlogger(__PACKAGE__));
    return undef;

}

1;
