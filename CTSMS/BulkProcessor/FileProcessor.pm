package CTSMS::BulkProcessor::FileProcessor;
use strict;

## no critic

use threads qw(yield);
use threads::shared qw(shared_clone);
use Thread::Queue;

use utf8;

use Time::HiRes qw(sleep);
use File::Basename qw(basename);

use CTSMS::BulkProcessor::Globals qw(
    $enablemultithreading
    $cpucount
    get_threadqueuelength
);
use CTSMS::BulkProcessor::Logging qw(
    getlogger
    filethreadingdebug
    fileprocessingstarted
    fileprocessingdone
    lines_read
    processing_lines
);

use CTSMS::BulkProcessor::LogError qw(
    processzerofilesize
    fileprocessingfailed
    fileerror
    notimplementederror
    fileprocessingwarn
);

use CTSMS::BulkProcessor::Utils qw(threadid);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(

    create_process_context

    get_other_threads_state
    $RUNNING
    $COMPLETED
    $ERROR

    $thread_sleep_secs
);

our $thread_sleep_secs = 0.1;

our $RUNNING = 1;
our $COMPLETED = 2;
our $ERROR = 4;

my $default_blocksize = 100;
my $default_numofthreads = 3;

my $buffersize = 100 * 1024;
my $threadqueuelength = 10;

sub new {

    my $class = shift;
    my $self = bless {}, $class;

    my %params = @_;
    ($self->{numofthreads},
     $self->{blocksize}) = @params{qw(
        numofthreads
        blocksize
    )};
    $self->{numofthreads} //= $default_numofthreads;
    $self->{blocksize} //= $default_blocksize;

    $self->{encoding} = undef;
    $self->{buffersize} = $buffersize;
    $self->{threadqueuelength} = $threadqueuelength;

    $self->{line_separator} = undef;

    return $self;

}

sub init_reader_context {

    my $self = shift;
    my ($context) = @_;
    # init stuff available to the reader loop
    # invoked after thread was forked, as
    # required by e.g. Marpa R2

}

sub _extractlines {
    my ($context,$buffer_ref,$lines) = @_;
    my $separator = $context->{instance}->{line_separator};
    my $last_line;
    foreach my $line (split(/$separator/,$$buffer_ref,-1)) {
        $last_line = $line;
        push(@$lines,$line);
    }
    $$buffer_ref = $last_line;
    pop @$lines;

    return 1;
}

