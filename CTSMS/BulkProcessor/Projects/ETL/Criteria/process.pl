use strict;

## no critic

use File::Basename;
use Cwd;
use lib Cwd::abs_path(File::Basename::dirname(__FILE__) . '/../../../../../');

use Getopt::Long qw(GetOptions);
use Fcntl qw(LOCK_EX LOCK_NB);

use CTSMS::BulkProcessor::Globals qw();
use CTSMS::BulkProcessor::Projects::ETL::Criteria::Settings qw(
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

use CTSMS::BulkProcessor::Projects::ETL::Criteria::Process qw(
    export_criteria
    import_criteria
);

scripterror(getscriptpath() . ' already running',getlogger(getscriptpath())) unless flock DATA, LOCK_EX | LOCK_NB; # not tested on windows yet

my @TASK_OPTS = ();

my $tasks = [];

my $cleanup_task_opt = 'cleanup';
push(@TASK_OPTS,$cleanup_task_opt);

my $cleanup_all_task_opt = 'cleanup_all';
push(@TASK_OPTS,$cleanup_all_task_opt);

my $export_criteria_task_opt = 'export_criteria';
push(@TASK_OPTS,$export_criteria_task_opt);

my $import_criteria_task_opt = 'import_criteria';
push(@TASK_OPTS,$import_criteria_task_opt);

my $create_criteria_task_opt = 'create_criteria';
push(@TASK_OPTS,$create_criteria_task_opt);

if (init()) {
    main();
    exit(0);
} else {
    exit(1);
}

sub init {

    my $configfile = $defaultconfig;
    my $settingsfile = $defaultsettings;

    return 0 unless GetOptions(
        "config=s" => \$configfile,
        "settings=s" => \$settingsfile,
        "task=s" => $tasks,
        "skip-errors" => \$skip_errors,
        "force" => \$force,
        "dry" => \$dry,
    );



    my $result = load_config($configfile);
    init_log();
    $result &= load_config($settingsfile,\&CTSMS::BulkProcessor::Projects::ETL::Criteria::Settings::update_settings,$YAML_CONFIG_TYPE);

    return $result;

}

sub main() {

    my @messages = ( 'Export/import database query criteria:' );
    my @attachmentfiles = ();
    my $result = 1;
    my $completion = 0;

    if (defined $tasks and 'ARRAY' eq ref $tasks and (scalar @$tasks) > 0) {
        scriptinfo('skip-errors: processing won\'t stop upon errors',getlogger(__PACKAGE__)) if $skip_errors;
        foreach my $task (@$tasks) {

            if (lc($cleanup_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages,0) if taskinfo($cleanup_task_opt,$result);

            } elsif (lc($cleanup_all_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages,1) if taskinfo($cleanup_all_task_opt,$result);

            } elsif (lc($export_criteria_task_opt) eq lc($task)) {
                $result &= export_criteria_task(\@messages,\@attachmentfiles) if taskinfo($export_criteria_task_opt,$result);
                $completion = 1;

            } elsif (lc($import_criteria_task_opt) eq lc($task)) {
                if (taskinfo($import_criteria_task_opt,$result)) {
                    next unless check_dry();
                    $result &= import_criteria_task(\@messages,0);
                    $completion = 1;
                }

            } elsif (lc($create_criteria_task_opt) eq lc($task)) {
                if (taskinfo($create_criteria_task_opt,$result)) {
                    next unless check_dry();
                    $result &= import_criteria_task(\@messages,1);
                    $completion = 1;
                }

            } else {
                $result = 0;
                scripterror("unknow task option '" . $task . "', must be one of " . join(', ',@TASK_OPTS),getlogger(getscriptpath()));
                last;
            }
        }

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



    return $result;
}

sub cleanup_task {
    my ($messages,$clean_generated) = @_;
    my $result = 0;


        eval {


            cleanuplogfiles(\&fileerror,\&filewarn,($currentlogfile,$attachmentlogfile));
            cleanupmsgfiles(\&fileerror,\&filewarn);
            cleanupdir($output_path,1,\&filewarn,getlogger(getscriptpath())) if $clean_generated;
            $result = 1;
        };

    if ($@ or !$result) {
        push(@$messages,'working directory cleanup error');
        return 0;
    } else {
        push(@$messages,'- working directory folders cleaned up');
        return 1;
    }
}

sub export_criteria_task {
    my ($messages,$completion_ref,$attachmentfiles) = @_;
    my ($result, $warning_count, $criteria_count, $filename) = (0,0,0,undef);
    eval {
        ($result, $warning_count, $criteria_count, $filename) = export_criteria();
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'export_criteria error: ' . $err);
        return 0;
    } else {
        push(@$messages,'- ' . $criteria_count . ' criteria exported (' . $warning_count . ' warnings)');
        push(@$attachmentfiles,$filename) if $filename;
        return $result;
    }
}

sub import_criteria_task {
    my ($messages,$create_all) = @_;
    my ($result,$warning_count,$updated_count,$added_count) = (0,0,0,0);
    eval {
        ($result, $warning_count,$updated_count,$added_count) = import_criteria($create_all);
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'import_criteria error: ' . $err);
        return 0;
    } else {
        push(@$messages,'- ' . ($updated_count + $added_count) . ' criteria imported (' . $warning_count . ' warnings)');
        push(@$messages,"  " . $updated_count . ' updated');
        push(@$messages,"  " . $added_count . ' added');

        return 1;
    }
}







__DATA__
This exists to allow the locking code at the beginning of the file to work.
DO NOT REMOVE THESE LINES!
