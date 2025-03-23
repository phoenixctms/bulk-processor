package CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor;
use strict;

## no critic

use threads qw(yield);
use threads::shared qw(shared_clone);

use CTSMS::BulkProcessor::Globals qw(
    get_threadqueuelength
);

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    lines_read
    processing_lines
    filethreadingdebug
);
#fileprocessingstarted
#fileprocessingdone
#lines_read

use CTSMS::BulkProcessor::LogError qw(
    notimplementederror
);
#fileprocessingfailed
#fileprocessingwarn
#fileerror

#use CTSMS::BulkProcessor::Utils qw(threadid);

use CTSMS::BulkProcessor::FileProcessor qw(
    get_other_threads_state

    $thread_sleep_secs

    $RUNNING
    $COMPLETED
    $ERROR
);

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::FileProcessor);
our @EXPORT_OK = qw();

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::FileProcessor->new(@_);

    bless($self,$class);

    return $self;

}

sub read_and_process {

    my $self = shift;
    my $context = shift;
    my $process_code = shift;

    my @rowblock = ();
    my $result = 1;
    my $i = 0;
    my $realblocksize = 0;

    while ($result and $self->has_next_row($context)) {
        my $row = $self->get_row($context);
        push(@rowblock,$row) if defined $row;
        $realblocksize = scalar @rowblock;
        if ($realblocksize >= $self->{blocksize}) {
            processing_lines($context->{tid},$i,$realblocksize,undef,getlogger(__PACKAGE__));
            $result &= &$process_code($context,\@rowblock,$i);
            $i += $realblocksize;
            @rowblock = ();
        }
    }
    processing_lines($context->{tid},$i,$realblocksize,undef,getlogger(__PACKAGE__));
    $result &= &$process_code($context,\@rowblock,$i);

    return $result;

}

sub read {

    my $self = shift;
    my $context = shift;

    my @rowblock = ();

    my $realblocksize = 0;

    my $i = 0;

    my $state = $RUNNING; #start at first
    sleep(1); #wait for processors to come up
    while (($state & $RUNNING) == $RUNNING and ($state & $ERROR) == 0 and $self->has_next_row($context)) { #as long there is one running consumer and no defunct consumer
        my $row = $self->get_row($context);
        push(@rowblock,$row) if defined $row;
        $realblocksize = scalar @rowblock;
        yield();
        if ($realblocksize >= $self->{blocksize}) {
            lines_read($context->{filename},$i,$realblocksize,undef,1,getlogger(__PACKAGE__));
            my %packet :shared = ();
            $packet{rows} = shared_clone(\@rowblock);
            $packet{size} = $realblocksize;
            $packet{row_offset} = $i;

            $context->{queue}->enqueue(\%packet);

            $i += $realblocksize;
            #processing_lines($context->{tid},$i,$self->{blocksize},undef,getlogger(__PACKAGE__));
            @rowblock = ();

            #wait if the queue is full and there there is one running consumer
            while (((($state = get_other_threads_state($context->{errorstates},$context->{tid})) & $RUNNING) == $RUNNING) and $context->{queue}->pending() >= get_threadqueuelength($context->{instance}->{threadqueuelength})) {
                sleep($thread_sleep_secs);
            }

        }

    }
    if (($state & $RUNNING) == $RUNNING and ($state & $ERROR) == 0) {
        #and $realblocksize > 0) {
        lines_read($context->{filename},$i,$realblocksize,undef,1,getlogger(__PACKAGE__));
        my %packet :shared = ();
        $packet{rows} = shared_clone(\@rowblock);
        $packet{size} = $realblocksize;
        $packet{row_offset} = $i;

        $context->{queue}->enqueue(\%packet);

        filethreadingdebug('[' . $context->{tid} . '] reader thread is shutting down (end of data) ...',getlogger(__PACKAGE__));
    }

    return $state;

}

sub has_next_row {

    my $self = shift;
    my $context = shift;

    notimplementederror((ref $self) . ': ' . (caller(0))[3] . ' not implemented',getlogger(__PACKAGE__));
    return undef;

}

sub get_row {

    my $self = shift;
    my $context = shift;

    notimplementederror((ref $self) . ': ' . (caller(0))[3] . ' not implemented',getlogger(__PACKAGE__));
    return undef;

}

sub get_sheet_names {

    my $self = shift;
    my $file = shift;

    notimplementederror((ref $self) . ': ' . (caller(0))[3] . ' not implemented',getlogger(__PACKAGE__));
    return undef;

}

1;