sub process {

    my $self = shift;

    my %params = @_;
    my @opts = qw/
        file
        process_code
        static_context
        init_process_context_code
        uninit_process_context_code
        multithreading
    /;
    my ($file,
        $process_code,
        $static_context,
        $init_process_context_code,
        $uninit_process_context_code,
        $multithreading) = @params{@opts};
    delete @params{@opts};

    my $files_code = $file;
    my $single_file = 1;
    $single_file = 0 if ('CODE' eq ref $file);
    $files_code = sub {
        my ($context,$cb) = @_;
        $cb->($file);
    } if $single_file;

    if (ref $process_code eq 'CODE') {

        my $errorstate = $RUNNING;
        my $tid = threadid();

        if ($enablemultithreading and $multithreading and $cpucount > 1) {

            my $reader;
            my %processors = ();
            my %errorstates :shared = ();
            my $queue = Thread::Queue->new();

            filethreadingdebug('starting reader thread',getlogger(__PACKAGE__));

            $reader = threads->create(\&_reader,
                                          { %params,
                                            queue                => $queue,
                                            errorstates          => \%errorstates,
                                            instance             => $self,
                                            files_code           => $files_code,
                                            single_file          => $single_file,
                                          });

            for (my $i = 0; $i < $self->{numofthreads}; $i++) {
                filethreadingdebug('starting processor thread ' . ($i + 1) . ' of ' . $self->{numofthreads},getlogger(__PACKAGE__));
                my $processor = threads->create(\&_process,
                                              create_process_context($static_context,
                                              { %params,
                                                queue                       => $queue,
                                                errorstates                 => \%errorstates,
                                                readertid                   => $reader->tid(),
                                                process_code                => $process_code,
                                                single_file                 => $single_file,
                                                init_process_context_code   => $init_process_context_code,
                                                uninit_process_context_code => $uninit_process_context_code,
                                                instance                    => $self,
                                              }));
                if (!defined $processor) {
                    filethreadingdebug('processor thread ' . ($i + 1) . ' of ' . $self->{numofthreads} . ' NOT started',getlogger(__PACKAGE__));
                }
                $processors{$processor->tid()} = $processor;
            }

            $reader->join();
            filethreadingdebug('reader thread joined',getlogger(__PACKAGE__));
            while ((scalar keys %processors) > 0) {
                foreach my $processor (values %processors) {
                    if (defined $processor and $processor->is_joinable()) {
                        $processor->join();
                        delete $processors{$processor->tid()};
                        filethreadingdebug('processor thread tid ' . $processor->tid() . ' joined',getlogger(__PACKAGE__));
                    }
                }
                sleep($thread_sleep_secs);
            }

            $errorstate = (get_other_threads_state(\%errorstates,$tid) & ~$RUNNING);

        } else {

            my $context = create_process_context($static_context,{
                %params,
                instance => $self,
                tid      => $tid,
            });
            my $filename;
            eval {

                if (defined $init_process_context_code and 'CODE' eq ref $init_process_context_code) {
                    &$init_process_context_code($context);
                }
                my $read_and_process_code = $self->can('read_and_process');
                if (defined $read_and_process_code) {
                    $files_code->($context,sub {
                        $filename = shift;
                        $context->{filename} = $filename;

                        if (-s $filename > 0) {
                            fileprocessingstarted($filename,getlogger(__PACKAGE__));
                        } else {
                            if ($single_file) {
                                processzerofilesize($filename,getlogger(__PACKAGE__));
                            } else {
                                fileprocessingwarn($filename,basename($filename) . ' ' . (-e $filename ? 'has 0 bytes' : 'not found'),getlogger(__PACKAGE__));
                            }
                            return;
                        }

                        my $init_reader_context_code = $self->can('init_reader_context');
                        if (defined $init_reader_context_code) {
                            &$init_reader_context_code($self,$context);
                        }
                        my $rowblock_result = &$read_and_process_code($self,$context,$process_code);
                        fileprocessingdone($filename,getlogger(__PACKAGE__));
                    });
                } else {
                    my $extractlines_code = (ref $self)->can('extractlines');
                    if (!defined $extractlines_code) {
                        if (defined $self->{line_separator}) {
                            $extractlines_code = \&_extractlines;
                        } else {
                            notimplementederror((ref $self) . ': ' . 'extractlines class method not implemented and line separator pattern not defined',getlogger(__PACKAGE__));
                        }
                    }
                    my $extractfields_code = (ref $self)->can('extractfields');
                    if (!defined $extractfields_code) {
                        notimplementederror((ref $self) . ': ' . 'extractfields class method not implemented',getlogger(__PACKAGE__));
                    }

                    $files_code->($context,sub {
                        $filename = shift;

                        if (-s $filename > 0) {
                            fileprocessingstarted($filename,getlogger(__PACKAGE__));
                        } else {
                            if ($single_file) {
                                processzerofilesize($filename,getlogger(__PACKAGE__));
                            } else {
                                fileprocessingwarn($filename,basename($filename) . ' ' . (-e $filename ? 'has 0 bytes' : 'not found'),getlogger(__PACKAGE__));
                            }
                            return;
                        }

                        $context->{filename} = $filename;
                        my $init_reader_context_code = $self->can('init_reader_context');
                        if (defined $init_reader_context_code) {
                            &$init_reader_context_code($self,$context);
                        }

                        local *INPUTFILE;
                        if (not open (INPUTFILE, '<:encoding(' . $self->{encoding} . ')', $filename)) {
                            fileerror('processing file - cannot open file ' . $filename . ': ' . $!,getlogger(__PACKAGE__));
                            return;
                        }
                        binmode INPUTFILE;

                        my $buffer = undef;
                        my $chunk = undef;
                        my $n = 0;
                        $context->{charsread} = 0;
                        $context->{linesread} = 0;

                        my $i = 0;
                        my $rowblock_result = 1;
                        while (1) {
                            my $block_n = 0;
                            my @lines = ();
                            while ((scalar @lines) < $self->{blocksize} and defined ($n = read(INPUTFILE,$chunk,$self->{buffersize})) and $n != 0) {
                                if (defined $buffer) {
                                    $buffer .= $chunk;
                                } else {
                                    $buffer = $chunk;
                                }
                                $context->{charsread} += $n;
                                $block_n += $n;
                                last unless &$extractlines_code($context,\$buffer,\@lines);
                            }
                            lines_read($filename,$i,$self->{blocksize},$block_n,getlogger(__PACKAGE__));

                            if (not defined $n) {
                                fileerror('processing file - error reading file ' . $filename . ': ' . $!,getlogger(__PACKAGE__));
                                close(INPUTFILE);
                                last;
                            } else {
                                if ($n == 0 && defined $buffer) {
                                    push(@lines,$buffer);
                                }
                                my @rowblock = ();
                                foreach my $line (@lines) {
                                    $context->{linesread} += 1;
                                    my $row = &$extractfields_code($context,(ref $line ? $line : \$line));
                                    if (exists $row->[0] and 'ARRAY' eq ref $row->[0]) {
                                        foreach (@$row) {
                                            push(@rowblock,$_) if defined $_;
                                        }
                                    } else {
                                        push(@rowblock,$row) if defined $row;
                                    }
                                }
                                my $realblocksize = scalar @rowblock;
                                if ($realblocksize > 0) {
                                    processing_lines($tid,$i,$realblocksize,undef,getlogger(__PACKAGE__));

                                    $rowblock_result = &$process_code($context,\@rowblock,$i);

                                    $i += $realblocksize;
                                    if ($n == 0 || not $rowblock_result) {
                                        last;
                                    }
                                } else {
                                    last;
                                }
                            }
                        }
                        close(INPUTFILE);

                        fileprocessingdone($filename,getlogger(__PACKAGE__));

                    });
                }

            };

            if ($@) {
                $errorstate = $ERROR;
            } else {
                $errorstate = $COMPLETED;
            }

            eval {
                if (defined $uninit_process_context_code and 'CODE' eq ref $uninit_process_context_code) {
                    &$uninit_process_context_code($context);
                }
            };

            unless ($errorstate == $COMPLETED) {
                fileprocessingfailed($filename,getlogger(__PACKAGE__));
            }
        }

        if ($errorstate == $COMPLETED) {
            return 1;
        }

    }

    return 0;

}

