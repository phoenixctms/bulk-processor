use strict;

## no critic

use File::Basename;
use Cwd;
use lib Cwd::abs_path(File::Basename::dirname(__FILE__) . '/../../../../');

use Getopt::Long qw(GetOptions);
use Fcntl qw(LOCK_EX LOCK_NB);

use CTSMS::BulkProcessor::Globals qw();
use CTSMS::BulkProcessor::Projects::Render::Settings qw(
    update_settings
    $output_path
    $defaultsettings
    $defaultconfig
    $force

    $courseparticipationstatustype_participant_filename
    $courseparticipationstatustype_admin_filename
    $courseparticipationstatustype_self_registration_participant_filename
    $courseparticipationstatustype_self_registration_admin_filename

    $ecrffieldstatustype_annotation_filename
    $ecrffieldstatustype_validation_filename
    $ecrffieldstatustype_query_filename

    $probandliststatustype_person_filename
    $probandliststatustype_animal_filename
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
use CTSMS::BulkProcessor::SqlConnectors::CSVDB qw(cleanupcvsdirs);
use CTSMS::BulkProcessor::SqlConnectors::SQLiteDB qw(cleanupdbfiles);

use CTSMS::BulkProcessor::ConnectorPool qw(destroy_dbs);

use CTSMS::BulkProcessor::Projects::Render::JournalReportDiagrams qw(
    create_journal_heatmap
    create_logon_heatmap
    create_journal_histogram
);
use CTSMS::BulkProcessor::Projects::Render::StateDiagrams qw(
    create_ecrfstatustype_diagram
    create_courseparticipationstatustype_diagram
    create_privacyconsentstatustype_diagram
    create_trialstatustype_diagram
    create_probandliststatustype_diagram
    create_ecrffieldstatustype_diagram
    create_massmailstatustype_diagram
);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::EcrfFieldStatusType qw(
    $ANNOTATION_QUEUE
    $VALIDATION_QUEUE
    $QUERY_QUEUE
);

scripterror(getscriptpath() . ' already running',getlogger(getscriptpath())) unless flock DATA, LOCK_EX | LOCK_NB;

my @TASK_OPTS = ();

my $tasks = [];

my $cleanup_task_opt = 'cleanup';
push(@TASK_OPTS,$cleanup_task_opt);

my $cleanup_all_task_opt = 'cleanup_all';
push(@TASK_OPTS,$cleanup_all_task_opt);

my $create_ecrfstatustype_diagram_task_opt = 'create_ecrfstatustype_diagram';
push(@TASK_OPTS,$create_ecrfstatustype_diagram_task_opt);

my $create_courseparticipationstatustype_diagrams_task_opt = 'create_courseparticipationstatustype_diagrams';
push(@TASK_OPTS,$create_courseparticipationstatustype_diagrams_task_opt);

my $create_privacyconsentstatustype_diagram_task_opt = 'create_privacyconsentstatustype_diagram';
push(@TASK_OPTS,$create_privacyconsentstatustype_diagram_task_opt);

my $create_trialstatustype_diagram_task_opt = 'create_trialstatustype_diagram';
push(@TASK_OPTS,$create_trialstatustype_diagram_task_opt);

my $create_probandliststatustype_diagram_task_opt = 'create_probandliststatustype_diagram';
push(@TASK_OPTS,$create_probandliststatustype_diagram_task_opt);

my $create_ecrffieldstatustype_diagrams_task_opt = 'create_ecrffieldstatustype_diagrams';
push(@TASK_OPTS,$create_ecrffieldstatustype_diagrams_task_opt);

my $create_massmailstatustype_diagram_task_opt = 'create_massmailstatustype_diagram';
push(@TASK_OPTS,$create_massmailstatustype_diagram_task_opt);

my $create_logon_heatmap_task_opt = 'create_logon_heatmap';
push(@TASK_OPTS,$create_logon_heatmap_task_opt);

my $create_journal_heatmap_task_opt = 'create_journal_heatmap';
push(@TASK_OPTS,$create_journal_heatmap_task_opt);

my $create_journal_histogram_task_opt = 'create_journal_histogram';
push(@TASK_OPTS,$create_journal_histogram_task_opt);


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
        "force" => \$force,
    );

    $tasks = removeduplicates($tasks,1);

    my $result = load_config($configfile);
    init_log();
    $result &= load_config($settingsfile,\&update_settings,$SIMPLE_CONFIG_TYPE);

    return $result;

}

