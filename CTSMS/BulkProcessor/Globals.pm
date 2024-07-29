package CTSMS::BulkProcessor::Globals;
use strict;

## no critic

use 5.8.8;

use threads; # as early as possible...
use threads::shared;

use Time::HiRes qw(time);

use Tie::IxHash;

use Cwd 'abs_path';
use File::Basename qw(dirname);
use File::Temp 0.2304 qw(tempdir);
use FindBin qw();

use CTSMS::BulkProcessor::Utils qw(
    get_ipaddress
    get_hostfqdn
    get_cpucount
    makepath
    fixdirpath
    $chmod_umask
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	$system_name
	$system_version
	$system_abbreviation
	$system_instance
	$system_instance_label
	$local_ip
	$local_fqdn
	$application_path
	$executable_path
	$working_path
    $is_perl_debug
    $is_windows

    create_path
	$appstartsecs
	$enablemultithreading
	$root_threadid
	$cpucount
    get_threadqueuelength

	$cells_transfer_memory_limit
	$LongReadLen_limit
	$transfer_defer_indexes

	$ctsms_databasename
	$ctsms_username
	$ctsms_password
	$ctsms_host
	$ctsms_port



    $ctsmsrestapi_uri
    $ctsmsrestapi_username
    $ctsmsrestapi_password
    $ctsmsrestapi_realm
    $ctsmsrestapi_path

	$csv_path

    $local_db_path
    $emailenable
    $erroremailrecipient
    $warnemailrecipient
    $completionemailrecipient
    $doneemailrecipient
    $mailfile_path

    $ismsexchangeserver
    $sender_address
    $smtp_server
    $smtpuser
    $smtppasswd
    $writefiles

    $logfile_path
    $fileloglevel
    $screenloglevel
    $emailloglevel
    $screenlogstderr
    $mailprog
    $mailtype

    $defaultconfig

    update_masterconfig
    create_path

    $chmod_umask

    @jobservers
    $jobnamespace
);

#set process umask for open and mkdir calls:
umask 0000;

# general constants
our $system_name = 'Bulk Processing Framework';
our $VERSION = '1.8.1';
our $system_version = $VERSION; #keep this filename-save
our $system_abbreviation = 'bpf'; #keep this filename-, dbname-save
our $system_instance = 'phoenix'; #'test'; #'2014'; #dbname-save 0-9a-z_
our $system_instance_label = 'Phoenix CTMS';

our $local_ip = get_ipaddress();
our $local_fqdn = get_hostfqdn();
our $application_path = get_applicationpath();
our $executable_path = $FindBin::RealBin . '/';



our $is_perl_debug = defined &DB::DB;

our $is_windows;
our $enablemultithreading;
if ($^O eq 'MSWin32') {
    $enablemultithreading = 1; # tested ok with windows.
    $is_windows = 1;
} else {
    $enablemultithreading = 1; # oel 5.4 perl 5.8.8 obvoisly not ok.
    $is_windows = 0;
}
if ($is_perl_debug) {
    $enablemultithreading = 0;
}

our $cpucount = get_cpucount();

sub get_threadqueuelength {
    my $length = shift;
    if ($length < 2 * $cpucount) {
        $length = 2 * $cpucount;
    }
    return $length;
}

our $root_threadid = 0;
our $cells_transfer_memory_limit = 10000000; #db fields
our $transfer_defer_indexes = 1;
#http://docstore.mik.ua/orelly/linux/dbi/ch06_01.htm
our $LongReadLen_limit = 128*1024; #longest LOB field size in bytes

our $appstartsecs = Time::HiRes::time();




our	$ctsms_databasename = 'ctsms';
our $ctsms_username = 'ctsms';
our	$ctsms_password = 'ctsms';
our $ctsms_host = '127.0.0.1';
our $ctsms_port = '5432';




our $ctsmsrestapi_uri = 'http://127.0.0.1:8080/ctsms-web/';
our $ctsmsrestapi_username = 'user_9qxs_1_1';
our $ctsmsrestapi_password = 'user_9qxs_1_1';
our $ctsmsrestapi_realm = 'api';
our $ctsmsrestapi_path = 'rest';

