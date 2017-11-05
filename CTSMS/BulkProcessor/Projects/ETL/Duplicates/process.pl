use strict;

## no critic

use File::Basename;
use Cwd;
use lib Cwd::abs_path(File::Basename::dirname(__FILE__) . '/../../../../../');

use Getopt::Long qw(GetOptions);
use Fcntl qw(LOCK_EX LOCK_NB);

use CTSMS::BulkProcessor::Globals qw();
use CTSMS::BulkProcessor::Projects::ETL::Duplicates::Settings qw(
    $output_path
    $skip_errors
    $defaultsettings
    $defaultconfig
    $force
    $dry
    check_dry
);
use CTSMS::BulkProcessor::Logging qw(
    init_log
    getlogger
    $attachmentlogfile
    scriptinfo
    cleanuplogfiles
    $currentlogfile
);
use CTSMS::BulkProcessor::LogError qw (
    completion
    done
    scriptwarn
    scripterror
    filewarn
    fileerror
);
use CTSMS::BulkProcessor::LoadConfig qw(
    load_config
    $SIMPLE_CONFIG_TYPE
    $YAML_CONFIG_TYPE
    $ANY_CONFIG_TYPE
);
use CTSMS::BulkProcessor::Array qw(removeduplicates);
use CTSMS::BulkProcessor::Utils qw(getscriptpath prompt cleanupdir);
use CTSMS::BulkProcessor::Mail qw(
    cleanupmsgfiles
);
#use CTSMS::BulkProcessor::SqlConnectors::CSVDB qw(cleanupcvsdirs);
use CTSMS::BulkProcessor::SqlConnectors::SQLiteDB qw(cleanupdbfiles);

use CTSMS::BulkProcessor::Projects::ETL::Duplicates::ProjectConnectorPool qw(destroy_all_dbs);
#use CTSMS::BulkProcessor::ConnectorPool qw(destroy_dbs);

use CTSMS::BulkProcessor::Projects::ETL::Duplicates::Process qw(
    import_proband
    create_duplicate
    update_proband
);


scripterror(getscriptpath() . ' already running',getlogger(getscriptpath())) unless flock DATA, LOCK_EX | LOCK_NB; # not tested on windows yet

my @TASK_OPTS = ();

my $tasks = [];

my $cleanup_task_opt = 'cleanup';
push(@TASK_OPTS,$cleanup_task_opt);

my $cleanup_all_task_opt = 'cleanup_all';
push(@TASK_OPTS,$cleanup_all_task_opt);

my $import_proband_task_opt = 'import_proband';
push(@TASK_OPTS,$import_proband_task_opt);

my $create_duplicate_task_opt = 'create_duplicate';
push(@TASK_OPTS,$create_duplicate_task_opt);

my $update_proband_task_opt = 'update_proband';
push(@TASK_OPTS,$update_proband_task_opt);

if (init()) {
    main();
    exit(0);
} else {
    exit(1);
}

sub init {

    my $configfile = $defaultconfig;
    my $settingsfile = $defaultsettings;
    #print STDERR (join("|",@ARGV),"\n");
    return 0 unless GetOptions(
        "config=s" => \$configfile,
        "settings=s" => \$settingsfile,
        "task=s" => $tasks,
        "skip-errors" => \$skip_errors,
        "force" => \$force,
        "dry" => \$dry,
    ); # or scripterror('error in command line arguments',getlogger(getscriptpath()));

    #$tasks = removeduplicates($tasks,1); #allowe cleanup twice

    my $result = load_config($configfile);
    init_log();
    $result &= load_config($settingsfile,\&CTSMS::BulkProcessor::Projects::ETL::Duplicates::Settings::update_settings,$YAML_CONFIG_TYPE);
    #$result &= load_config($some_yml,\&update_something,$YAML_CONFIG_TYPE);
    return $result;

}

