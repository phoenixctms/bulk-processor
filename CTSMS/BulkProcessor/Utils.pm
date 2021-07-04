package CTSMS::BulkProcessor::Utils;
use strict;

## no critic

use threads;

use POSIX qw(strtod locale_h floor fmod);
setlocale(LC_NUMERIC, 'C');

use Fcntl qw(LOCK_EX LOCK_NB);
use Data::UUID qw();
use Net::Address::IP::Local qw();
use Net::Domain qw(hostname hostfqdn hostdomain);
use Cwd qw(abs_path);
use Date::Manip qw(Date_Init ParseDate UnixDate);

Date_Init('DateFormat=US');
use Date::Calc qw(Normalize_DHMS Add_Delta_DHMS);
use DateTime::Format::Excel qw();

use Text::Wrap qw();
use Digest::MD5 qw();
use File::Temp 0.2304 qw(tempfile tempdir) ;
use File::Path 2.07 qw(remove_tree make_path);

use Encode qw(encode_utf8 encode_utf8);

# after all, the only reliable way to get the true vCPU count:
my $can_cpu_affinity = 1;
eval "use Sys::CpuAffinity"; # qw(getNumCpus); not exported?
if ($@) {
    $can_cpu_affinity = 1;
}

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    float_equal
    round
    stringtobool
    booltostring
    check_bool
    tempfilename
    timestampdigits
    datestampdigits
    parse_datetime
    parse_date
    timestampfromdigits
    datestampfromdigits
    timestamptodigits
    datestamptodigits
    timestamptostring
    timestampaddsecs
    file_md5
    cat_file
    wrap_text
    create_guid

    urlencode
    urldecode
    utf8bytes_to_string
    string_to_utf8bytes
    timestamp
    datestamp
    timestamp_fromepochsecs
    get_year
    get_year_month
    get_year_month_day
    to_duration_string
    secs_to_years

    zerofill
    trim
    chopstring
    get_ipaddress
    get_hostfqdn
    getscriptpath

    kbytes2gigs
    cleanupdir
    fixdirpath
    threadid
    format_number

    dec2bin
    bin2dec

    check_number
    min_timestamp
    max_timestamp
    add_months
    makepath
    changemod

    get_cpucount

    $chmod_umask

    prompt
    check_int

    run
    shell_args

    excel_to_date
    excel_to_timestamp

    checkrunning
    unshare

    load_module
);

our $chmod_umask = 0777; #0644;
#"You need the group "x" bit set in the directory to allow group searches. The "rw-" permissions allow opening a file given its name (r) or creating a file (w), but not listing or searching the files (x)."

my $default_epsilon = 1e-3; #float comparison tolerance

sub float_equal {

    my ($a, $b, $epsilon) = @_;
    if ((!defined $epsilon) || ($epsilon <= 0.0)) {
        $epsilon = $default_epsilon;
    }
    return (abs($a - $b) < $epsilon);

}

sub round {

    my ($number) = @_;
    return int($number + .5 * ($number <=> 0));

}

sub stringtobool {

  my $inputstring = shift;
  if (lc($inputstring) eq 'y' or lc($inputstring) eq 'true' or $inputstring >= 1) {
    return 1;
  } else {
    return 0;
  }

}

sub booltostring {

  if (shift) {
    return 'true';
  } else {
    return 'false';
  }

}

sub check_bool {

  my $inputstring = shift;
  if (lc($inputstring) eq 'y' or lc($inputstring) eq 'true' or $inputstring >= 1) {
    return 1;
  } elsif (lc($inputstring) eq 'n' or lc($inputstring) eq 'false' or $inputstring == 0) {
    return 1;
  } else {
    return 0;
  }

}

sub timestampdigits {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return sprintf "%4d%02d%02d%02d%02d%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec;

}

sub datestampdigits {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return sprintf "%4d%02d%02d",$year+1900,$mon+1,$mday;

}

sub parse_datetime {

  my ($datetimestring,$non_us) = @_;
  if ($non_us) {
    Date_Init('DateFormat=non-US');
  } else {
    Date_Init('DateFormat=US');
  }
  my $datetime = ParseDate($datetimestring);
  if (!$datetime) {
    return undef;
  } else {
    my ($year,$mon,$mday,$hour,$min,$sec) = UnixDate($datetime,"%Y","%m","%d","%H","%M","%S");
    return sprintf "%4d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hour,$min,$sec;
  }

}

