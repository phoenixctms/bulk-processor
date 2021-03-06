package CTSMS::BulkProcessor::ServiceProxy;
use strict;

## no critic

use threads qw(yield);
use threads::shared;
use Thread::Queue;

use Time::HiRes qw(sleep);

use CTSMS::BulkProcessor::Globals qw(
    @jobservers
    $jobnamespace
);

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    servicedebug
    serviceinfo
);
use CTSMS::BulkProcessor::LogError qw(
    serviceerror
    servicewarn
    notimplementederror
);

use CTSMS::BulkProcessor::Utils qw(threadid);
use CTSMS::BulkProcessor::Serialization qw(serialize deserialize);
use Encode qw(encode_utf8);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(new_async_do new_do);



use Gearman::Client;




use Gearman::Task;

my $timeout_secs_default = 0;

my $retry_count_default = 0;
my $high_priority_default = 0;

my $block_destroy_default = 1;

my $poll_interval_secs = 0.1;

my $instance_count = 0;

sub new {

    my $class = shift;
    my $self = bless {}, $class;
    my ($serialization_format,$timeout_secs,$block_destroy) = @_;

    $self->{serialization_format} = $serialization_format;
    $self->{client} = undef;

    $self->{timeout_secs} = ((defined $timeout_secs) ? $timeout_secs : $timeout_secs_default);

    $self->{retry_count} = $retry_count_default;
    $self->{high_priority} = $high_priority_default;

    $self->{block_destroy} = ((defined $block_destroy) ? $block_destroy : $block_destroy_default);

    $self->{arg} = undef;

    $self->{ret} = undef;
    $self->{function} = undef;

    $self->{exception} = undef;
    $self->{on_error} = undef;

    $self->{on_complete} = undef;
    $self->{on_fail} = undef;
    $self->{on_status} = undef;

    my $async_running = 0;
    $self->{async_running_ref} = share($async_running);
    $self->{thread} = undef;
    $self->{create_tid} = threadid();
    $self->{tid} = $self->{create_tid};
    $self->{wait_tid} = undef;
    $self->{queue} = undef;

    $self->{instance} = $instance_count;
    $instance_count++;




    servicedebug($self,'service proxy created, job servers ' . join(',',@jobservers),getlogger(__PACKAGE__));

    return $self;

}

sub identifier {
    my $self = shift;
    return '(' . $self->{instance} . ') ' . (length($self->{function}) > 0 ? '\'' . $self->{function} . '\'' : __PACKAGE__);
}

sub new_async_do {




    my $proxy = __PACKAGE__->new();
    if ($proxy->do_async(@_)) {
        return $proxy;
    }
    return undef;
}
sub new_do {




    my $proxy = __PACKAGE__->new();
    return $proxy->do(@_);
}

sub do_async {
    my $self = shift;
    my ($function_name,$on_complete,$on_error,@args) = @_;

    if ($self->_check_async_running($on_error,'do_async \'' . $function_name . '\' failed because do_async \'' . $self->{function} . '\' is waiting',1)) {
        return 0;
    }

    $self->{client} = undef;

    $self->{function} = $function_name;
    $self->{ret} = undef;
    $self->{exception} = undef;






    $self->{on_error} = $on_error;
    $self->{on_complete} = $on_complete;
    $self->{on_fail} = undef;
    $self->{on_status} = undef;

    my $arg = serialize(\@args,$self->{serialization_format});
    $self->{arg} = \$arg;


        $self->{queue} = Thread::Queue->new();


    servicedebug($self,'start waiting do_async \'' . $function_name . '\', args length: ' . length(encode_utf8($arg)),getlogger(__PACKAGE__));
    $self->{thread} = threads->create(\&_wait_thread,

                                          { proxy                => $self,

                                          }

                                          );



    return 1;
}

sub _get_task_opts {
    my $self = shift;
    return {
                       on_complete => undef,
                       on_fail => undef,
                       on_retry => undef,
                       on_status => undef,
                       on_exception => undef,
                       retry_count => $self->{retry_count},
                       high_priority => $self->{high_priority},

                       };
}

