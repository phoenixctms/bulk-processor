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
use CTSMS::BulkProcessor::Projects::ETL::InquirySettings qw(
    $output_path
    $skip_errors
    $ctsms_base_url
    $inquiry_data_trial_id
    $job_id
    @job_file
    update_job
    $lockfile
);
use CTSMS::BulkProcessor::Projects::ETL::InquiryExporter::Settings qw(
    $defaultsettings
    $defaultconfig
    $force
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
use CTSMS::BulkProcessor::Utils qw(getscriptpath prompt cleanupdir checkrunning);
use CTSMS::BulkProcessor::Mail qw(
    cleanupmsgfiles
);
use CTSMS::BulkProcessor::SqlConnectors::CSVDB qw(cleanupcvsdirs);
use CTSMS::BulkProcessor::SqlConnectors::SQLiteDB qw(cleanupdbfiles);

use CTSMS::BulkProcessor::Projects::ETL::InquiryConnectorPool qw(destroy_all_dbs);


use CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job qw(
    $PROCESSING_JOB_STATUS
    $FAILED_JOB_STATUS
    $OK_JOB_STATUS
);

use CTSMS::BulkProcessor::Projects::ETL::InquiryExport qw(
    export_inquiry_data_vertical
    export_inquiry_data_horizontal

    publish_inquiry_data_sqlite
    publish_inquiry_data_horizontal_csv
    publish_inquiry_data_xls

    publish_inquiry_data_pdfs
);

my @TASK_OPTS = ();

my $tasks = [];

my $cleanup_task_opt = 'cleanup';
push(@TASK_OPTS,$cleanup_task_opt);

my $cleanup_all_task_opt = 'cleanup_all';
push(@TASK_OPTS,$cleanup_all_task_opt);

my $export_inquiry_data_vertical_task_opt = 'export_inquiry_data_vertical';
push(@TASK_OPTS,$export_inquiry_data_vertical_task_opt);

my $export_inquiry_data_horizontal_task_opt = 'export_inquiry_data_horizontal';
push(@TASK_OPTS,$export_inquiry_data_horizontal_task_opt);

my $publish_inquiry_data_sqlite_task_opt = 'publish_inquiry_data_sqlite';
push(@TASK_OPTS,$publish_inquiry_data_sqlite_task_opt);

my $publish_inquiry_data_horizontal_csv_task_opt = 'publish_inquiry_data_horizontal_csv';
push(@TASK_OPTS,$publish_inquiry_data_horizontal_csv_task_opt);

my $publish_inquiry_data_xls_task_opt = 'publish_inquiry_data_xls';
push(@TASK_OPTS,$publish_inquiry_data_xls_task_opt);

my $publish_inquiry_data_pdfs_task_opt = 'publish_inquiry_data_pdfs';
push(@TASK_OPTS,$publish_inquiry_data_pdfs_task_opt);

my $upload_files = 0;

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
        "id=i" => \$inquiry_data_trial_id,
        "jid=i" => \$job_id,
        "auth=s" => \$auth,
        "upload" => \$upload_files,

    );

    my $result = load_config($configfile);
    #support credentials via args for jobs:
    if ($auth) {
        ($ctsmsrestapi_username,$ctsmsrestapi_password) = split("\n",decode_base64($auth),2);
    }
    init_log();
    $result &= load_config($settingsfile,\&CTSMS::BulkProcessor::Projects::ETL::InquirySettings::update_settings,$YAML_CONFIG_TYPE);
    $result &= load_config($settingsfile,\&CTSMS::BulkProcessor::Projects::ETL::InquiryExporter::Settings::update_settings,$YAML_CONFIG_TYPE);

    return $result;

}