sub parse_date {

  my ($datetimestring,$non_us) = @_;
  if ($non_us) {
    Date_Init('DateFormat=non-US');
  } else {
    Date_Init('DateFormat=US');
  }
  my $datetime = ParseDate($datetimestring);
  if (!$datetime) {
    return undef;
  } else {
    my ($year,$mon,$mday) = UnixDate($datetime,"%Y","%m","%d");
    return sprintf "%4d-%02d-%02d",$year,$mon,$mday;
  }

}

sub timestampfromdigits {

  my ($timestampdigits) = @_;
  if ($timestampdigits =~ /^[0-9]{14}$/g) {
    return substr($timestampdigits,0,4) . '-' .
         substr($timestampdigits,4,2) . '-' .
         substr($timestampdigits,6,2) . ' ' .
         substr($timestampdigits,8,2) . ':' .
         substr($timestampdigits,10,2) . ':' .
         substr($timestampdigits,12,2);
  } else {
    return $timestampdigits;
  }

}

sub datestampfromdigits {

  my ($datestampdigits) = @_;
  if ($datestampdigits =~ /^[0-9]{8}$/g) {
    return substr($datestampdigits,0,4) . '-' .
         substr($datestampdigits,4,2) . '-' .
         substr($datestampdigits,6,2);
  } else {
    return $datestampdigits;
  }

}

sub timestamptodigits {

  my ($datetimestring,$non_us) = @_;
  if ($non_us) {
    Date_Init('DateFormat=non-US');
  } else {
    Date_Init('DateFormat=US');
  }
  my $datetime = ParseDate($datetimestring);
  if (!$datetime) {
    return '0';
  } else {
    my ($year,$mon,$mday,$hour,$min,$sec) = UnixDate($datetime,"%Y","%m","%d","%H","%M","%S");
    return sprintf "%4d%02d%02d%02d%02d%02d",$year,$mon,$mday,$hour,$min,$sec;
  }

}

sub datestamptodigits {

  my ($datestring,$non_us) = @_;
  if ($non_us) {
    Date_Init('DateFormat=non-US');
  } else {
    Date_Init('DateFormat=US');
  }
  my $datetime = ParseDate($datestring);
  if (!$datetime) {
    return '0';
  } else {
    my ($year,$mon,$mday) = UnixDate($datetime,"%Y","%m","%d");
    return sprintf "%4d%02d%02d",$year,$mon,$mday;
  }

}

sub timestamptostring {

    Date_Init('DateFormat=US');
    return UnixDate(@_);

}

sub timestampaddsecs {

  my ($datetimestring,$timespan,$non_us) = @_;

  if ($non_us) {
    Date_Init('DateFormat=non-US');
  } else {
    Date_Init('DateFormat=US');
  }

  my $datetime = ParseDate($datetimestring);

  if (!$datetime) {

    return $datetimestring;

  } else {

    my ($fromyear,$frommonth,$fromday,$fromhour,$fromminute,$fromsecond) = UnixDate($datetime,"%Y","%m","%d","%H","%M","%S");

    my ($Dd,$Dh,$Dm,$Ds) = Date::Calc::Normalize_DHMS(0,0,0,$timespan);
    my ($toyear,$tomonth,$to_day,$tohour,$tominute,$tosecond) = Date::Calc::Add_Delta_DHMS($fromyear,$frommonth,$fromday,$fromhour,$fromminute,$fromsecond,
                                                                                           $Dd,$Dh,$Dm,$Ds);

    return sprintf "%4d-%02d-%02d %02d:%02d:%02d",$toyear,$tomonth,$to_day,$tohour,$tominute,$tosecond;

  }

}

sub tempfilename {

   my ($template,$path,$suffix) = @_;
   my ($tmpfh,$tmpfilename) = tempfile($template,DIR => $path,SUFFIX => $suffix);
   close $tmpfh;
   return $tmpfilename;

}