sub main() {

    my @messages = ( 'Detect and mark subject duplicates:' );
    my @attachmentfiles = ();
    my $result = 1;
    my $completion = 0;

    if (defined $tasks and 'ARRAY' eq ref $tasks and (scalar @$tasks) > 0) {
        #scriptinfo('skip-errors: processing won\'t stop upon errors',getlogger(__PACKAGE__)) if $skip_errors;
        foreach my $task (@$tasks) {

            if (lc($cleanup_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages,0) if taskinfo($cleanup_task_opt,$result);

            } elsif (lc($cleanup_all_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages,1) if taskinfo($cleanup_all_task_opt,$result);

            } elsif (lc($import_proband_task_opt) eq lc($task)) {
                $result &= import_proband_task(\@messages) if taskinfo($import_proband_task_opt,$result);

            } elsif (lc($create_duplicate_task_opt) eq lc($task)) {
                $result &= create_duplicate_task(\@messages) if taskinfo($create_duplicate_task_opt,$result);

            } elsif (lc($update_proband_task_opt) eq lc($task)) {
                if (taskinfo($update_proband_task_opt,$result)) {
                    next unless check_dry();
                    $result &= update_proband_task(\@messages,\$completion);
                }

            } else {
                $result = 0;
                scripterror("unknow task option '" . $task . "', must be one of " . join(', ',@TASK_OPTS),getlogger(getscriptpath()));
                last;
            }
        }
        destroy_all_dbs();
    } else {
        $result = 0;
        scripterror('at least one task option is required. supported tasks: ' . join(', ',@TASK_OPTS),getlogger(getscriptpath()));
    }

    push(@attachmentfiles,$attachmentlogfile);
    if ($result and $completion) {
        completion(join("\n\n",@messages),\@attachmentfiles,getlogger(getscriptpath()));
    } elsif ($result) {
        done(join("\n\n",@messages),\@attachmentfiles,getlogger(getscriptpath()));
    } else {
        scriptwarn(join("\n\n",@messages),getlogger(getscriptpath()),1);
    }

    return $result;
}

sub taskinfo {
    my ($task,$result) = @_;
    scriptinfo($result ? "starting task: '$task'" : "skipping task '$task' due to previous problems",getlogger(getscriptpath()));
    #if (!$batch_supported and $batch) {
    #    scriptwarn("no batch processing supported for this mode",getlogger(getscriptpath()));
    #}
    return $result;
}

sub cleanup_task {
    my ($messages,$clean_generated) = @_;
    my $result = 0;
    #if (!$clean_generated or $force or 'yes' eq lc(prompt("Type 'yes' to proceed: "))) {
        destroy_all_dbs();
        eval {
            #cleanupcvsdirs() if $clean_generated;
            cleanupdbfiles() if $clean_generated;
            cleanuplogfiles(\&fileerror,\&filewarn,($currentlogfile,$attachmentlogfile));
            cleanupmsgfiles(\&fileerror,\&filewarn);
            cleanupdir($output_path,1,\&filewarn,getlogger(getscriptpath())) if $clean_generated;
            $result = 1;
        };
    #}
    if ($@ or !$result) {
        push(@$messages,'working directory cleanup error');
        return 0;
    } else {
        push(@$messages,'- working directory folders cleaned up');
        return 1;
    }
}

sub import_proband_task {
    my ($messages) = @_;
    my ($result, $warning_count) = (0,0);
    eval {
        ($result, $warning_count) = import_proband();
    };
    my $err = $@;

    if ($err) {
        #print $@;
        push(@$messages,'import_proband error: ' . $err);
        return 0;
    } else {
        push(@$messages,'- probands imported');
        return 1;
    }
}

sub create_duplicate_task {
    my ($messages) = @_;
    my ($result, $warning_count) = (0,0);
    eval {
        ($result, $warning_count) = create_duplicate();
    };
    my $err = $@;

    if ($err) {
        #print $@;
        push(@$messages,'create_duplicate error: ' . $err);
        return 0;
    } else {
        push(@$messages,'- duplicates identified');
        return 1;
    }
}

sub update_proband_task {
    my ($messages,$completion_ref) = @_;
    my ($result, $warning_count, $updated_proband_count) = (0,0,0);
    eval {
        ($result, $warning_count,$updated_proband_count) = update_proband();
    };
    my $err = $@;

    if ($err) {
        #print $@;
        push(@$messages,'update_proband error: ' . $err);
        return 0;
    } else {
        push(@$messages,'- ' . $updated_proband_count . ' probands' . ($dry ? '' : ' updated'));
        $$completion_ref = $updated_proband_count > 0;
        return 1;
    }
}

#END {
#    # this should not be required explicitly, but prevents Log4Perl's
#    # "rootlogger not initialized error upon exit..
#    destroy_all_dbs
#}

__DATA__
This exists to allow the locking code at the beginning of the file to work.
DO NOT REMOVE THESE LINES!