sub main {

    my @messages = ();
    my @attachmentfiles = ();
    my $result = 1;
    my $completion = 0;

    if (defined $tasks and 'ARRAY' eq ref $tasks and (scalar @$tasks) > 0) {

        foreach my $task (@$tasks) {

            if (lc($cleanup_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages,0) if taskinfo($cleanup_task_opt,$result);

            } elsif (lc($cleanup_all_task_opt) eq lc($task)) {
                $result &= cleanup_task(\@messages,1) if taskinfo($cleanup_all_task_opt,$result);

            } elsif (lc($create_ecrfstatustype_diagram_task_opt) eq lc($task)) {
                $result &= create_ecrfstatustype_diagram_task(\@messages) if taskinfo($create_ecrfstatustype_diagram_task_opt,$result);

            } elsif (lc($create_courseparticipationstatustype_diagrams_task_opt) eq lc($task)) {
                $result &= create_courseparticipationstatustype_diagrams_task(\@messages) if taskinfo($create_courseparticipationstatustype_diagrams_task_opt,$result);

            } elsif (lc($create_privacyconsentstatustype_diagram_task_opt) eq lc($task)) {
                $result &= create_privacyconsentstatustype_diagram_task(\@messages) if taskinfo($create_privacyconsentstatustype_diagram_task_opt,$result);

            } elsif (lc($create_trialstatustype_diagram_task_opt) eq lc($task)) {
                $result &= create_trialstatustype_diagram_task(\@messages) if taskinfo($create_trialstatustype_diagram_task_opt,$result);

            } elsif (lc($create_probandliststatustype_diagram_task_opt) eq lc($task)) {
                $result &= create_probandliststatustype_diagram_task(\@messages) if taskinfo($create_probandliststatustype_diagram_task_opt,$result);

            } elsif (lc($create_ecrffieldstatustype_diagrams_task_opt) eq lc($task)) {
                $result &= create_ecrffieldstatustype_diagrams_task(\@messages) if taskinfo($create_ecrffieldstatustype_diagrams_task_opt,$result);

            } elsif (lc($create_massmailstatustype_diagram_task_opt) eq lc($task)) {
                $result &= create_massmailstatustype_diagram_task(\@messages) if taskinfo($create_massmailstatustype_diagram_task_opt,$result);

            } elsif (lc($create_logon_heatmap_task_opt) eq lc($task)) {
                $result &= create_logon_heatmap_task(\@messages) if taskinfo($create_logon_heatmap_task_opt,$result);

            } elsif (lc($create_journal_heatmap_task_opt) eq lc($task)) {
                $result &= create_journal_heatmap_task(\@messages) if taskinfo($create_journal_heatmap_task_opt,$result);

            } elsif (lc($create_journal_histogram_task_opt) eq lc($task)) {
                $result &= create_journal_histogram_task(\@messages) if taskinfo($create_journal_histogram_task_opt,$result);


            } else {
                $result = 0;
                scripterror("unknow task option '" . $task . "', must be one of " . join(', ',@TASK_OPTS),getlogger(getscriptpath()));
                last;
            }
        }
        destroy_dbs();
    } else {
        $result = 0;
        scripterror('at least one task option is required. supported tasks: ' . join(', ',@TASK_OPTS),getlogger(getscriptpath()));
    }

    push(@attachmentfiles,$attachmentlogfile);
    if ($completion) {
        completion(join("\n\n",@messages),\@attachmentfiles,getlogger(getscriptpath()));
    } else {
        done(join("\n\n",@messages),\@attachmentfiles,getlogger(getscriptpath()));
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
        push(@$messages,'working directory cleanup INCOMPLETE');
        return 0;
    } else {
        push(@$messages,'working directory folders cleaned up');
        return 1;
    }
}