sub file_md5 {

    my ($filepath,$fileerrorcode,$logger) = @_;

    local *MD5FILE;

    if (not open (MD5FILE, '<' . $filepath)) {
      if (defined $fileerrorcode and ref $fileerrorcode eq 'CODE') {
        &$fileerrorcode('md5sum - cannot open file ' . $filepath . ': ' . $!,$logger);
      }
      return '';
    }
    binmode MD5FILE;
    my $md5digest = Digest::MD5->new->addfile(*MD5FILE)->hexdigest;
    close MD5FILE;
    return $md5digest;

}

sub cat_file {

    my ($filepath,$fileerrorcode,$logger) = @_;

    if (not open (CATFILE, '<' . $filepath)) {
      if (defined $fileerrorcode and ref $fileerrorcode eq 'CODE') {
        &$fileerrorcode('cat - cannot open file ' . $filepath . ': ' . $!,$logger);
      }
      return '';
    }
    my @linebuffer = <CATFILE>;
    close CATFILE;
    return join("\n",@linebuffer);

}

sub wrap_text {

    my ($inputstring, $columns) = @_;
    $Text::Wrap::columns = $columns;
    return Text::Wrap::wrap("","",$inputstring);

}

sub create_guid {

  my $ug = new Data::UUID;
  my $uuid = $ug->create();
  return $ug->to_string( $uuid );

}

sub urlencode {
  my ($urltoencode) = @_;
  $urltoencode =~ s/([^a-zA-Z0-9\/_\-.])/uc sprintf("%%%02x",ord($1))/eg;
  return $urltoencode;
}

sub urldecode {
  my ($urltodecode) = @_;
  $urltodecode =~ s/%([\dA-Fa-f][\dA-Fa-f])/pack ("C", hex ($1))/eg;
  return $urltodecode;
}