our $working_path = tempdir(CLEANUP => 0) . '/'; #'/var/xy/';





# csv
our $csv_path = $working_path . 'csv/';


# logging
our $logfile_path = $working_path . 'log/';


our $fileloglevel = 'OFF';
our $screenloglevel = 'INFO';
our $screenlogstderr = 0;
our $emailloglevel = 'OFF';






# local db setup
our $local_db_path = $working_path . 'db/';






# email setup
#set emailenable and writefiles to 0 during development with IDE that perform
#on-the-fly compilation during typing
our $emailenable = 0;                                # globally enable email sending
our $mailfile_path = $working_path . 'mails/';   # emails can be saved (logged) as message files to this folder

our $writefiles = 0;                                 # save emails

our $erroremailrecipient = '';
our $warnemailrecipient = '';
our $completionemailrecipient = '';
our $doneemailrecipient = '';

our $mailprog = "/usr/sbin/sendmail"; # linux only
our $mailtype = 2; #0 .. mailprog, 1 .. socket, 2 .. Net::SMTP


our $ismsexchangeserver = 0;                         # smtp server is a ms exchange server
our $smtp_server = '192.168.0.99';                   # smtp sever ip/hostname
our $smtpuser = 'WORKGROUP\rkrenn';
our $smtppasswd = 'xyz';
our $sender_address = 'donotreply@phoenixctms.at';



#service layer:
our @jobservers = ('127.0.0.1:4730');

our $jobnamespace = $system_abbreviation . '-' . $system_version . '-' . $system_instance;









our $defaultconfig = 'default.cfg';


sub update_masterconfig {

    my %params = @_;
    my ($data,
        $configfile,
        $split_tuplecode,
        $format_numbercode,
        $parse_regexpcode,
        $configurationinfocode,
        $configurationwarncode,
        $configurationerrorcode,
        $fileerrorcode,
        $simpleconfigtype,
        $yamlconfigtype,
        $anyconfigtype,
        $configlogger) = @params{qw/
            data
            configfile
            split_tuplecode
            format_numbercode
            parse_regexpcode
            configurationinfocode
            configurationwarncode
            configurationerrorcode
            fileerrorcode
            simpleconfigtype
            yamlconfigtype
            anyconfigtype
            configlogger
        /};

    if (defined $data) {

        my $result = 1;

        $ctsmsrestapi_uri = $data->{ctsmsrestapi_uri} if exists $data->{ctsmsrestapi_uri};
        $ctsmsrestapi_username = $data->{ctsmsrestapi_username} if exists $data->{ctsmsrestapi_username};
        $ctsmsrestapi_password = $data->{ctsmsrestapi_password} if exists $data->{ctsmsrestapi_password};
        $ctsmsrestapi_realm = $data->{ctsmsrestapi_realm} if exists $data->{ctsmsrestapi_realm};

        $cpucount = $data->{cpucount} if exists $data->{cpucount};
        $enablemultithreading = $data->{enablemultithreading} if exists $data->{enablemultithreading};
        if ($is_perl_debug) {
            $enablemultithreading = 0;
        }
        $cells_transfer_memory_limit = $data->{cells_transfer_memory_limit} if exists $data->{cells_transfer_memory_limit};
        $transfer_defer_indexes = $data->{transfer_defer_indexes} if exists $data->{transfer_defer_indexes};


        if (defined $split_tuplecode and ref $split_tuplecode eq 'CODE') {
            @jobservers = &$split_tuplecode($data->{jobservers}) if exists $data->{jobservers};
        } else {
            @jobservers = ($data->{jobservers}) if exists $data->{jobservers};
        }

        if (defined $format_numbercode and ref $format_numbercode eq 'CODE') {

        }

        if (defined $parse_regexpcode and ref $parse_regexpcode eq 'CODE') {

        }


        $emailenable = $data->{emailenable} if exists $data->{emailenable};
        $erroremailrecipient = $data->{erroremailrecipient} if exists $data->{erroremailrecipient};
        $warnemailrecipient = $data->{warnemailrecipient} if exists $data->{warnemailrecipient};
        $completionemailrecipient = $data->{completionemailrecipient} if exists $data->{completionemailrecipient};
        $doneemailrecipient = $data->{doneemailrecipient} if exists $data->{doneemailrecipient};

        $ismsexchangeserver = $data->{ismsexchangeserver} if exists $data->{ismsexchangeserver};
        $smtp_server = $data->{smtp_server} if exists $data->{smtp_server};
        $smtpuser = $data->{smtpuser} if exists $data->{smtpuser};
        $smtppasswd = $data->{smtppasswd} if exists $data->{smtppasswd};
        $sender_address = $data->{sender_address} if exists $data->{sender_address};

        $fileloglevel = $data->{fileloglevel} if exists $data->{fileloglevel};
        $screenloglevel = $data->{screenloglevel} if exists $data->{screenloglevel};
        $screenlogstderr = $data->{screenlogstderr} if exists $data->{screenlogstderr};
        $emailloglevel = $data->{emailloglevel} if exists $data->{emailloglevel};
        
        if ('debug' eq lc($fileloglevel)
            or 'debug' eq lc($screenloglevel)
            or 'debug' eq lc($screenlogstderr)
            or 'debug' eq lc($emailloglevel)) {
            $NGCP::BulkProcessor::SqlConnector::log_db_operations = 1;
        }

        if (exists $data->{working_path}) {
            $result &= _prepare_working_paths($data->{working_path},1,$fileerrorcode,$configlogger);
        } else {
            $result &= _prepare_working_paths($working_path,1,$fileerrorcode,$configlogger);
        }

        my @loadconfig_args = ();












        return ($result,\@loadconfig_args,\&_postprocess_masterconfig);

    }
    return (0,undef,\&_postprocess_masterconfig);

}


