sub main {

    my @messages = ( 'Trial inquiry export/data aggregation:' );
    my @attachmentfiles = ();
    my $result = 1;
    my $completion = 0;

    update_job($PROCESSING_JOB_STATUS);
    return 0 unless checkrunning(sprintf($lockfile,$inquiry_data_trial_id),sub {
        scriptwarn(@_);
        update_job($FAILED_JOB_STATUS);
        return 0;
    },getlogger(getscriptpath()));
    if (defined $tasks and 'ARRAY' eq ref $tasks and (scalar @$tasks) > 0) {

        foreach my $task (@$tasks) {

            if (lc($cleanup_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages,0) if taskinfo($cleanup_task_opt,\$result);

            } elsif (lc($cleanup_all_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages,1) if taskinfo($cleanup_all_task_opt,\$result);

            } elsif (lc($export_inquiry_data_vertical_task_opt) eq lc($task)) {
                $result &= export_inquiry_data_vertical_task(\@messages) if taskinfo($export_inquiry_data_vertical_task_opt,\$result,1);
            } elsif (lc($export_inquiry_data_horizontal_task_opt) eq lc($task)) {
                $result &= export_inquiry_data_horizontal_task(\@messages) if taskinfo($export_inquiry_data_horizontal_task_opt,\$result,1);

            } elsif (lc($publish_inquiry_data_sqlite_task_opt) eq lc($task)) {
                $result &= publish_inquiry_data_sqlite_task(\@messages,\@attachmentfiles) if taskinfo($publish_inquiry_data_sqlite_task_opt,\$result,1);
                $completion = $result;
            } elsif (lc($publish_inquiry_data_horizontal_csv_task_opt) eq lc($task)) {
                $result &= publish_inquiry_data_horizontal_csv_task(\@messages,\@attachmentfiles) if taskinfo($publish_inquiry_data_horizontal_csv_task_opt,\$result,1);
                $completion = $result;
            } elsif (lc($publish_inquiry_data_xls_task_opt) eq lc($task)) {
                $result &= publish_inquiry_data_xls_task(\@messages,\@attachmentfiles) if taskinfo($publish_inquiry_data_xls_task_opt,\$result,1);
                $completion = $result;

            } elsif (lc($publish_inquiry_data_pdfs_task_opt) eq lc($task)) {
                $result &= publish_inquiry_data_pdfs_task(\@messages,\@attachmentfiles) if taskinfo($publish_inquiry_data_pdfs_task_opt,\$result,1);
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
    if ($result and $completion) {
        if ($upload_files) {
            push(@messages,"Visit $ctsms_base_url/trial/trial.jsf?trialid=$inquiry_data_trial_id to download files.");
        }
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
    my ($task,$result_ref,$inquiry_data_trial_id_required) = @_;
    scriptinfo($$result_ref ? "starting task: '$task'" : "skipping task '$task' due to previous problems",getlogger(getscriptpath()));
    if ($inquiry_data_trial_id_required and (not defined $inquiry_data_trial_id or length($inquiry_data_trial_id) == 0)) {
        scripterror("trial id required",getlogger(getscriptpath()));
        $$result_ref = 0;
    }
    return $$result_ref;
}

sub cleanup_task {
    my ($messages,$clean_generated) = @_;
    my $result = 0;
    if (!$clean_generated or $force or 'yes' eq lc(prompt("Type 'yes' to proceed: "))) {
        eval {
            cleanupcvsdirs() if $clean_generated;
            cleanupdbfiles() if $clean_generated;
            cleanuplogfiles(\&fileerror,\&filewarn,($currentlogfile,$attachmentlogfile));
            cleanupmsgfiles(\&fileerror,\&filewarn);
            cleanupdir($output_path,1,\&filewarn,getlogger(getscriptpath())) if $clean_generated;
            $result = 1;
        };
    }
    if ($@ or !$result) {
        push(@$messages,'working directory cleanup error');
        return 0;
    } else {
        push(@$messages,'- working directory folders cleaned up');
        return 1;
    }
}

sub export_inquiry_data_vertical_task {
    my ($messages) = @_;
    my ($result, $warning_count) = (0,0);
    eval {
        ($result, $warning_count) = export_inquiry_data_vertical();
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'export_inquiry_data_vertical error: ' . $err);
        return 0;
    } else {
        push(@$messages,'- vertical inquiry data prepared');
        return 1;
    }
}

sub export_inquiry_data_horizontal_task {
    my ($messages) = @_;
    my ($result, $warning_count) = (0,0);
    eval {
        ($result, $warning_count) = export_inquiry_data_horizontal();
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'export_inquiry_data_horizontal error: ' . $err);
        return 0;
    } else {
        push(@$messages,'- horizontal inquiry data prepared');
        return 1;
    }
}

sub publish_inquiry_data_sqlite_task {
    my ($messages,$attachmentfiles) = @_;
    my $out = undef;
    eval {
        ($out,@job_file) = publish_inquiry_data_sqlite($upload_files);
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'publish_inquiry_data_sqlite error: ' . $err);
        return 0;
    } else {
        push(@$messages,"- file '$out->{title}' added to the '$out->{trial}->{name}' trial") if $out;
        return 1;
    }
}

sub publish_inquiry_data_horizontal_csv_task {
    my ($messages,$attachmentfiles) = @_;
    my $out = undef;
    eval {
        ($out,@job_file) = publish_inquiry_data_horizontal_csv($upload_files);
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'publish_inquiry_data_horizontal_csv error: ' . $err);
        return 0;
    } else {
        push(@$messages,"- file '$out->{title}' added to the '$out->{trial}->{name}' trial") if $out;
        push(@$messages,'- publish_inquiry_data_horizontal_csv finished (specify --upload to store the files)') unless $out;
        return 1;
    }
}

sub publish_inquiry_data_xls_task {
    my ($messages,$attachmentfiles) = @_;
    my $out = undef;
    eval {
        ($out,@job_file) = publish_inquiry_data_xls($upload_files);
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'publish_inquiry_data_xls error: ' . $err);
        return 0;
    } else {
        push(@$messages,"- file '$out->{title}' added to the '$out->{trial}->{name}' trial") if $out;
        push(@$messages,'- publish_inquiry_data_xls finished (specify --upload to store the files)') unless $out;
        return 1;
    }
}

sub publish_inquiry_data_pdfs_task {
    my ($messages,$attachmentfiles) = @_;
    my ($result, $warning_count, $uploads) = (0,0,undef);
    eval {
        ($result, $warning_count, $uploads) = publish_inquiry_data_pdfs($upload_files);
    };
    my $err = $@;
    if ($err) {
        push(@$messages,'publish_inquiry_data_pdfs error: ' . $err);
        return 0;
    } else {
        foreach my $upload (@$uploads) {
            my ($out,$filename) = @$upload;
            push(@$messages,"- file '$out->{title}' added to the '$out->{trial}->{name}' trial");
        }
        push(@$messages,'- publish_inquiry_data_pdfs finished (specify --upload to store the files)') unless ('ARRAY' eq ref $uploads and (scalar @$uploads > 0));
        return 1;
    }
}
