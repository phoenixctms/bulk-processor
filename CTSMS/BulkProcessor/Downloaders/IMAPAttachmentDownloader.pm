package CTSMS::BulkProcessor::Downloaders::IMAPAttachmentDownloader;
use strict;

## no critic

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    attachmentdownloaderdebug
    attachmentdownloaderinfo
);
use CTSMS::BulkProcessor::LogError qw(
    fileerror
    attachmentdownloadererror
    attachmentdownloaderwarn
);

use CTSMS::BulkProcessor::Utils qw(kbytes2gigs);

use IO::Socket::SSL;
use Mail::IMAPClient;
use MIME::Base64;





require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::AttachmentDownloader);
our @EXPORT_OK = qw();



sub new {

    my $class = shift;
    my ($server,$ssl,$user,$pass,$foldername,$checkfilenamecode,$download_urls) = @_;
    my $self = CTSMS::BulkProcessor::AttachmentDownloader->new($class,$server,$ssl,$user,$pass,$foldername,$checkfilenamecode,$download_urls);
    attachmentdownloaderdebug('IMAP attachment downloader object created',getlogger(__PACKAGE__));
    return $self;

}

sub logout {
  my $self = shift;
  if (defined $self->{imap}) {
    if ($self->{imap}->logout()) {
        attachmentdownloaderinfo('IMAP logout successful',getlogger(__PACKAGE__));
    } else {
        attachmentdownloaderwarn($@,getlogger(__PACKAGE__));
    }
    $self->{imap} = undef;
  }
}

sub setup {

    my $self = shift;
    my ($server,$ssl,$user,$pass,$foldername,$checkfilenamecode,$download_urls) = @_;

    $self->logout();

    attachmentdownloaderdebug('IMAP attachment downloader setup - ' . $server . ($ssl ? ' (SSL)' : ''),getlogger(__PACKAGE__));

    $self->{server} = $server;
    $self->{ssl} = $ssl;
    $self->{foldername} = $foldername;

    $self->{checkfilenamecode} = $checkfilenamecode;

    $self->{download_urls} = $download_urls;

    #* OK The Microsoft Exchange IMAP4 service is ready.
    #a1 capability
    #* CAPABILITY IMAP4 IMAP4rev1 AUTH=NTLM AUTH=GSSAPI AUTH=PLAIN STARTTLS UIDPLUS CHILDREN IDLE NAMESPACE LITERAL+

    my %opts = (
                User => $user,
                Password => $pass,
        Uid      => 1,
        Peek     => 1,  # don't set \Seen flag)
        Debug    => 0,
        IgnoreSizeErrors => 1,
        Authmechanism  => 'LOGIN',

        );

    if ($ssl) {
        $opts{Socket} = IO::Socket::SSL->new(
                Proto    => 'tcp',
                PeerAddr => $server,
                PeerPort => 993,
              ) or attachmentdownloadererror($@,getlogger(__PACKAGE__));
    } else {
        $opts{Server} = $server;
    }

    my $imap = Mail::IMAPClient->new(%opts) or attachmentdownloadererror($@,getlogger(__PACKAGE__));
























    if ($@) {
        attachmentdownloadererror($@,getlogger(__PACKAGE__));
    } else {
        attachmentdownloaderinfo('IMAP login successful',getlogger(__PACKAGE__));
    }

    $imap->select($foldername) or attachmentdownloadererror('cannot select ' . $foldername . ': ' . $imap->LastError,getlogger(__PACKAGE__)); #'folder ' . $foldername . ' not found: '
    attachmentdownloaderdebug('folder ' . $foldername . ' selected',getlogger(__PACKAGE__));

    $self->{imap} = $imap;

}

sub download {

    my $self = shift;
    my $filedir = shift;

    my @files_saved = ();
    my $message_count = 0;

    if (defined $self->{imap}) {

        attachmentdownloaderinfo('searching messages from folder ' . $self->{foldername},getlogger(__PACKAGE__));

        my $found = 0;

        my $message_ids = $self->{imap}->search('ALL');
        if (defined $message_ids and ref $message_ids eq 'ARRAY') {
            foreach my $id (@$message_ids) {
                attachmentdownloadererror('invalid message id ' . $id,getlogger(__PACKAGE__)) unless $id =~ /\A\d+\z/;
                my $message_string = $self->{imap}->message_string($id) or attachmentdownloadererror($@,getlogger(__PACKAGE__));

                $found |= $self->_process_message($self->{imap}->subject($id),$message_string,$filedir,\@files_saved);
                $message_count++;

                if ($found) {
                    last;
                }
            }
        } else {
            if ($@) {
                attachmentdownloadererror($@,getlogger(__PACKAGE__));
            }
        }

        if (scalar @files_saved == 0) {
          attachmentdownloaderwarn('IMAP download complete - ' . $message_count . ' messages found, but no matching attachments saved',getlogger(__PACKAGE__));
        } else {
          attachmentdownloaderinfo('IMAP attachment download complete - ' . scalar @files_saved . ' files saved',getlogger(__PACKAGE__));
        }
    }

    return \@files_saved;

}

1;
