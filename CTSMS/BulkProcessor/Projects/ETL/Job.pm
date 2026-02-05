package CTSMS::BulkProcessor::Projects::ETL::Job;
use strict;

## no critic

use threads qw();
use threads::shared qw(shared_clone);

use CTSMS::BulkProcessor::Globals qw(
    $working_path
    $enablemultithreading
    $cpucount
    create_path
    $ctsmsrestapi_path
    $completionemailrecipient
);

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    scriptinfo
    configurationinfo
    $attachmentlogfile
);

use CTSMS::BulkProcessor::LogError qw(
    fileerror
    configurationwarn
    configurationerror
    scriptwarn
    scripterror
    $cli
);

use CTSMS::BulkProcessor::Utils qw(cat_file);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_job
    update_settings

    $job_id
    @job_file
);

our $job_id = undef;
my %job :shared = ();
our @job_file = ();


sub update_settings {

    my ($data,$configfile,%params) = @_;

    my ($input_path) = @params{qw/
        input_path
    /};

    if (defined $data) {
        my $result = 1;

        $job_id = $data->{job_id} if exists $data->{job_id};
        if (defined $job_id and length($job_id) > 0) {
            lock %job;
            sleep 2; #the database record might no exist yet, so wait
            $cli = 0;
            _set_job(CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job::get_item($job_id, { _file => 1, }));
            if (keys %job) {
                scriptinfo("job '$job{type}->{name}' id $job_id",getlogger(__PACKAGE__));
                _download_job_file($input_path) if $job{type}->{inputFile};
            } else {
                scripterror("error loading job id $job_id",getlogger(__PACKAGE__));
                $result = 0;
            }
            $completionemailrecipient = $job{emailRecipients};
        }

        return $result;
    }
    return 0;

}

sub _set_job {
    my $obj = shift;
    $obj //= {};
    delete @job{keys %job};
    @job{keys %$obj} = map { shared_clone($_); } values %$obj;
}

sub update_job {

    my ($status,$progress,$progress_max) = @_;
    lock %job;
    if (keys %job) {
        my $in = {
            id => $job{id},
            version => $job{version},
            status => $status,
            jobOutput => cat_file($attachmentlogfile,\&fileerror,getlogger(__PACKAGE__)),
            progress => (defined $progress ? $progress : $job{progress}),
            progressMax => (defined $progress_max ? $progress_max : $job{progressMax}),
        };

        my @args = ($in);
        if ($job{type}->{outputFile}
            or ($job{hasFile} and $job{type}->{inputFile})) {
            push(@args,@job_file);
        } else {
            push(@args,undef,undef,undef);
        }
        push(@args, { _file => 1, });

        _set_job(CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job::update_item(@args));
    }

}

sub _download_job_file {

    my ($input_path) = @_;
    @job_file = ();
    lock %job;
    if (keys %job) {
        unless ($job{hasFile}) {
            scripterror("job has no file",getlogger(__PACKAGE__));
            return;
        }
        unless ($job{_file}->{decrypted}) {
            scripterror("job file is not decrypted",getlogger(__PACKAGE__));
            return;
        }
        my ($file,$filename,$content_type) = ($input_path . $job{_file}->{fileName}, $job{_file}->{fileName}, $job{_file}->{contentType}->{mimeType});
        unlink $file;
        scriptinfo("downloading job input file to $file",getlogger(__PACKAGE__));
        my $lwp_response = CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job::download_job_file($job{id});
        my $out;
        unless (open($out, '>', $file)) {
            fileerror("Unable to open: $!",getlogger(__PACKAGE__));
            return;
        }
        binmode($out);
        print $out $lwp_response->content;
        close($out);
        @job_file = (
            $file,
            $filename,
            $content_type,
        );
    }

}

1;