sub utf8bytes_to_string {
    my $bytes = shift;
    if (defined $bytes) {
        return encode_utf8(join('',map { chr($_); } @$bytes));
    }
}
sub string_to_utf8bytes {
    my $string = shift;
    if (defined $string) {
        return [ map { ord($_); } split(//, encode_utf8($string)) ];
    }
}

sub timestamp {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return sprintf "%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec;

}

sub timestamp_fromepochsecs {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift);
  return sprintf "%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec;

}

sub datestamp {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return sprintf "%4d-%02d-%02d",$year+1900,$mon+1,$mday;

}

sub get_year {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return (sprintf "%4d",$year+1900);

}

sub get_year_month {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return ((sprintf "%4d",$year+1900),(sprintf "%02d",$mon+1));

}

sub get_year_month_day {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return ((sprintf "%4d",$year+1900),(sprintf "%02d",$mon+1),(sprintf "%02d",$mday));

}


sub excel_to_date {
    my $excel_date_value = shift;
    if ($excel_date_value > 0) {
        my $datetime = DateTime::Format::Excel->parse_datetime($excel_date_value);
        return $datetime->ymd('-');     # prints 2003-02-28
    }
    return undef;
}

sub excel_to_timestamp {
    my $excel_datetime_value = shift;
    if ($excel_datetime_value > 0) {
        my $datetime = DateTime::Format::Excel->parse_datetime($excel_datetime_value);
        return $datetime->ymd('-') . ' ' . $datetime->hms(':');
    }
    return undef;
}

sub zerofill {
  my ($integer,$digits) = @_;
  my $numberofzeroes = $digits - length($integer);
  my $resultstring = $integer;
  if ($digits > 0) {
    for (my $i = 0; $i < $numberofzeroes; $i += 1) {
      $resultstring = "0" . $resultstring;
    }
  }
  return $resultstring;
}

sub trim {
  my ($inputstring) = @_;

  $inputstring =~ s/[\n\r\t]/ /g;
  $inputstring =~ s/^ +//;
  $inputstring =~ s/ +$//;

  return $inputstring;
}

sub chopstring {

  my ($inputstring,$trimlength,$ending) = @_;

  my $result = $inputstring;

  if (defined $inputstring) {

    $result =~ s/[\n\r\t]/ /g;

    if (!defined $trimlength) {
      $trimlength = 30;
    }
    if (!defined $ending) {
      $ending = '...'
    }

    if (length($result) > $trimlength) {
      return substr($result,0,$trimlength-length($ending)) . $ending;
    }
  }

  return $result;

}

sub get_ipaddress {

  # Get the local system's IP address that is "en route" to "the internet":
  return Net::Address::IP::Local->public;

}

sub get_hostfqdn {

    return hostfqdn();

}

sub getscriptpath {

  return abs_path($0);

}

sub kbytes2gigs {
   my ($TotalkBytes,$kbytebase,$round) = @_;

   if ($kbytebase <= 0) {
     $kbytebase = 1024;
   }

   my $TotalkByteskBytes = $TotalkBytes;
   my $TotalkBytesMBytes = $TotalkBytes;
   my $TotalkBytesGBytes = $TotalkBytes;

   my $rounded = 0;
   $TotalkByteskBytes = $TotalkBytes;
   $TotalkBytesMBytes = 0;
   $TotalkBytesGBytes = 0;

   if ($TotalkByteskBytes >= $kbytebase) {
     $TotalkBytesMBytes = int($TotalkByteskBytes / $kbytebase);
     $rounded = int(($TotalkByteskBytes * 100) / $kbytebase) / 100;
     if ($round) {
       $rounded = int($rounded);
     }
     $rounded .= " MBytes";
     $TotalkByteskBytes = $TotalkBytes - $TotalkBytesGBytes * $kbytebase * $kbytebase - $TotalkBytesMBytes * $kbytebase;
     if ($TotalkBytesMBytes >= $kbytebase) {
       $TotalkBytesGBytes = int($TotalkBytesMBytes / $kbytebase);
       $rounded = int(($TotalkBytesMBytes * 100) / $kbytebase) / 100;
       if ($round) {
         $rounded = int($rounded);
       }
       $rounded .= " GBytes";
       $TotalkBytesMBytes = int(($TotalkBytes - $TotalkBytesGBytes * $kbytebase * $kbytebase) / $kbytebase);
       $TotalkByteskBytes = $TotalkBytes - $TotalkBytesGBytes * $kbytebase * $kbytebase - $TotalkBytesMBytes * $kbytebase;
     }
   }

   if ($TotalkBytesGBytes == 0 && $TotalkBytesMBytes == 0) {
     $TotalkBytes .= " kBytes";
   } elsif ($TotalkBytesGBytes == 0) {
     $TotalkBytes = $rounded;
     if ($round) {
       $TotalkBytes = $rounded;
     }
   } else {
     $TotalkBytes = $rounded;
     if ($round) {
       $TotalkBytes = $rounded;
     }
   }
   return $TotalkBytes;
}

sub cleanupdir {

    my ($dirpath,$keeproot,$filewarncode,$logger) = @_;
    my $removed_count = 0;
    if (-d $dirpath) {
        my $err;
        eval {
            $removed_count = remove_tree($dirpath, {
                    'keep_root' => $keeproot,
                    'verbose' => 1,
                    'error' => \$err });
        };
        if ($@) {
            if ($@ =~ /cannot chdir to .+ from .+/) {
                # https://perldoc.perl.org/File::Path
                # "cannot chdir to [parent-dir] from [child-dir]: [errmsg], aborting. (FATAL)
                # remove_tree, after having deleted everything and restored the permissions of
                # a directory, was unable to chdir back to the parent. The program halts to
                # avoid a race condition from occurring."
                $err = [] unless $err;
            } else {
                die($@);
            }
        }
        if (@$err) {
            if (defined $filewarncode and ref $filewarncode eq 'CODE') {
                for my $diag (@$err) {
                    my ($file, $message) = %$diag;
                    if ($file eq '') {
                        &$filewarncode("cleanup: $message",$logger);
                    } else {
                        &$filewarncode("problem unlinking $file: $message",$logger);
                    }
                }
            }
        }
    }
    return $removed_count;
}

sub fixdirpath {
    my ($dirpath) = @_;
    $dirpath .= '/' if $dirpath !~ m!/$!;
    return $dirpath;
}

sub makepath {
    my ($dirpath,$fileerrorcode,$logger) = @_;

    make_path($dirpath,{
        'chmod' => $chmod_umask,
        'verbose' => 1,
        'error' => \my $err });
    if (@$err) {
        if (defined $fileerrorcode and ref $fileerrorcode eq 'CODE') {
            for my $diag (@$err) {
                my ($file, $message) = %$diag;
                if ($file eq '') {
                    &$fileerrorcode("creating path: $message",$logger);
                } else {
                    &$fileerrorcode("problem creating $file: $message",$logger);
                }
            }
        }
        return 0;
    }
    return 1;
}

sub changemod {
    my ($filepath) = @_;
    chmod $chmod_umask,$filepath;
}

sub threadid {

    return threads->tid();

}

sub format_number {
  my ($value,$decimals) = @_;
  my $output = $value;

  if (defined $decimals and $decimals >= 0) {
    $output = round(($output * (10 ** ($decimals + 1))) / 10) / (10 ** $decimals);
    $output = sprintf("%." . $decimals . "f",$output);
    if (index($output,',') > -1) {
      $output =~ s/,/\./g;
    }
  } else {
    $output = sprintf("%f",$output);
    if (index($output,'.') > -1) {
      $output =~ s/0+$//g;
      $output =~ s/\.$//g;
    }
  }
  return $output;
}

sub dec2bin {
    my $str = unpack("B32", pack("N", shift));
    $str =~ s/^0+(?=\d)//;   # leading zeros otherwise
    return $str;
}

sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}

