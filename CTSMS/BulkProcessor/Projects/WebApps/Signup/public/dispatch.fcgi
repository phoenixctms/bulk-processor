#!/usr/bin/perl
use Dancer ':syntax';
use FindBin '$RealBin';
use Plack::Handler::FCGI;

# For some reason Apache SetEnv directives don't propagate
# correctly to the dispatchers, so forcing PSGI and env here
# is safer

set apphandler => 'PSGI';
set environment => 'production';

my $psgi = path($RealBin, '..', 'app.pl');
my $app = do($psgi);
die "Unable to read startup script: $@" if $@;
# processes are spawned and managed by mod_fcgid (STDIN is its socket), so no nproc or daemonize here
my $server = Plack::Handler::FCGI->new();

$server->run($app);
