package CTSMS::BulkProcessor::LogError;
use strict;

## no critic

use CTSMS::BulkProcessor::Globals qw(
    $system_version
    $erroremailrecipient
    $warnemailrecipient
    $doneemailrecipient
    $completionemailrecipient
    $appstartsecs
    $root_threadid
    $enablemultithreading
);

use CTSMS::BulkProcessor::Mail qw(
    send_message
    send_email
    $signature
    wrap_mailbody
    $lowpriority
    $normalpriority
);
use CTSMS::BulkProcessor::Utils qw(
    threadid
    create_guid
    getscriptpath
    timestamp
    secs_to_years
);

use POSIX qw(ceil);

use File::Basename qw(basename);

use Time::HiRes qw(time);

use Carp qw(carp cluck croak confess);
#$Carp::Verbose = 1;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    notimplementederror
    faketimeerror
    runerror
    dberror
    dbwarn
    nosqlerror
    nosqlwarn
    nosqlprocessingfailed
    fieldnamesdiffer
    transferzerorowcount
    processzerorowcount
    deleterowserror
    rowprocessingwarn
    rowprocessingerror

    tabletransferfailed
    tableprocessingfailed

    resterror
    restwarn
    restrequesterror
    restresponseerror

    fileerror
    filewarn

    processzerofilesize
    fileprocessingfailed
    fileprocessingerror
    fileprocessingwarn

    restprocessingfailed

    emailwarn
    configurationwarn
    configurationerror

    sortconfigerror

    xls2csverror
    xls2csvwarn

    serviceerror
    servicewarn

    webarchivexls2csverror
    webarchivexls2csvwarn

    dbclustererror
    dbclusterwarn

    done
    completion

    scripterror
    scriptwarn

    $cli
);

our $cli = 1;

my $erroremailsubject = 'error: module ';
my $warnemailsubject = 'warning: module ';
my $donemailsubject = 'done: module ';
my $completionmailsubject = 'completed: module ';

sub done {

    my ($message,$attachments,$logger) = @_;

    if (length($message) == 0) {
        $message = 'done';
    }

    if ($cli) {
        my $appexitsecs = Time::HiRes::time();

        $message .= "\n\n" . 'time elapsed: ' . secs_to_years(ceil($appexitsecs - $appstartsecs));

        if (defined $logger) {
            $logger->info($message);
        }

        if (threadid() == $root_threadid) {
            if (length($doneemailrecipient) > 0 and defined $logger) {
                my $email = {
                    to          => $doneemailrecipient,



                    priority    => $lowpriority,


                    subject     => $donemailsubject . $logger->{category},
                    body        => getscriptpath() . ":\n\n" . wrap_mailbody($message) . "\n\n" . $signature,
                    guid        => create_guid()
                };

                my ($mailresult,$mailresultmessage) = send_email($email,$attachments,\&fileerror,\&emailwarn);
            }

        }
    } else {
        if (defined $logger) {
            $logger->info($message);
        }
    }

}

sub completion {

    my ($message,$attachments,$logger) = @_;

    if (length($message) == 0) {
        $message = 'completed';
    }

    if ($cli) {
        my $appexitsecs = Time::HiRes::time();

        $message .= "\n\n" . 'time elapsed: ' . secs_to_years(ceil($appexitsecs - $appstartsecs));

        if (defined $logger) {
            $logger->info($message);
        }

        if (threadid() == $root_threadid) {
            if (length($completionemailrecipient) > 0 and defined $logger) {
                my $email = {
                    to          => $completionemailrecipient,



                    priority    => $normalpriority,


                    subject     => $completionmailsubject . $logger->{category},
                    body        => getscriptpath() . ":\n\n" . wrap_mailbody($message) . "\n\n" . $signature,
                    guid        => create_guid()
                };

                my ($mailresult,$mailresultmessage) = send_email($email,$attachments,\&fileerror,\&emailwarn);
            }


        }
    } else {
        if (defined $logger) {
            $logger->info($message);
        }
    }

}