sub getnum {

    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    $! = 0;
    my($num, $unparsed) = strtod($str);
    if (($str eq '') || ($unparsed != 0) || $!) {
        return;
    } else {
        return $num;
    }
}

sub check_number {

    my $potential_number = shift;
    if (defined getnum($potential_number)) {
        return 1;
    } else {
        return 0;
    }

}

sub min_timestamp {

    my (@timestamps) = @_;

    my $min_ts = $timestamps[0];
    foreach my $ts (@timestamps) {
        if (($ts cmp $min_ts) < 0) {
            $min_ts = $ts;
        }
    }

    return $min_ts;

}

sub max_timestamp {

    my (@timestamps) = @_;

    my $min_ts = $timestamps[0];
    foreach my $ts (@timestamps) {
        if (($ts cmp $min_ts) > 0) {
            $min_ts = $ts;
        }
    }

    return $min_ts;

}

sub add_months {

  my ($month, $year, $ads) = @_;

  if ($month > 0  and $month <= 12) {

    my $sign = ($ads > 0) ? 1 : -1;
    my $rmonths = $month + $sign * (abs($ads) % 12);
    my $ryears = $year + int( $ads / 12 );

    if ($rmonths < 1) {
      $rmonths += 12;
      $ryears -= 1;
    } elsif ($rmonths > 12) {
      $rmonths -= 12;
      $ryears += 1;
    }

    return ($rmonths,$ryears);

  } else {

    return (undef,undef);

  }

}

sub secs_to_years {

  my $time_in_secs = shift;

  my $negative = 0;
  if ($time_in_secs < 0) {
    $time_in_secs *= -1;
    $negative = 1;
  }

  my $years = 0;
  my $months = 0;
  my $days = 0;
  my $hours = 0;
  my $mins = 0;
  my $secs = $time_in_secs;

  if ($secs >= 60) {
    $mins = int($secs / 60);
    $secs = ($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60-$mins*60);
    if ($mins >= 60) {
      $hours = int($mins / 60);
      $mins = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60) / (60));
      $secs = ($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60-$mins*60);
      if ($hours >= 24) {
        $days = int($hours / 24);
        $hours = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24) / (60*60));
        $mins = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60) / (60));
        $secs = ($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60-$mins*60);
        if ($days >= 30) {
          $months = int($days / 30);
          $days = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30) / (60*60*24));
          $hours = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24) / (60*60));
          $mins = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60) / (60));
          $secs = ($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60-$mins*60);
          if ($months >= 12) {
            $years = int($months / 12);
            $months = int(($time_in_secs-$years*60*60*24*30*12) / (60*60*24*30));
            $days = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30) / (60*60*24));
            $hours = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24) / (60*60));
            $mins = int(($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60) / (60));
            $secs = ($time_in_secs-$years*60*60*24*30*12-$months*60*60*24*30-$days*60*60*24-$hours*60*60-$mins*60);
          }
        }
      }
    }
  }

  $secs = zerofill(int($secs),2);
  $mins = zerofill($mins,2);
  $hours = zerofill($hours,2);

  if ($years == 0 && $months == 0 && $days == 0) {
    $time_in_secs = $hours . ':' . $mins . ':' . $secs;
  } elsif($years == 0 && $months == 0) {
    $time_in_secs = $days . ' day(s) - ' . $hours . ':' . $mins . ':' . $secs;
  } elsif($years == 0) {
    $time_in_secs = $months . ' month(s)/' . $days . ' day(s) - ' . $hours . ':' . $mins . ':' . $secs;
  } else {
    $time_in_secs = $years . ' year(s)/' . $months . ' month(s)/' . $days . ' day(s) - ' . $hours . ':' . $mins . ':' . $secs;
  }

  if ($negative == 1) {
    return '- ' . $time_in_secs;
  } else {
    return $time_in_secs;
  }
}