sub _postprocess_masterconfig {

    my %params = @_;
    my ($data) = @params{qw/data/};

    if (defined $data) {

        $ctsms_host = $data->{ctsms_host} if exists $data->{ctsms_host};
        $ctsms_port = $data->{ctsms_port} if exists $data->{ctsms_port};
        $ctsms_databasename = $data->{ctsms_databasename} if exists $data->{ctsms_databasename};
        $ctsms_username = $data->{ctsms_username} if exists $data->{ctsms_username};
        $ctsms_password = $data->{ctsms_password} if exists $data->{ctsms_password};



        return 1;
    }
    return 0;

}

sub _prepare_working_paths {

    my ($new_working_path,$create,$fileerrorcode,$logger) = @_;
    my $result = 1;
    my $path_result;

    ($path_result,$working_path) = create_path($new_working_path,$working_path,$create,$fileerrorcode,$logger);
    $result &= $path_result;
    ($path_result,$csv_path) = create_path($working_path . 'csv',$csv_path,$create,$fileerrorcode,$logger);
    $result &= $path_result;


    ($path_result,$logfile_path) = create_path($working_path . 'log',$logfile_path,$create,$fileerrorcode,$logger);
    $result &= $path_result;
    ($path_result,$local_db_path) = create_path($working_path . 'db',$local_db_path,$create,$fileerrorcode,$logger);
    $result &= $path_result;
    ($path_result,$mailfile_path) = create_path($working_path . 'mails',$local_db_path,$create,$fileerrorcode,$logger);
    $result &= $path_result;



    return $result;

}

sub get_applicationpath {

  return dirname(abs_path(__FILE__)) . '/';

}

sub create_path {
    my ($new_value,$old_value,$create,$fileerrorcode,$logger) = @_;
    my $path = $old_value;
    my $result = 0;
    if (defined $new_value and length($new_value) > 0) {
        $new_value = fixdirpath($new_value);
        if (-d $new_value) {
            $path = $new_value;
            $result = 1;
        } else {
            if ($create) {
                if (makepath($new_value,$fileerrorcode,$logger)) {
                    $path = $new_value;
                    $result = 1;
                }
            } else {
                if (defined $fileerrorcode and ref $fileerrorcode eq 'CODE') {
                    &$fileerrorcode("path '$new_value' does not exist",$logger);
                }
            }
        }
    } else {
        if (defined $fileerrorcode and ref $fileerrorcode eq 'CODE') {
            &$fileerrorcode("empty path",$logger);
        }
    }
    return ($result,$path);
}

1;