sub warning {

    my ($message,$logger,$sendemail) = @_;

    if (threadid() == $root_threadid and $cli) {
        if ($sendemail and length($warnemailrecipient) > 0 and defined $logger) {
            my ($mailresult,$mailresultmessage) = send_message($warnemailrecipient,$warnemailsubject . $logger->{category},getscriptpath() . ":\n\n" . wrap_mailbody($message) . "\n\n" . $signature,\&fileerror,\&emailwarn);
        }
        carp($message);

    } else {

        if ($cli) {
            carp($message)
        } else {
            warn($message."\n");
        }

    }

}

sub terminate {

    my ($message,$logger) = @_;

    if (threadid() == $root_threadid and $cli) {

        my $appexitsecs = Time::HiRes::time();

        $message .= "\n\n" . 'time elapsed: ' . secs_to_years(ceil($appexitsecs - $appstartsecs));

        if (length($erroremailrecipient) > 0 and defined $logger) {
            my ($mailresult,$mailresultmessage) = send_message($erroremailrecipient,$erroremailsubject . $logger->{category},getscriptpath() . ":\n\n" . wrap_mailbody($message) . "\n\n" . $signature,\&fileerror,\&emailwarn);
        }
        croak($message);

    } else {

        if ($cli) {
            croak($message)
        } else {
            die($message."\n");
        }

    }

}