sub to_duration_string {
    my ($duration_secs,$most_significant,$least_significant,$least_significant_decimals,$loc_code) = @_;
    $most_significant //= 'years';
    $least_significant //= 'seconds';

    my $abs = abs($duration_secs);
    my ($years,$months,$days,$hours,$minutes,$seconds);
    my $result = '';
    if ('seconds' ne $least_significant) {
        $abs = $abs / 60.0; #minutes
        if ('minutes' ne $least_significant) {
            $abs = $abs / 60.0; #hours
            if ('hours' ne $least_significant) {
                $abs = $abs / 24.0; #days
                if ('days' ne $least_significant) {
                    $abs = $abs / 30.0; #months
                    if ('months' ne $least_significant) {
                        $abs = $abs / 12.0; #years
                        if ('years' ne $least_significant) {
                            die("unknown least significant duration unit-of-time: '$least_significant'");
                        } else {
                            $seconds = 0.0;
                            $minutes = 0.0;
                            $hours = 0.0;
                            $days = 0.0;
                            $months = 0.0;
                            if ('years' eq $most_significant) {
                                $years = $abs;
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    } else {
                        $seconds = 0.0;
                        $minutes = 0.0;
                        $hours = 0.0;
                        $days = 0.0;
                        $years = 0.0;
                        if ('months' eq $most_significant) {
                            $months = $abs;
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                } else {
                    $seconds = 0.0;
                    $minutes = 0.0;
                    $hours = 0.0;
                    $months = 0.0;
                    $years = 0.0;
                    if ('days' eq $most_significant) {
                        $days = $abs;
                    } else {
                        $days = ($abs >= 30.0) ? fmod($abs,30.0) : $abs;
                        $abs = $abs / 30.0;
                        if ('months' eq $most_significant) {
                            $months = floor($abs);
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                }
            } else {
                $seconds = 0.0;
                $minutes = 0.0;
                $days = 0.0;
                $months = 0.0;
                $years = 0.0;
                if ('hours' eq $most_significant) {
                    $hours = $abs;
                } else {
                    $hours = ($abs >= 24.0) ? fmod($abs,24.0) : $abs;
                    $abs = $abs / 24.0;
                    if ('days' eq $most_significant) {
                        $days = floor($abs);
                    } else {
                        $days = ($abs >= 30.0) ? fmod($abs,30) : $abs;
                        $abs = $abs / 30.0;
                        if ('months' eq $most_significant) {
                            $months = floor($abs);
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                }
            }
        } else {
            $seconds = 0.0;
            $hours = 0.0;
            $days = 0.0;
            $months = 0.0;
            $years = 0.0;
            if ('minutes' eq $most_significant) {
                $minutes = $abs;
            } else {
                $minutes = ($abs >= 60.0) ? fmod($abs,60.0) : $abs;
                $abs = $abs / 60.0;
                if ('hours' eq $most_significant) {
                    $hours = floor($abs);
                } else {
                    $hours = ($abs >= 24.0) ? fmod($abs,24.0) : $abs;
                    $abs = $abs / 24.0;
                    if ('days' eq $most_significant) {
                        $days = floor($abs);
                    } else {
                        $days = ($abs >= 30.0) ? fmod($abs,30.0) : $abs;
                        $abs = $abs / 30.0;
                        if ('months' eq $most_significant) {
                            $months = floor($abs);
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                }
            }
        }
    } else {
        $minutes = 0.0;
        $hours = 0.0;
        $days = 0.0;
        $months = 0.0;
        $years = 0.0;
        if ('seconds' eq $most_significant) {
            $seconds = $abs;
        } else {
            $seconds = ($abs >= 60.0) ? fmod($abs,60.0) : $abs;
            $abs = $abs / 60.0;
            if ('minutes' eq $most_significant) {
                $minutes = floor($abs);
            } else {
                $minutes = ($abs >= 60.0) ? fmod($abs,60.0) : $abs;
                $abs = $abs / 60.0;
                if ('hours' eq $most_significant) {
                    $hours = floor($abs);
                } else {
                    $hours = ($abs >= 24.0) ? fmod($abs,24.0) : $abs;
                    $abs = $abs / 24.0;
                    if ('days' eq $most_significant) {
                        $days = floor($abs);
                    } else {
                        $days = ($abs >= 30.0) ? fmod($abs,30.0) : $abs;
                        $abs = $abs / 30.0;
                        if ('minutes' eq $most_significant) {
                            $months = floor($abs);
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                }
            }
        }
    }
    if ($years > 0.0) {
        if ($months > 0.0 || $days > 0.0 || $hours > 0.0 || $minutes > 0.0 || $seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$years, 0, 'years');
        } else {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$years, $least_significant_decimals, 'years');
        }
    }
    if ($months > 0.0) {
        if ($years > 0.0) {
            $result .= ', ';
        }
        if ($days > 0.0 || $hours > 0.0 || $minutes > 0.0 || $seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$months, 0, 'months');
        } else {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$months, $least_significant_decimals, 'months');
        }
    }
    if ($days > 0.0) {
        if ($years > 0.0 || $months > 0.0) {
            $result .= ', ';
        }
        if ($hours > 0.0 || $minutes > 0.0 || $seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$days, 0, 'days');
        } else {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$days, $least_significant_decimals, 'days');
        }
    }
    if ($hours > 0.0) {
        if ($years > 0.0 || $months > 0.0 || $days > 0.0) {
            $result .= ', ';
        }
        if ($minutes > 0.0 || $seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$hours, 0, 'hours');
        } else {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$hours, $least_significant_decimals, 'hours');
        }
    }
    if ($minutes > 0.0) {
        if ($years > 0.0 || $months > 0.0 || $days > 0.0 || $hours > 0.0) {
            $result .= ', ';
        }
        if ($seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$minutes, 0, 'minutes');
        } else {
            $result .= _duration_unit_of_time_value_to_string($loc_code,$minutes, $least_significant_decimals, 'minutes');
        }
    }
    if ($seconds > 0.0) {
        if ($years > 0.0 || $months > 0.0 || $days > 0.0 || $hours > 0.0 || $minutes > 0.0) {
            $result .= ', ';
        }
        $result .= _duration_unit_of_time_value_to_string($loc_code,$seconds, $least_significant_decimals, 'seconds');
    }
    if (length($result) == 0) {
        $result .= _duration_unit_of_time_value_to_string($loc_code,0.0, $least_significant_decimals, $least_significant);
    }
    return ($result,$years,$months,$days,$hours,$minutes,$seconds);
}

sub _duration_unit_of_time_value_to_string {
    my ($loc_code,$value, $decimals, $unit_of_time) = @_;
    my $result = '';
    my $unit_label_plural = '';
    my $unit_label_singular = '';
    if (defined $loc_code) {
        if ('seconds' eq $unit_of_time) {
            $unit_label_plural = ' ' . &$loc_code('seconds');
            $unit_label_singular = ' ' . &$loc_code("second");
        } elsif ('minutes' eq $unit_of_time) {
            $unit_label_plural = ' ' . &$loc_code('minutes');
            $unit_label_singular = ' ' . &$loc_code("minute");
        } elsif ('hours' eq $unit_of_time) {
            $unit_label_plural = ' ' . &$loc_code('hours');
            $unit_label_singular = ' ' . &$loc_code("hour");
        } elsif ('days' eq $unit_of_time) {
            $unit_label_plural = ' ' . &$loc_code('days');
            $unit_label_singular = ' ' . &$loc_code("day");
        } elsif ('months' eq $unit_of_time) {
            $unit_label_plural = ' ' . &$loc_code('months');
            $unit_label_singular = ' ' . &$loc_code("month");
        } elsif ('years' eq $unit_of_time) {
            $unit_label_plural = ' ' . &$loc_code('years');
            $unit_label_singular = ' ' . &$loc_code("year");
        }
    }
    if ($decimals < 1) {
        if (int($value) == 1) {
            $result .= '1';
            $result .= $unit_label_singular;
        } else {
            $result .= int($value);
            $result .= $unit_label_plural;
        }
    } else {
        $result .= sprintf('%.' . $decimals . 'f', $value);
        $result .= $unit_label_plural;
    }
    return $result;
}

sub get_cpucount {
    my $cpucount = 0;
    if ($can_cpu_affinity) {
        $cpucount = eval { Sys::CpuAffinity::getNumCpus() + 0; };
    }
    return ($cpucount > 0) ? $cpucount : 1;
}

sub prompt {
  my ($query) = @_; # take a prompt string as argument
  local $| = 1; # activate autoflush to immediately show the prompt
  print $query;
  chomp(my $answer = <STDIN>);
  return $answer;
}

sub check_int {
    my $val = shift;
    if($val =~ /^[+-]?[0-9]+$/) {
        return 1;
    }
    return 0;
}

sub shell_args {
    my @commandandargs = @_;
    if ($^O eq 'MSWin32') {
        unshift(@commandandargs,'cmd /C');
        push(@commandandargs,'>nul');
    }
    return @commandandargs;
}

sub run {

    my (@commandandargs) = @_;

    system(@commandandargs);

    my $command = shift @commandandargs;

    if ($? == -1) {
        return (0,'failed to execute ' . $command . ': ' . $!);
    } elsif ($? & 127) {
        return (0,sprintf($command . ' died with signal %d, %s dump', ($? & 127), ($? & 128) ? 'with' : 'without'));
    } else {
        if ($? == 0) {
            return (1,sprintf($command . ' exited with value %d', $? >> 8));
        } else {
            return (0,sprintf($command . ' exited with value %d', $? >> 8));
        }
    }

}

#https://www.perlmonks.org/?node_id=590619
sub checkrunning {

    my ($lockfile,$errorcode,$logger) = @_;
    if (not open (LOCKFILE, '>' . $lockfile)) {
      if (defined $errorcode and ref $errorcode eq 'CODE') {
        return &$errorcode('cannot open file ' . $lockfile . ': ' . $!,$logger);
      }
      return 0;
    } else {
      unless (flock(LOCKFILE, LOCK_EX|LOCK_NB)) {
        return &$errorcode('program already running',$logger);
      }
      return 1;
    }

}

sub unshare {

    # PP deep-copy without tie-ing, to un-share shared datastructures,
    # so they can be manipulated without errors
    my ($obj) = @_;
    return undef if not defined $obj; # terminal for: undefined
    my $ref = ref $obj;
    if (not $ref) { # terminal for: scalar
        return $obj;
    } elsif ("SCALAR" eq $ref) { # terminal for: scalar ref
        $obj = $$obj;
        return \$obj;
    } elsif ("ARRAY" eq $ref) { # terminal for: array
        my @array = ();
        foreach my $value (@$obj) {
           push(@array, unshare($value));
        }
        return \@array;
    } elsif ($ref eq "HASH") { # terminal for: hash
        my %hash = ();
        foreach my $key (keys %$obj) {
            $hash{$key} = unshare($obj->{$key});
        }
        return \%hash;
    } elsif ("REF" eq $ref) { # terminal for: ref of scalar ref, array, hash etc.
        $obj = unshare($$obj);
        return \$obj;
    } else {
        die("unsharing $ref not supported\n");
    }

}

sub load_module {
    my $package_element = shift;
    eval {
        (my $module = $package_element) =~ s/::[a-zA-Z_0-9]+$//g;
        (my $file = $module) =~ s|::|/|g;
        require $file . '.pm';
        #$module->import();
        1;
    } or do {
        die($@);
    };
}

1;