sub _reader {

    my $context = shift;

    my $tid = threadid();
    $context->{tid} = $tid;
    {
        lock $context->{errorstates};
        $context->{errorstates}->{$tid} = $RUNNING;
    }

    filethreadingdebug('[' . $tid . '] reader thread tid ' . $tid . ' started',getlogger(__PACKAGE__));

    my $blockcount = 0;
    my $filename;
    eval {

        my $read_code = $context->{instance}->can('read');
        if (defined $read_code) {
            $context->{files_code}->($context,sub {
                $filename = shift;
                if (-s $filename > 0) {
                    fileprocessingstarted($filename,getlogger(__PACKAGE__));
                } else {
                    if ($context->{single_file}) {
                        processzerofilesize($filename,getlogger(__PACKAGE__));
                    } else {
                        fileprocessingwarn($filename,basename($filename) . ' ' . (-e $filename ? 'has 0 bytes' : 'not found'),getlogger(__PACKAGE__));
                    }
                    return;
                }
                $context->{filename} = $filename;
                my $init_reader_context_code = $context->{instance}->can('init_reader_context');
                if (defined $init_reader_context_code) {
                    &$init_reader_context_code($context->{instance},$context);
                }
                my $state = &$read_code($context->{instance},$context);
                if (not (($state & $RUNNING) == $RUNNING and ($state & $ERROR) == 0)) {
                    filethreadingdebug('[' . $tid . '] reader thread is shutting down (' .
                                      (($state & $RUNNING) == $RUNNING ? 'still running consumer threads' : 'no running consumer threads') . ', ' .
                                      (($state & $ERROR) == 0 ? 'no defunct thread(s)' : 'defunct thread(s)') . ') ...'
                    ,getlogger(__PACKAGE__));
                }

                fileprocessingdone($filename,getlogger(__PACKAGE__));
            });
        } else {
            my $extractlines_code = (ref $context->{instance})->can('extractlines');
            if (!defined $extractlines_code) {
                if (defined $context->{instance}->{line_separator}) {
                    $extractlines_code = \&_extractlines;
                } else {
                    notimplementederror((ref $context->{instance}) . ': ' . 'extractlines class method not implemented and line separator pattern not defined',getlogger(__PACKAGE__));
                }
            }

            my $extractfields_code = (ref $context->{instance})->can('extractfields');
            if (!defined $extractfields_code) {
                notimplementederror((ref $context->{instance}) . ': ' . 'extractfields class method not implemented',getlogger(__PACKAGE__));
            }

            $context->{files_code}->($context,sub {
                $filename = shift;
                if (-s $filename > 0) {
                    fileprocessingstarted($filename,getlogger(__PACKAGE__));
                } else {
                    if ($context->{single_file}) {
                        processzerofilesize($filename,getlogger(__PACKAGE__));
                    } else {
                        fileprocessingwarn($filename,basename($filename) . ' ' . (-e $filename ? 'has 0 bytes' : 'not found'),getlogger(__PACKAGE__));
                    }
                    return;
                }

                $context->{filename} = $filename;
                my $init_reader_context_code = $context->{instance}->can('init_reader_context');
                if (defined $init_reader_context_code) {
                    &$init_reader_context_code($context->{instance},$context);
                }

                local *INPUTFILE_READER;
                if (not open (INPUTFILE_READER, '<:encoding(' . $context->{instance}->{encoding} . ')', $filename)) {
                    fileerror('processing file - cannot open file ' . $filename . ': ' . $!,getlogger(__PACKAGE__));
                    return;
                }
                binmode INPUTFILE_READER;

                filethreadingdebug('[' . $tid . '] reader thread waiting for consumer threads',getlogger(__PACKAGE__));
                while ((get_other_threads_state($context->{errorstates},$tid) & $RUNNING) == 0) { #wait on cosumers to come up
                    sleep($thread_sleep_secs);
                }

                my $buffer = undef;
                my $chunk = undef;
                my $n = 0;
                $context->{charsread} = 0;
                $context->{linesread} = 0;

                my $i = 0;
                my $state = $RUNNING; #start at first
                sleep(1); #wait for processors to come up
                while (($state & $RUNNING) == $RUNNING and ($state & $ERROR) == 0) { #as long there is one running consumer and no defunct consumer
                    my $block_n = 0;
                    my @lines = ();
                    while ((scalar @lines) < $context->{instance}->{blocksize} and defined ($n = read(INPUTFILE_READER,$chunk,$context->{instance}->{buffersize})) and $n != 0) {
                        if (defined $buffer) {
                            $buffer .= $chunk;
                        } else {
                            $buffer = $chunk;
                        }
                        $context->{charsread} += 1;
                        $block_n += $n;
                        last unless &$extractlines_code($context,\$buffer,\@lines);
                        yield();
                    }
                    lines_read($filename,$i,$context->{instance}->{blocksize},$block_n,getlogger(__PACKAGE__));
                    if (not defined $n) {
                        fileerror('processing file - error reading file ' . $filename . ': ' . $!,getlogger(__PACKAGE__));
                        close(INPUTFILE_READER);
                        last;
                    } else {
                        if ($n == 0 && defined $buffer) {
                            push(@lines,$buffer);
                        }
                        my @rowblock :shared = ();
                        foreach my $line (@lines) {
                            $context->{linesread} += 1;
                            my $row = &$extractfields_code($context,(ref $line ? $line : \$line));
                            if (exists $row->[0] and 'ARRAY' eq ref $row->[0]) {
                                foreach (@$row) {
                                    push(@rowblock,shared_clone($_)) if defined $_;
                                }
                            } else {
                                push(@rowblock,shared_clone($row)) if defined $row;
                            }
                            yield();
                        }
                        my $realblocksize = scalar @rowblock;
                        my %packet :shared = ();
                        $packet{rows} = \@rowblock;
                        $packet{size} = $realblocksize;
                        $packet{row_offset} = $i;
                        $packet{block_n} = $block_n;
                        if ($realblocksize > 0) {
                            $context->{queue}->enqueue(\%packet); #$packet);
                            $blockcount++;
                            #wait if thequeue is full and there there is one running consumer
                            while (((($state = get_other_threads_state($context->{errorstates},$tid)) & $RUNNING) == $RUNNING) and $context->{queue}->pending() >= get_threadqueuelength($context->{instance}->{threadqueuelength})) {
                                #yield();
                                sleep($thread_sleep_secs);
                            }
                            $i += $realblocksize;
                            if ($n == 0) {
                                filethreadingdebug('[' . $tid . '] reader thread is shutting down (end of data) ...',getlogger(__PACKAGE__));
                                last;
                            }
                        } else {
                            $context->{queue}->enqueue(\%packet); #$packet);
                            filethreadingdebug('[' . $tid . '] reader thread is shutting down (end of data - empty block) ...',getlogger(__PACKAGE__));
                            last;
                        }
                    }
                }
                if (not (($state & $RUNNING) == $RUNNING and ($state & $ERROR) == 0)) {
                    filethreadingdebug('[' . $tid . '] reader thread is shutting down (' .
                                      (($state & $RUNNING) == $RUNNING ? 'still running consumer threads' : 'no running consumer threads') . ', ' .
                                      (($state & $ERROR) == 0 ? 'no defunct thread(s)' : 'defunct thread(s)') . ') ...'
                    ,getlogger(__PACKAGE__));
                }
                close(INPUTFILE_READER);

                fileprocessingdone($filename,getlogger(__PACKAGE__));

            });
        }
    };

    filethreadingdebug($@ ? '[' . $tid . '] reader thread error: ' . $@ : '[' . $tid . '] reader thread finished (' . $blockcount . ' blocks)',getlogger(__PACKAGE__));
    lock $context->{errorstates};
    if ($@) {
        $context->{errorstates}->{$tid} = $ERROR;
        fileprocessingfailed($filename,getlogger(__PACKAGE__));
    } else {
        $context->{errorstates}->{$tid} = $COMPLETED;
    }
    return $context->{errorstates}->{$tid};
}