sub create_ecrfstatustype_diagram_task {
    my ($messages) = @_;
    eval {
        create_ecrfstatustype_diagram();
    };
    if ($@) {

        push(@$messages,'create_ecrfstatustype_diagram error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_ecrfstatustype_diagram done');
        return 1;
    }
}

sub create_courseparticipationstatustype_diagrams_task {
    my ($messages) = @_;
    eval {
        create_courseparticipationstatustype_diagram(0,0,$courseparticipationstatustype_participant_filename);
        create_courseparticipationstatustype_diagram(0,1,$courseparticipationstatustype_self_registration_participant_filename);

        create_courseparticipationstatustype_diagram(1,0,$courseparticipationstatustype_admin_filename);
        create_courseparticipationstatustype_diagram(1,1,$courseparticipationstatustype_self_registration_admin_filename);
    };
    if ($@) {

        push(@$messages,'create_courseparticipationstatustype_diagrams error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_courseparticipationstatustype_diagrams done');
        return 1;
    }
}

sub create_privacyconsentstatustype_diagram_task {
    my ($messages) = @_;
    eval {
        create_privacyconsentstatustype_diagram();
    };
    if ($@) {

        push(@$messages,'create_privacyconsentstatustype_diagram error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_privacyconsentstatustype_diagram done');
        return 1;
    }
}

sub create_trialstatustype_diagram_task {
    my ($messages) = @_;
    eval {
        create_trialstatustype_diagram();
    };
    if ($@) {

        push(@$messages,'create_trialstatustype_diagram error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_trialstatustype_diagram done');
        return 1;
    }
}

sub create_probandliststatustype_diagram_task {
    my ($messages) = @_;
    eval {
        create_probandliststatustype_diagram(undef,1,$probandliststatustype_person_filename);
        create_probandliststatustype_diagram(0,0,$probandliststatustype_animal_filename);
    };
    if ($@) {

        push(@$messages,'create_probandliststatustype_diagram error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_probandliststatustype_diagram done');
        return 1;
    }
}

sub create_ecrffieldstatustype_diagrams_task {
    my ($messages) = @_;
    eval {

        create_ecrffieldstatustype_diagram($ANNOTATION_QUEUE,$ecrffieldstatustype_annotation_filename);
        create_ecrffieldstatustype_diagram($VALIDATION_QUEUE,$ecrffieldstatustype_validation_filename);
        create_ecrffieldstatustype_diagram($QUERY_QUEUE,$ecrffieldstatustype_query_filename);

    };
    if ($@) {

        push(@$messages,'create_ecrffieldstatustype_diagrams error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_ecrffieldstatustype_diagrams done');
        return 1;
    }
}

sub create_massmailstatustype_diagram_task {
    my ($messages) = @_;
    eval {
        create_massmailstatustype_diagram();
    };
    if ($@) {

        push(@$messages,'create_massmailstatustype_diagram error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_massmailstatustype_diagram done');
        return 1;
    }
}


sub create_logon_heatmap_task {
    my ($messages) = @_;
    eval {
        create_logon_heatmap();
    };
    if ($@) {

        push(@$messages,'create_logon_heatmap error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_logon_heatmap done');
        return 1;
    }

}

sub create_journal_heatmap_task {
    my ($messages) = @_;
    eval {
        create_journal_heatmap();
    };
    if ($@) {

        push(@$messages,'create_journal_heatmap error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_journal_heatmap done');
        return 1;
    }

}

sub create_journal_histogram_task {
    my ($messages) = @_;
    eval {
        create_journal_histogram();
    };
    if ($@) {

        push(@$messages,'create_journal_histogram error: ' . $@);
        return 0;
    } else {
        push(@$messages,'create_journal_histogram done');
        return 1;
    }

}

__DATA__
This exists to allow the locking code at the beginning of the file to work.
DO NOT REMOVE THESE LINES!