sub _wait_thread {

    my $context = shift;


    my $proxy = $context->{proxy};

    $proxy->{wait_tid} = threadid();
    $proxy->{tid} = $proxy->{wait_tid};
    servicedebug($proxy,'wait thread tid ' . $proxy->{tid} . ' started',getlogger(__PACKAGE__));
    my $async_running_ref = $proxy->{async_running_ref};

    my $task_opts = $proxy->_get_task_opts();
    $task_opts->{on_complete} = sub { $proxy->_on_complete(@_); };
    $task_opts->{on_fail} = sub { $proxy->_on_fail(@_); };
    $task_opts->{on_retry} = sub { $proxy->_on_retry(@_); };
    $task_opts->{on_status} = sub { $proxy->_on_status(@_); };
    $task_opts->{on_exception} = sub { $proxy->_on_exception(@_); };

    $proxy->{client} = Gearman::Client->new(( job_servers => \@jobservers,
                                             prefix => $jobnamespace,
                                             exceptions => 1));

    my $task = Gearman::Task->new($proxy->{function}, $proxy->{arg}, $task_opts);
    if ($proxy->{timeout_secs} > 0) {
        $task->timeout($proxy->{timeout_secs});
    }


    my $task_set = $proxy->{client}->new_task_set();

    $task_set->add_task($task);

    local $SIG{'KILL'} = sub {
        servicedebug($proxy,'kill signal received, exiting wait thread tid ' . $proxy->{tid} . ' ...',getlogger(__PACKAGE__));




        threads->exit();

    };

    servicedebug($proxy,'start waiting (do_async) ...',getlogger(__PACKAGE__));
    $task_set->wait(timeout => $task->timeout);

    {
        lock $async_running_ref;
        $$async_running_ref = 0;
    }

    servicedebug($proxy,'shutting down wait thread tid ' . $proxy->{tid} . ' ...',getlogger(__PACKAGE__));

}

sub do {
    my $self = shift;
    my ($function_name,$on_error,@args) = @_;

    if ($self->_check_async_running($on_error,'do \'' . $function_name . '\' failed because do_async \'' . $self->{function} . '\' is waiting',0)) {
        return undef;
    }

    $self->{function} = $function_name;
    $self->{ret} = undef;
    $self->{exception} = undef;







    $self->{on_error} = $on_error;
    $self->{on_complete} = undef;
    $self->{on_fail} = undef;
    $self->{on_status} = undef;

    my $arg = serialize(\@args,$self->{serialization_format});
    $self->{arg} = \$arg;

    my $task_opts = $self->_get_task_opts();
    $task_opts->{on_complete} = sub { $self->_on_complete(@_); };
    $task_opts->{on_fail} = sub { $self->_on_fail(@_); };
    $task_opts->{on_retry} = sub { $self->_on_retry(@_); };
    $task_opts->{on_status} = sub { $self->_on_status(@_); };
    $task_opts->{on_exception} = sub { $self->_on_exception(@_); };

    $self->{client} = Gearman::Client->new(( job_servers => \@jobservers,
                                             prefix => $jobnamespace,
                                             exceptions => 1));

    my $task = Gearman::Task->new($function_name, \$arg, $task_opts);

    if ($self->{timeout_secs} > 0) {
        $task->timeout($self->{timeout_secs});
    }

    my $task_set = $self->{client}->new_task_set();

    $task_set->add_task($task);

    servicedebug($self,'start waiting do \'' . $function_name . '\', args length: ' . length(encode_utf8($arg)),getlogger(__PACKAGE__));
    $task_set->wait(timeout => $task->timeout);
    return wantarray ? @{$self->{ret}} : $self->{ret}->[0];

}

sub _enqueue_event {
    my $self = shift;
    my ($event,$args) = @_;
    my $packet = {event     => $event,
                    args     => $args};
    $self->{queue}->enqueue($packet);
    servicedebug($self,'event ' . $event . ' enqueued, ' . $self->{queue}->pending() . ' event(s) pending',getlogger(__PACKAGE__));
}

sub _on_complete  {
    my $self = shift;
    my $result_ref = shift;
    if ($self->_is_wait_thread()) {
        $self->_enqueue_event('_on_complete',[$result_ref]);
    } elsif ($self->_is_create_thread()) {
        my $result = $$result_ref;
        $self->{ret} = deserialize($result,$self->{serialization_format});
        servicedebug($self,'on_complete event received, result length: ' . length(encode_utf8($result)),getlogger(__PACKAGE__));
        if (defined $self->{on_complete} and ref $self->{on_complete} eq 'CODE') {
            &{$self->{on_complete}}(@{$self->{ret}});
        }
    }


}

sub _on_fail {
    my $self = shift;
    if ($self->_is_wait_thread()) {
        $self->_enqueue_event('_on_fail');
    } elsif ($self->_is_create_thread()) {
        servicedebug($self,'on_fail event received',getlogger(__PACKAGE__));
        if (defined $self->{on_fail} and ref $self->{on_fail} eq 'CODE') {
            &{$self->{on_fail}}();
        }
    }
}

sub _on_retry {
    my $self = shift;
    if ($self->_is_wait_thread()) {
        $self->_enqueue_event('_on_retry');
    } elsif ($self->_is_create_thread()) {
        servicedebug($self,'on_retry event received',getlogger(__PACKAGE__));
        if (defined $self->{on_retry} and ref $self->{on_retry} eq 'CODE') {
            &{$self->{on_retry}}();
        }
    }
}