sub _process {

    my $context = shift;

    my $rowblock_result = 1;
    my $tid = threadid();
    $context->{tid} = $tid;
    {
        lock $context->{errorstates};
        $context->{errorstates}->{$tid} = $RUNNING;
    }

    filethreadingdebug('[' . $tid . '] processor thread tid ' . $tid . ' started',getlogger(__PACKAGE__));

    my $blockcount = 0;
    eval {
        if (defined $context->{init_process_context_code} and 'CODE' eq ref $context->{init_process_context_code}) {
            &{$context->{init_process_context_code}}($context);
        }
        while (not _get_stop_consumer_thread($context,$tid)) {
            my $packet = $context->{queue}->dequeue_nb();
            if (defined $packet) {
                if ($packet->{size} > 0) {

                    processing_lines($tid,$packet->{row_offset},$packet->{size},undef,getlogger(__PACKAGE__));

                    $rowblock_result = &{$context->{process_code}}($context, $packet->{rows},$packet->{row_offset});

                    $blockcount++;

                    if (not $rowblock_result) {
                        filethreadingdebug('[' . $tid . '] shutting down processor thread (processing block NOK) ...',getlogger(__PACKAGE__));
                        last;
                    }

                } elsif ($context->{single_file}) {
                    filethreadingdebug('[' . $tid . '] shutting down processor thread (end of data - empty block) ...',getlogger(__PACKAGE__));
                    last;
                } else {
                    sleep($thread_sleep_secs);
                }
            } else {
                sleep($thread_sleep_secs);
            }
        }
    };
    my $err = $@;
    filethreadingdebug($err ? '[' . $tid . '] processor thread error: ' . $err : '[' . $tid . '] processor thread finished (' . $blockcount . ' blocks)',getlogger(__PACKAGE__));
    eval {
        if (defined $context->{uninit_process_context_code} and 'CODE' eq ref $context->{uninit_process_context_code}) {
            &{$context->{uninit_process_context_code}}($context);
        }
    };
    lock $context->{errorstates};
    if ($err) {
        $context->{errorstates}->{$tid} = $ERROR;
    } else {
        $context->{errorstates}->{$tid} = $COMPLETED; #(not $rowblock_result) ? $ERROR : $COMPLETED;
    }
    return $context->{errorstates}->{$tid};
}