sub notimplementederror {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub faketimeerror {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub runerror {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub dberror {

    my ($db, $message, $logger) = @_;
    $message = _getsqlconnectorinstanceprefix($db) . _getsqlconnectidentifiermessage($db,$message) if $cli;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub dbwarn {

    my ($db, $message, $logger) = @_;
    $message = _getsqlconnectorinstanceprefix($db) . _getsqlconnectidentifiermessage($db,$message) if $cli;
    if (defined $logger) {
        $logger->warn($message);
    }


    warning($message, $logger);

}

sub nosqlerror {

    my ($connector, $message, $logger) = @_;
    $message = _getnosqlconnectorinstanceprefix($connector) . _getnosqlconnectidentifiermessage($connector,$message);
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub nosqlwarn {

    my ($connector, $message, $logger) = @_;
    $message = _getnosqlconnectorinstanceprefix($connector) . _getnosqlconnectidentifiermessage($connector,$message);
    if (defined $logger) {
        $logger->warn($message);
    }

    warning($message, $logger);

}

sub nosqlprocessingfailed {

    my ($store,$scan_pattern,$logger) = @_;
    my $msg = 'keystore processing failed: ';
    my $connectidentifier = $store->connectidentifier();
    if ($connectidentifier) {
        $msg .= '[' . $connectidentifier . '] ';
    }
    $msg .= $scan_pattern;
    if (defined $logger) {
        $logger->error($msg);
    }
    terminate($msg, $logger);

}

sub resterror {

    my ($restapi, $message, $logger) = @_;
    $message = _getrestconnectorinstanceprefix($restapi) . _getrestconnectidentifiermessage($restapi,$message) if $cli;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub restwarn {

    my ($restapi, $message, $logger) = @_;
    $message = _getrestconnectorinstanceprefix($restapi) . _getrestconnectidentifiermessage($restapi,$message) if $cli;
    if (defined $logger) {
        $logger->warn($message);
    }


    warning($message, $logger);

}

sub restrequesterror {

    my ($restapi, $message, $request, $data, $logger) = @_;
    $message = _getrestconnectorinstanceprefix($restapi) . _getrestconnectidentifiermessage($restapi,$message) if $cli;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub restresponseerror {

    my ($restapi, $message, $response, $logger) = @_;
    $message = _getrestconnectorinstanceprefix($restapi) . _getrestconnectidentifiermessage($restapi,$message) if $cli;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub fieldnamesdiffer {

    my ($db,$tablename,$expectedfieldnames,$fieldnamesfound,$logger) = @_;
    my $message = _getsqlconnectorinstanceprefix($db) . 'wrong table fieldnames (v ' . $system_version . '): [' . $db->connectidentifier() . '].' . $tablename . ":\nexpected: " . ((defined $expectedfieldnames) ? join(', ',@$expectedfieldnames) : '<none>') . "\nfound:    " . ((defined $fieldnamesfound) ? join(', ',@$fieldnamesfound) : '<none>');
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub dbclustererror {

    my ($clustername,$message,$logger) = @_;
    $message = 'database cluster ' . $clustername . ': ' . $message;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub dbclusterwarn {

    my ($clustername,$message,$logger) = @_;
    $message = 'database cluster ' . $clustername . ': ' . $message;
    if (defined $logger) {
        $logger->warn($message);
    }


    warning($message, $logger);

}

sub transferzerorowcount {

    my ($db,$tablename,$target_db,$targettablename,$numofrows,$logger) = @_;
    my $message = _getsqlconnectorinstanceprefix($db) . '[' . $db->connectidentifier() . '].' . $tablename . ' has 0 rows';
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub processzerorowcount {

    my ($db,$tablename,$numofrows,$logger) = @_;
    my $message = '[' . $db->connectidentifier() . '].' . $tablename . ' has 0 rows';
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub rowprocessingerror {

    my ($tid, $message, $logger) = @_;
    if (defined $logger) {
        $logger->error(($enablemultithreading ? '[' . $tid . '] ' : '') . $message);
    }
    terminate($message, $logger);

}

sub rowprocessingwarn {

    my ($tid, $message, $logger) = @_;
    if (defined $logger) {
        $logger->warn(($enablemultithreading ? '[' . $tid . '] ' : '') . $message);
    }
    warning($message, $logger);

}

sub tabletransferfailed {

    my ($db,$tablename,$target_db,$targettablename,$numofrows,$logger) = @_;
    my $message = _getsqlconnectorinstanceprefix($db) . 'table transfer failed: [' . $db->connectidentifier() . '].' . $tablename . ' > ' . $targettablename;
    if (defined $logger) {
        $logger->error($message);
    }
    terminate($message, $logger);

}

sub tableprocessingfailed {

    my ($db,$tablename,$numofrows,$logger) = @_;
    my $message = 'table processing failed: [' . $db->connectidentifier() . '].' . $tablename;
    if (defined $logger) {
        $logger->error($message);
    }
    terminate($message, $logger);

}

sub deleterowserror {

    my ($db,$tablename,$message,$logger) = @_;
    $message = _getsqlconnectorinstanceprefix($db) . '[' . $db->connectidentifier() . '].' . $tablename . ' - ' . $message;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub fileerror {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}


sub processzerofilesize {

    my ($file,$logger) = @_;
    my $message = basename($file) . ' ' . (-e $file ? 'has 0 bytes' : 'not found');
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub fileprocessingfailed {

    my ($file,$logger) = @_;
    my $message = 'file processing failed: ' . basename($file);
    if (defined $logger) {
        $logger->error($message);
    }
    terminate($message, $logger);

}

sub fileprocessingerror {

    my ($file,$message,$logger) = @_;
    $message = basename($file) . ': ' . $message;
    if (defined $logger) {
        $logger->error($message);
    }
    terminate($message, $logger);

}

sub fileprocessingwarn {

    my ($file,$message,$logger) = @_;
    $message = basename($file) . ': ' . $message;
    if (defined $logger) {
        $logger->warn($message);
    }
    warning($message, $logger);

}

sub restprocessingfailed {

    my ($restapi,$path_query,$logger) = @_;
    my $message = 'collection processing failed: [' . $restapi->connectidentifier() . '] ' . $path_query;
    if (defined $logger) {
        $logger->error($message);
    }
    terminate($message, $logger);

}

sub xls2csverror {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub webarchivexls2csverror {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);



}

sub filewarn {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->warn($message);
    }


    warning($message, $logger);
}


sub xls2csvwarn {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->warn($message);
    }

    warning($message, $logger);
}

sub webarchivexls2csvwarn {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->warn($message);
    }

    warning($message, $logger);
}


sub emailwarn {

    my ($message, $errormsg, $response, $logger) = @_;
    if (defined $logger) {
        if (length($response) > 0) {
            $logger->warn($message . ': ' . $errormsg . ' \'' . $response . '\'');
        } else {
            $logger->warn($message . ': ' . $errormsg);
        }
    }

    warning($message, $logger, 0);

}

sub configurationwarn {

    my ($configfile,$message,$logger) = @_;
    $message = 'configuration file ' . $configfile . ': ' . $message;
    if (defined $logger) {
        $logger->warn($message);
    }
    warning($message, $logger, 0);

}

sub configurationerror {

    my ($configfile,$message,$logger) = @_;
    $message = 'configuration file ' . $configfile . ': ' . $message;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub sortconfigerror {

    my ($identifier,$message,$logger) = @_;

    if (defined $identifier) {
        $message = 'sort configuration (' . $identifier . '): ' . $message;
    } else {
        $message = 'sort configuration: ' . $message;
    }
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub serviceerror {

    my ($service, $message, $logger) = @_;
    $message = '[' . $service->{tid} . '] ' . $service->identifier() . ' - ' . $message;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub servicewarn {

    my ($service, $message, $logger) = @_;
    $message = '[' . $service->{tid} . '] ' . $service->identifier() . ' - ' . $message;
    if (defined $logger) {
        $logger->warn($message);
    }


    warning($message, $logger);

}

sub _getsqlconnectorinstanceprefix {
    my ($db) = @_;
    my $instancestring = $db->instanceidentifier();
    if (length($instancestring) > 0) {
    if ($db->{tid} != $root_threadid) {
        return '[' . $db->{tid} . '/' . $instancestring . '] ';
    } else {
        return '[' . $instancestring . '] ';
    }
    } elsif ($db->{tid} != $root_threadid) {
    return '[' . $db->{tid} . '] ';
    }
    return '';
}

sub scripterror {

    my ($message, $logger) = @_;
    if (defined $logger) {
        $logger->error($message);
    }

    terminate($message, $logger);

}

sub scriptwarn {

    my ($message, $logger , $sendemail) = @_;
    if (defined $logger) {
        $logger->warn($message);
    }

    warning($message, $logger, $sendemail);

}

sub _getsqlconnectidentifiermessage {
    my ($db,$message) = @_;
    my $result = $db->connectidentifier();
    my $connectidentifier = $db->_connectidentifier();
    if (length($result) > 0 and defined $db->cluster and length($connectidentifier) > 0) {
    $result .= '->' . $connectidentifier;
    }
    if (length($result) > 0) {
    $result .= ' - ';
    }
    return $result . $message;
}

sub _getrestconnectorinstanceprefix {
    my ($restapi) = @_;
    my $instancestring = $restapi->instanceidentifier();
    if (length($instancestring) > 0) {
    if ($restapi->{tid} != $root_threadid) {
        return '[' . $restapi->{tid} . '/' . $instancestring . '] ';
    } else {
        return '[' . $instancestring . '] ';
    }
    } elsif ($restapi->{tid} != $root_threadid) {
    return '[' . $restapi->{tid} . '] ';
    }
    return '';
}

sub _getrestconnectidentifiermessage {
    my ($restapi,$message) = @_;
    my $result = $restapi->connectidentifier();
    if (length($result) > 0) {
    $result .= ' - ';
    }
    return $result . $message;
}

sub _getnosqlconnectorinstanceprefix {
    my ($connector) = @_;
    my $instancestring = $connector->instanceidentifier();
    if (length($instancestring) > 0) {
    if ($connector->{tid} != $root_threadid) {
        return '[' . $connector->{tid} . '/' . $instancestring . '] ';
    } else {
        return '[' . $instancestring . '] ';
    }
    } elsif ($connector->{tid} != $root_threadid) {
    return '[' . $connector->{tid} . '] ';
    }
    return '';
}

sub _getnosqlconnectidentifiermessage {
    my ($connector,$message) = @_;
    my $result = $connector->connectidentifier();
    if (length($result) > 0) {
    $result .= ' - ';
    }
    return $result . $message;
}

1;
