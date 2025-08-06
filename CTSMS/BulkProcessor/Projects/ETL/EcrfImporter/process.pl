use strict;

## no critic

use File::Basename;
use Cwd;
use lib Cwd::abs_path(File::Basename::dirname(__FILE__) . '/../../../../../');

use Getopt::Long qw(GetOptions);
use MIME::Base64 qw(decode_base64);

use CTSMS::BulkProcessor::Globals qw(
    $ctsmsrestapi_username
    $ctsmsrestapi_password
);
use CTSMS::BulkProcessor::Projects::ETL::EcrfSettings qw(
    $skip_errors
    $timezone
    $ctsms_base_url
    $ecrf_data_trial_id
    $lockfile
    $input_path
);
#$output_path
use CTSMS::BulkProcessor::Projects::ETL::Job qw(
    $job_id
    @job_file
    update_job
);
use CTSMS::BulkProcessor::Projects::ETL::EcrfImporter::Settings qw(
    $defaultsettings
    $defaultconfig
    $force
    $clear_sections
    $clear_all_sections
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
    $cli
);
use CTSMS::BulkProcessor::LoadConfig qw(
    load_config
    $SIMPLE_CONFIG_TYPE
    $YAML_CONFIG_TYPE
    $ANY_CONFIG_TYPE
);
use CTSMS::BulkProcessor::Array qw(removeduplicates);
use CTSMS::BulkProcessor::Utils qw(getscriptpath prompt cleanupdir checkrunning);
use CTSMS::BulkProcessor::Mail qw(
    cleanupmsgfiles
);
#use CTSMS::BulkProcessor::SqlConnectors::CSVDB qw(cleanupcsvdirs);
use CTSMS::BulkProcessor::SqlConnectors::SQLiteDB qw(cleanupdbfiles);

use CTSMS::BulkProcessor::Projects::ETL::EcrfConnectorPool qw(destroy_all_dbs);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job qw(
    $PROCESSING_JOB_STATUS
    $FAILED_JOB_STATUS
    $OK_JOB_STATUS
);

use CTSMS::BulkProcessor::Projects::ETL::EcrfImport qw(
    import_ecrf_data_horizontal
);

my @TASK_OPTS = ();

my $tasks = [];
my $file;

my $cleanup_task_opt = 'cleanup';
push(@TASK_OPTS,$cleanup_task_opt);

my $import_ecrf_data_horizontal_task_opt = 'import_ecrf_data_horizontal';
push(@TASK_OPTS,$import_ecrf_data_horizontal_task_opt);

if (init()) {
    main();
    exit(0);
} else {
    exit(1);
}

sub init {

    my $configfile = $defaultconfig;
    my $settingsfile = $defaultsettings;

    my $auth;
    return 0 unless GetOptions(
        "config=s" => \$configfile,
        "settings=s" => \$settingsfile,
        "task=s" => $tasks,
        "skip-errors" => \$skip_errors,
        "force" => \$force,
        "clear-sections" => \$clear_sections,
        "clear-all-sections" => \$clear_all_sections,
        "id=i" => \$ecrf_data_trial_id,
        "jid=i" => \$job_id,
        "auth=s" => \$auth,
        "file=s" => \$file,
        "tz=s" => \$timezone,
    );

    my $result = load_config($configfile);
    #support credentials via args for jobs:
    if ($auth) {
        ($ctsmsrestapi_username,$ctsmsrestapi_password) = split("\n",decode_base64($auth),2);
    }
    init_log();
    eval {
        $result &= load_config($settingsfile,\&CTSMS::BulkProcessor::Projects::ETL::EcrfSettings::update_settings,$YAML_CONFIG_TYPE);
        $result &= load_config($settingsfile,\&CTSMS::BulkProcessor::Projects::ETL::EcrfImporter::Settings::update_settings,$YAML_CONFIG_TYPE);
        $result &= load_config($settingsfile,\&CTSMS::BulkProcessor::Projects::ETL::Job::update_settings,$YAML_CONFIG_TYPE,undef,
            input_path => $input_path,
        );
    };
    if ($@) {
        $result = 0;
        eval {
            update_job($FAILED_JOB_STATUS);
        };
    }

    return $result;

}