sub get_other_threads_state {
    my ($errorstates,$tid) = @_;
    my $result = 0;
    if (!defined $tid) {
        $tid = threadid();
    }
    if (defined $errorstates and ref $errorstates eq 'HASH') {
        lock $errorstates;
        foreach my $threadid (keys %$errorstates) {
            if ($threadid != $tid) {
                $result |= $errorstates->{$threadid};
            }
        }
    }
    return $result;
}

sub _get_stop_consumer_thread {
    my ($context,$tid) = @_;
    my $result = 1;
    my $other_threads_state;
    my $reader_state;
    my $queuesize;
    {
        my $errorstates = $context->{errorstates};
        lock $errorstates;
        $other_threads_state = get_other_threads_state($errorstates,$tid);
        $reader_state = $errorstates->{$context->{readertid}};
    }
    $queuesize = $context->{queue}->pending();
    if (($other_threads_state & $ERROR) == 0 and ($queuesize > 0 or $reader_state == $RUNNING)) {
        $result = 0;
        #keep the consumer thread running if there is no defunct thread and queue is not empty or reader is still running
    }

    if ($result) {
        filethreadingdebug('[' . $tid . '] consumer thread is shutting down (' .
                            (($other_threads_state & $ERROR) == 0 ? 'no defunct thread(s)' : 'defunct thread(s)') . ', ' .
                            ($queuesize > 0 ? 'blocks pending' : 'no blocks pending') . ', ' .
                            ($reader_state == $RUNNING ? 'reader thread running' : 'reader thread not running') . ') ...'
        ,getlogger(__PACKAGE__));
    }

    return $result;

}

sub create_process_context {

    my $context = {};
    foreach my $ctx (@_) {
        if (defined $ctx and 'HASH' eq ref $ctx) {
            foreach my $key (keys %$ctx) {
                $context->{$key} = $ctx->{$key};
                #delete $ctx->{$key};
            }
        }
    }
    return $context;

}

1;
