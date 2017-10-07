package CTSMS::BulkProcessor::Calendar;
use strict;

## no critic

use Time::Local qw(timelocal_nocheck);

use CTSMS::BulkProcessor::Utils qw(timestamp zerofill get_year timestamp_fromepochsecs);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    is_leapyear
    weekday_num
    weeks_of_year
    days_of_year
    days_of_month
    add_days
    date_delta
    datetime_delta
    split_date
    split_time
    split_datetime
    check_date
    check_time
);

my @daysofmonths = (31,28,31,30,31,30,31,31,30,31,30,31);

sub is_leapyear {

  my $year = shift;
  my $v = 0;
  if ($year % 4 == 0) {
    $v = 1;
  }
  if ($year % 100 == 0) {
    $v = 0;
  }
  if ($year % 400 == 0) {
    $v = 1;
  }
  return $v;

}

sub weekday_num {

  my ($year, $month, $day) = @_;
  my ($year1,$year2,$h1,$h2,$h3,$b,$f) = ();
  my $rmonth = $month;
  my $ryear = $year;
  if ($rmonth < 3) {
    $rmonth += 10;
    $ryear -= 1;
  } else {
    $rmonth -= 2;
  }
  $year1 = int($ryear / 100);
  $year2 = $ryear % 100;
  $h1 = int(($rmonth * 13 - 1) / 5);
  $h2 = int($year2 / 4);
  $h3 = int($year1 / 4);
  $b = $h1 + $h2 + $h3;
  $f = ($b + $year2 + $day - 2 * $year1) % 7;
  return $f;

}

sub weeks_of_year {

  my $year = shift;
  my $weeks = 52;
  if (weekday_num($year,1,1) == 4 or weekday_num($year,12,31) == 4) {
    $weeks++;
  }
  return $weeks;

}

sub days_of_year {

  my $year = shift;
  my $days = 365;
  if (is_leapyear($year)) {
    $days++;
  }
  return $days;

}

sub days_of_month {

  my ($month, $year) = @_;
  if ($month > 0  and $month <= 12) {
    if ($month == 2 and is_leapyear($year)) { # leapyear
      return 29;
    } else {
      return $daysofmonths[$month - 1];
    }
  } else {
    return 0;
  }

}

#sub split_date {
#
#  my $datestring = shift;
#  return split /-/,$datestring,3;
#
#}

sub check_time {

  my ($hour,$minute,$second) = @_;

  if ($hour =~ /[^0-9]/ or $minute =~ /[^0-9]/ or (defined $second and $second =~ /[^0-9]/)) {
    return (0,'invalid time');
  } elsif ($hour >= 24 or $hour < 0) {
    return (0,'invalid hour',$hour);
  } elsif ($minute >= 60 or $minute < 0) {
    return (0,'invalid minute',$minute);
  } elsif (defined $second and $second >= 60 or $second < 0) {
    return (0,'invalid second',$second);
  } else {
    return (1);
  }

}

sub check_date {

  my ($year,$month,$day) = @_;
  
  if ($year =~ /[^0-9]/ or $month =~ /[^0-9]/ or $day =~ /[^0-9]/) {
    return (0,'invalid date');
  } elsif ($month > 12 or $month <= 0) {
    return (0,'invalid month',$month);
  } elsif ($year < 1582) {
    return (0,'invalid year',$year);
  } elsif ($month < 10 and $year < 1582) { # 15.10.1582 Gregorian Day
    return (0,'invalid date');
  } elsif ($day > days_of_month($month,$year) or $day <= 0) {
    return (0,'invalid day',$day);
  } else {
    return (1);
  }

}

sub add_days {

  my ($year,$month,$day,$ads) = @_;

  #my ($year,$month,$day) = split_date($date);
  
  my $rday = $day;
  my $rmonth = $month;
  my $ryear = $year;

  my $result;

  if($ads >= 0) { # addition
    for (1 .. $ads) {
      # increment day, turn month forward:
      if ($rday < days_of_month($rmonth,$ryear)) {
        $rday++;
      } else {
        $rmonth++;
        $rday = 1;
      }
      # turn year forward:
      if ($rmonth > 12) {
        $rday = 1;
        $rmonth = 1;
        $ryear++;
      }
    }
  } else { # difference
    my $subs = -1 * $ads;
    for (1 .. $subs) {
      # decrement day, turn month backward
      if ($rday > 1) {
        $rday--;
      } else {
        $rmonth--;
        $rday = days_of_month($rmonth,$ryear);
      }
      # turn year backward:
      if ($rmonth < 1) {
        $rmonth = 12;
        $rday = days_of_month($rmonth,$ryear);
        $ryear--;
      }
    }
  }
  
  # check date since we could fall below Gregorian Day ...
  $result = $ryear . '-' . zerofill($rmonth,2) . '-' . zerofill($rday,2);
#  if (not check_date($result)) {
#    calendarerror('resulting date ' . $result . ' not supported');
#    return undef;
#  } else {
#    return $result;
#  }
}

sub date_delta {

  my ($date1,$date2) = @_;
  my ($year1,$month1,$day1) = split_date($date1);
  my ($year2,$month2,$day2) = split_date($date2);
  return int((timelocal_nocheck(0,0,0,$day2,$month2 - 1,$year2) - timelocal_nocheck(0,0,0,$day1,$month1 - 1,$year1)) / 86400);

}

sub datetime_delta {

  my ($datetime1,$datetime2) = @_;
  my ($date1,$time1) = split_datetime($datetime1);
  my ($date2,$time2) = split_datetime($datetime2);
  my ($year1,$month1,$day1) = split_date($date1);
  my ($year2,$month2,$day2) = split_date($date2);
  my ($hour1,$minute1,$second1) = split_time($time1);
  my ($hour2,$minute2,$second2) = split_time($time2);
  return int(timelocal_nocheck($second2,$minute2,$hour2,$day2,$month2 - 1,$year2) - timelocal_nocheck($second1,$minute1,$hour1,$day1,$month1 - 1,$year1));

}

sub split_date {

  my $datestring = shift;
  return split /-/,$datestring,3;

}

sub split_time {

  my $timestring = shift;
  return split /:/,$timestring,3;

}

sub split_datetime {

  my $timestampstring = shift;
  return split / /,$timestampstring,2;

}

1;