sub _on_status {
    my $self = shift;
    my ($numerator, $denominator) = @_;
    if ($self->_is_wait_thread()) {
        $self->_enqueue_event('_on_status',[$numerator, $denominator]);
    } elsif ($self->_is_create_thread()) {
        servicedebug($self,'on_status event received: ' . $numerator . '/' . $denominator,getlogger(__PACKAGE__));
        if (defined $self->{on_status} and ref $self->{on_status} eq 'CODE') {
            &{$self->{on_status}}($numerator, $denominator);
        }
    }
}

sub _on_exception {
    my $self = shift;
    my $exception = shift;
    $self->{exception} = $exception;
    if ($self->_is_wait_thread()) {
        $self->_enqueue_event('_on_exception',[$exception]);

    } elsif ($self->_is_create_thread()) {
        if (defined $self->{on_error} and ref $self->{on_error} eq 'CODE') {
            servicedebug($self,'on_exception event received: ' . $exception,getlogger(__PACKAGE__));
            &{$self->{on_error}}($exception);
        } else {
            servicewarn($self,'on_exception event received: ' . $exception,getlogger(__PACKAGE__));
        }
    }
}

sub _check_async_running {
    my $self = shift;
    my ($on_error,$message,$async_running) = @_;
    if ($self->_is_create_thread()) {
        my $async_running_ref = $self->{async_running_ref};
        lock $async_running_ref;
        if ($$async_running_ref) {
            if (defined $on_error and ref $on_error eq 'CODE') {
                servicedebug($self,$message,getlogger(__PACKAGE__));
                &$on_error($message);
            } elsif (length($message) > 0) {
                servicewarn($self,$message,getlogger(__PACKAGE__));
            }
            return 1;
        } elsif ($async_running) {
            $$async_running_ref = 1;
        }


    }
    return 0;
}

sub _get_stop_wait_thread {
    my $self = shift;
    my $timeout_secs = shift;
    my $async_running;
    {
        my $async_running_ref = $self->{async_running_ref};
        lock $async_running_ref;
        $async_running = $$async_running_ref;
    }
    if ((not $async_running and $self->{queue}->pending() == 0) or (defined $timeout_secs and $timeout_secs <= 0)) {
        servicedebug($self,'stop waiting now (' .
                 ($async_running ? 'wait thread running' : 'wait thread not running') .', '.
                 $self->{queue}->pending() . ' event(s) queued, ' .
                 ((defined $timeout_secs) ? 'timeout in ' . sprintf('%.1f',$timeout_secs) . 'secs' : 'no timeout') . ')'
                 ,getlogger(__PACKAGE__));
        return 1;
    }
    return 0;
}

sub wait {
    my $self = shift;
    my $timeout_secs = shift;
    if ($self->_is_create_thread()) {
            while (not $self->_get_stop_wait_thread($timeout_secs)) {
                my $packet = $self->{queue}->dequeue_nb();
                if (defined $packet) {
                    my $event = $packet->{event};
                    servicedebug($self,'event ' . $event . ' dequeued, ' . $self->{queue}->pending() . ' event(s) pending',getlogger(__PACKAGE__));
                    $self->$event(@{$packet->{args}});
                    yield();
                } else {
                    if (defined $timeout_secs) {
                        $timeout_secs -= $poll_interval_secs;
                    }
                    sleep $poll_interval_secs;
                }
            }
            my $killtread = 0;
            {
                my $async_running_ref = $self->{async_running_ref};
                lock $async_running_ref;
                $killtread = ($$async_running_ref and (defined $timeout_secs and $timeout_secs <= 0));
                if ($killtread) {
                    servicedebug($self,'wait timeout exceeded (' . sprintf('%.1f',$timeout_secs) . '), killing wait thread ...',getlogger(__PACKAGE__));
                    $self->{thread}->kill('KILL')->detach();
                    $$async_running_ref = 0;
                }
            }
            if (not $killtread) {
                $self->{thread}->join();
                servicedebug($self,'wait thread joined',getlogger(__PACKAGE__));
            }









            $self->{queue} = undef;
            $self->{thread} = undef;
            $self->{wait_tid} = undef;














    }
}

sub DESTROY {

    my $self = shift;
    if ($self->_is_create_thread()) {
        servicedebug($self,'destroying proxy ...',getlogger(__PACKAGE__));
        if ($self->{block_destroy}) {
            $self->wait($self->{timeout_secs} > 0 ? $self->{timeout_secs} : undef);
        } else {
            $self->_check_async_running(undef,'do_async \'' . $self->{function} . '\' is still waiting');
        }
        servicedebug($self,'proxy destroyed',getlogger(__PACKAGE__));
    }
}

sub _is_wait_thread {
    my $self = shift;
    return (defined $self->{wait_tid} and $self->{wait_tid} == threadid());
}

sub _is_create_thread {
    my $self = shift;
    return $self->{create_tid} == threadid();
}

1;