sub main {

    my @messages = ( 'Trial eCRF data import:' );
    my @attachmentfiles = ();
    my $result = 1;
    my $completion = 0;

    update_job($PROCESSING_JOB_STATUS);
    return 0 unless checkrunning(sprintf($lockfile,$ecrf_data_trial_id),sub {
        scriptwarn(@_);
        update_job($FAILED_JOB_STATUS);
        return 0;
    },getlogger(getscriptpath()));
    if (defined $tasks and 'ARRAY' eq ref $tasks and (scalar @$tasks) > 0) {

        foreach my $task (@$tasks) {

            if (lc($cleanup_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages) if taskinfo($cleanup_task_opt,\$result);

            } elsif (lc($import_ecrf_data_horizontal_task_opt) eq lc($task)) {
                $result &= import_ecrf_data_horizontal_task(\@messages) if taskinfo($import_ecrf_data_horizontal_task_opt,\$result,
                    ecrf_data_trial_id_required => 1,
                    check_clear_sections => 1,
                    check_force => 1,
                    messages => \@messages,
                );
                $completion = $result;

            } else {
                $result = 0;
                scripterror("unknow task option '" . $task . "', must be one of " . join(', ',@TASK_OPTS),getlogger(getscriptpath()));
                last;
            }
            update_job($PROCESSING_JOB_STATUS);
        }
        destroy_all_dbs();
    } else {
        $result = 0;
        scripterror('at least one task option is required. supported tasks: ' . join(', ',@TASK_OPTS),getlogger(getscriptpath()));
    }

    push(@attachmentfiles,$attachmentlogfile);
    $cli = 1;
    if ($result and $completion) {
        completion(join("\n\n",@messages),\@attachmentfiles,getlogger(getscriptpath()));
        update_job($OK_JOB_STATUS);
    } elsif ($result) {
        done(join("\n\n",@messages),\@attachmentfiles,getlogger(getscriptpath()));
        update_job($OK_JOB_STATUS);
    } else {
        scriptwarn(join("\n\n",@messages),getlogger(getscriptpath()),1);
        update_job($FAILED_JOB_STATUS);
    }

    return $result;
}

sub taskinfo {
    my ($task,$result_ref,%params) = @_;
    my ($ecrf_data_trial_id_required,
        $check_clear_sections,
        $check_force,
        $messages) = @params{qw/
        ecrf_data_trial_id_required
        check_clear_sections
        check_force
        messages
    /};
    scriptinfo($$result_ref ? "starting task: '$task'" : "skipping task '$task' due to previous problems",getlogger(getscriptpath()));
    if ($ecrf_data_trial_id_required and (not defined $ecrf_data_trial_id or length($ecrf_data_trial_id) == 0)) {
        scripterror("trial id required",getlogger(getscriptpath()));
        $$result_ref = 0;
    }
    if ($check_clear_sections) {
        if ($clear_sections and $clear_all_sections) {
            scripterror("update mode: either 'clear sections' or 'clear all sections' can be enabled, but not both",getlogger(getscriptpath()));
            $$result_ref = 0;
        } elsif ($clear_all_sections) {
            scriptinfo("update mode: *all* sections of all eCRFs will be cleared prior to importing values",getlogger(getscriptpath()));
        } elsif ($clear_sections) {
            scriptinfo("update mode: sections of imported eCRF fields will be cleared prior to importing values",getlogger(getscriptpath()));
        } else {
            scriptinfo("update mode: existing values will be updated (eCRF sections are not cleared)",getlogger(getscriptpath()));
        }
    }
    unless (!$check_force or $force or 'yes' eq lc(prompt("Type 'yes' to proceed: "))) {
        push(@$messages,"task '$task' skipped by user") if $messages;
        $$result_ref = 0;
    }
    return $$result_ref;
}

sub cleanup_task {
    my ($messages) = @_;
    my $result = 0;
    eval {
        cleanupdbfiles();
        cleanuplogfiles(\&fileerror,\&filewarn,($currentlogfile,$attachmentlogfile));
        cleanupmsgfiles(\&fileerror,\&filewarn);
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

sub import_ecrf_data_horizontal_task {
    my ($messages) = @_;
    my ($result, $warning_count) = (0,0);
    eval {
        ($result, $warning_count) = import_ecrf_data_horizontal($file);
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'import_ecrf_data_horizontal error: ' . $err);
        return 0;
    } else {
        push(@$messages,'- import_ecrf_data_horizontal ok');
        return 1;
    }
}
