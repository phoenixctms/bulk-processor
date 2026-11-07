package CTSMS::BulkProcessor::Projects::ETL::ExportFiles;
use strict;

## no critic

use File::Basename qw();
use Digest::MD5 qw();
use Encode qw();

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    processing_info
);
use CTSMS::BulkProcessor::LogError qw(
    fileerror
);

use CTSMS::BulkProcessor::Utils qw(timestampdigits makepath);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    get_export_file_value
    get_export_file_count
    publish_export_files
);

# the files of exported FILE values, to publish them along with the export. each file gets an
# entry path "<proband id>/<column name>/<file name>", with the column name of the value in the
# horizontal export. it is the path in the zip, and the logical path + file name when uploading the
# files individually. the exported value of a FILE column is "<entry path> (<md5>)".

my $zipextension = '.zip';
my $zipmimetype = 'application/zip';

my %export_files = (); # entry path -> file
my %export_file_paths = (); # value -> entry path

sub get_export_file_value {
    # registers the file of an exported FILE value and returns the column value, '' if no file is stored.
    my ($value,$value_type,$proband_id,$colname,$download_code) = @_;
    my $file = $value->{fileValue};
    return '' unless (defined $file and defined $value->{id});
    my $value_key = $value_type . ':' . $value->{id};
    my $path = $export_file_paths{$value_key};
    unless (defined $path) {
        my $dir = _sanitize_path_segment($proband_id) . '/' . _sanitize_path_segment($colname);
        my $file_name = _sanitize_path_segment($file->{fileName});
        $path = $dir . '/' . $file_name;
        # column name collision:
        $path = $dir . '_' . $value->{id} . '/' . $file_name if exists $export_files{$path};
        $export_file_paths{$value_key} = $path;
        $export_files{$path} = {
            path => $path,
            value_id => $value->{id},
            download_code => $download_code,
            file_name => $file_name,
            content_type => (defined $file->{contentType} ? $file->{contentType}->{mimeType} : undef),
            md5 => $file->{md5},
            size => $file->{size},
        };
    }
    return $path . ' (' . ($file->{md5} // '') . ')';
}

sub get_export_file_count {
    return scalar keys %export_files;
}

sub publish_export_files {
    # downloads the registered files and stores them as one zip or individually. returns the uploads
    # ([ $out, $localfile, $filename, $mimetype ]) and the messages of files that could not be added.
    # dies if the zip cannot be written or uploaded. the registered files are cleared.
    my %params = @_;
    my ($output_path,$upload_files,$zip,$zip_filename,$timestamp_suffix,$subfolder,$get_file_in_code) = @params{qw/
        output_path
        upload_files
        zip
        zip_filename
        timestamp_suffix
        subfolder
        get_file_in_code
    /};
    my @uploads = ();
    my @errors = ();
    my $fatal;
    my @paths = sort keys %export_files;
    return (\@uploads,\@errors) unless scalar @paths;

    my $timestamp_digits = timestampdigits() . ($timestamp_suffix // '');
    my $download_dir = $output_path . 'files_' . $timestamp_digits . '/';
    makepath($download_dir,\&fileerror,getlogger(__PACKAGE__));

    my @downloads = ();
    my $i = 0;
    foreach my $path (@paths) {
        my $export_file = $export_files{$path};
        my $localfile = $download_dir . $i++;
        eval {
            my $res = &{$export_file->{download_code}}($export_file->{value_id});
            die("no file content\n") unless ($res and defined $res->content_ref);
            my $md5 = Digest::MD5::md5_hex(${$res->content_ref});
            push(@errors,"- file '$path': downloaded file MD5 $md5 differs from the exported MD5 $export_file->{md5}")
                if (defined $export_file->{md5} and length($export_file->{md5}) > 0 and $md5 ne lc($export_file->{md5}));
            open(my $fh,'>',$localfile) or die("cannot create $localfile: $!\n");
            binmode($fh);
            print $fh ${$res->content_ref};
            close($fh);
            push(@downloads,[ $export_file, $localfile ]);
            processing_info(undef,"file '$path' downloaded",getlogger(__PACKAGE__));
        };
        if (my $err = $@) {
            chomp($err);
            push(@errors,"- file '$path' could not be downloaded: $err");
        }
    }

    if ($zip) {
        if (scalar @downloads) {
            my $filename = sprintf($zip_filename,$timestamp_digits,$zipextension);
            my $outputfile = $output_path . $filename;
            require Archive::Zip;
            my $archive = Archive::Zip->new();
            foreach my $download (@downloads) {
                my ($export_file,$localfile) = @$download;
                my $member = $archive->addFile($localfile,Encode::encode_utf8($export_file->{path}));
                $member->desiredCompressionMethod(Archive::Zip::COMPRESSION_DEFLATED());
            }
            # utf-8 entry names: the bitFlag accessor adds the language encoding flag (0x0800) with
            # $Archive::Zip::UNICODE. not set when adding the members, as it maps their names to local paths on win32.
            my $status;
            {
                local $Archive::Zip::UNICODE = 1;
                # the local file headers use the stored flags:
                $_->bitFlag() foreach $archive->members();
                $status = $archive->writeToFileNamed($outputfile);
            }
            if ($status == Archive::Zip::AZ_OK()) {
                processing_info(undef,(scalar @downloads) . " file(s) zipped to $filename",getlogger(__PACKAGE__));
                if ($upload_files) {
                    my $out = eval {
                        CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(&$get_file_in_code($filename,$subfolder),
                            $outputfile,$filename,$zipmimetype);
                    };
                    if (my $err = $@) {
                        chomp($err);
                        $fatal = "file '$filename' could not be uploaded: $err";
                    } elsif ($out) {
                        push(@uploads,[ $out,$outputfile,$filename,$zipmimetype ]);
                    }
                }
            } else {
                $fatal = "file '$filename' could not be written";
            }
        }
    } elsif ($upload_files) {
        foreach my $download (@downloads) {
            my ($export_file,$localfile) = @$download;
            my $folder = $subfolder . $timestamp_digits . '/' . File::Basename::dirname($export_file->{path}) . '/';
            my $out = eval {
                CTSMS::BulkProcessor::RestRequests::ctsms::shared::FileService::File::upload(&$get_file_in_code($export_file->{file_name},$folder),
                    $localfile,$export_file->{file_name},$export_file->{content_type});
            };
            if (my $err = $@) {
                chomp($err);
                push(@errors,"- file '$export_file->{path}' could not be uploaded: $err");
            } elsif ($out) {
                push(@uploads,[ $out,$localfile,$export_file->{file_name},$export_file->{content_type} ]);
            }
        }
    }

    foreach my $download (@downloads) {
        unlink($download->[1]);
    }
    rmdir($download_dir);

    # a later publication only gets the files registered after this one
    %export_files = ();
    %export_file_paths = ();

    die($fatal . "\n") if defined $fatal;
    return (\@uploads,\@errors);
}

sub _sanitize_path_segment {
    my ($segment) = @_;
    $segment //= '';
    $segment =~ s/[\x00-\x1f\x7f\/\\:*?"<>|]/_/g;
    $segment =~ s/^\s+|\s+$//g;
    $segment = '_' . $segment if $segment =~ /^\.*$/;
    return $segment;
}

1;
