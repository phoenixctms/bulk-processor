package CTSMS::BulkProcessor::Projects::ETL::EcrfSettings;
use strict;

## no critic

use utf8;

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
);

use CTSMS::BulkProcessor::LoadConfig qw(
    split_tuple
    parse_regexp
);

use CTSMS::BulkProcessor::ConnectorPool qw(
    get_ctsms_restapi

);

use CTSMS::BulkProcessor::Utils qw(format_number prompt chopstring cat_file);


use CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings
    update_job

    $input_path
    $output_path
    $sqlite_db_file
    $csv_dir

    $skip_errors

    $ecrf_data_truncate_table
    $ecrf_data_ignore_duplicates
    $ecrf_data_trial_id
    $job_id
    @job_file

    $ecrf_data_api_listentries_page_size
    $ecrf_data_api_ecrfs_page_size
    $ecrf_data_api_values_page_size
    $ecrf_data_row_block
    $ecrf_data_api_tagvalues_page_size
    $ecrf_data_api_ecrffields_page_size

    $ecrf_data_listentrytags

    %export_colname_abbreviation
    $col_per_selection_set_value
    $selection_set_value_separator
    ecrf_data_include_ecrffield
    $ecrf_data_export_upload_folder
    $ecrf_data_export_sqlite_filename
    $ecrf_data_export_horizontal_csv_filename
    $ecrf_data_export_xls_filename
    $ecrf_data_export_xlsx

    $audit_trail_export_xls_filename
    $ecrf_journal_export_xls_filename
    $ecrfs_export_xls_filename

    $ctsms_base_url
    $dbtool
    $lockfile
    $ecrf_data_export_pdf_filename
    $ecrf_data_export_pdfs_filename

    $proband_list_filename

);

our $input_path = $working_path . 'input/';
our $output_path = $working_path . 'output/';

our $sqlite_db_file = 'ecrf';
our $csv_dir = 'ecrf';

our $skip_errors = 0;

our $ecrf_data_truncate_table = 1;
our $ecrf_data_ignore_duplicates = 0;
our $ecrf_data_trial_id = undef;
our $job_id = undef;
my $job = undef;
our @job_file = ();

our $ecrf_data_api_listentries_page_size = 10;
our $ecrf_data_api_ecrfs_page_size  = 10;
our $ecrf_data_api_values_page_size = 10;
our $ecrf_data_row_block = 100;
our $ecrf_data_api_tagvalues_page_size = 10;
our $ecrf_data_api_ecrffields_page_size = 100;

our $ecrf_data_listentrytags = {};

our $ecrf_data_export_upload_folder = '';
our $ecrf_data_export_sqlite_filename = '%s%s';
our $ecrf_data_export_horizontal_csv_filename = '%s%s';
our $ecrf_data_export_xls_filename = '%s%s';
our $ecrf_data_export_xlsx = 0;

our $audit_trail_export_xls_filename = "%s%s";
our $ecrf_journal_export_xls_filename = "%s%s";
our $ecrfs_export_xls_filename = "%s%s";

our $ctsms_base_url = undef;
our $dbtool = undef;
our $lockfile = undef;
our $ecrf_data_export_pdf_filename = '%s%s';
our $ecrf_data_export_pdfs_filename = '%s_%s%s';

our $proband_list_filename = '%s_%s%s';

my $ecrfname_abbreviate_opts = {};
my $visit_abbreviate_opts = {};
my $group_abbreviate_opts = {};
my $section_abbreviate_opts = {};
my $inputfieldname_abbreviate_opts = {};
my $selectionvalue_abbreviate_opts = {};

our $col_per_selection_set_value = 1;
our $selection_set_value_separator = ',';

my $ecrf_data_include_ecrffield_code = sub {
    my ($ecrffield) = @_;
    return 1;
};

our %export_colname_abbreviation = (
    ignore_external_ids => undef,
    ecrf_position_digits => 2,
    ecrffield_position_digits => 2,
    index_digits => 2,
    abbreviate_ecrf_name_code => sub {
        my ($ecrf_name,$ecrf_id) = @_;
        $ecrf_name = abbreviate(string => $ecrf_name, %$ecrfname_abbreviate_opts);

        return $ecrf_name;
    },
    abbreviate_visit_code => sub {
        my ($token,$title,$id) = @_;
        $token = abbreviate(string => $token, %$visit_abbreviate_opts);
        return $token;
    },
    abbreviate_group_code => sub {
        my ($token,$title,$id) = @_;
        $token = abbreviate(string => $token, %$group_abbreviate_opts);
        return $token;
    },
    abbreviate_section_code => sub {
        my $section = shift;

        $section = abbreviate(string => $section, %$section_abbreviate_opts);
        return $section;
    },
    abbreviate_inputfield_name_code => sub {
        my ($inputfield_name,$inputfield_id) = @_;
        $inputfield_name = abbreviate(string => $inputfield_name, %$inputfieldname_abbreviate_opts);
        return $inputfield_name;
    },
    abbreviate_selectionvalue_code => sub {
        my ($selectionvalue_value,$selectionvalue_id) = @_;
        $selectionvalue_value = abbreviate(string => $selectionvalue_value, %$selectionvalue_abbreviate_opts);
        return 'o' . $selectionvalue_value;
    },
    sanitize_colname_symbols_code => sub {
        my $colname = shift;
        $colname =~ s/ä/ae/g;
        $colname =~ s/ö/oe/g;
        $colname =~ s/ü/ue/g;
        $colname =~ s/ß/ss/g;
        $colname =~ s/Ä/Ae/g;
        $colname =~ s/Ö/Oe/g;
        $colname =~ s/Ü/Ue/g;
        $colname =~ s/µ/u/g;
        $colname =~ s/<=/le/g;
        $colname =~ s/>=/ge/g;
        $colname =~ s/</lt/g;
        $colname =~ s/>/gt/g;
        $colname =~ s/=/eq/g;
        return $colname;
    },
);

sub abbreviate {
    my %params = @_;
    my ($string,
        $limit, #abreviate only if total length > limit
        $word_count_limit, # abbreviate only if more than x words
        $word_abbreviation_length, #truncate words to 3 chars
        $word_limit, #if the word length > 5 chars
        $word_blacklist) = @params{qw/
            string
            limit
            word_count_limit
            word_abbreviation_length
            word_limit
            word_blacklist
    /};

    $limit //= 1;
    $word_count_limit //= 2;
    $word_abbreviation_length //= 3;
    $word_limit //= $word_abbreviation_length + 2;
    $word_blacklist = {} unless 'HASH' eq ref $word_blacklist;
    return $string if length($string) <= $limit;
    $string =~ s/[^a-zA-Z0-9 <>=äöüÄÖÜß_-]//g;
    $string =~ s/[ _-]+/ /g;
    my @words = grep { local $_ = $_; (not exists $word_blacklist->{$_}) or (not $word_blacklist->{$_}); } split(/ /,$string,-1);
    return join(' ',@words) if (scalar grep { local $_ = $_; length($_) > $word_abbreviation_length; } @words) <= $word_count_limit;
    my @abbreviated_words = ();
    foreach my $word (@words) {
        push(@abbreviated_words,(length($word) > $word_limit ? chopstring($word,$word_abbreviation_length,'') : $word));
    }
    return join(' ',@abbreviated_words);
}

sub ecrf_data_include_ecrffield {
    return &$ecrf_data_include_ecrffield_code(shift);
}

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;

        $result &= _prepare_working_paths(1);

        $sqlite_db_file = $data->{sqlite_db_file} if exists $data->{sqlite_db_file};
        $csv_dir = $data->{csv_dir} if exists $data->{csv_dir};

        $skip_errors = $data->{skip_errors} if exists $data->{skip_errors};

        $ecrf_data_truncate_table = $data->{ecrf_data_truncate_table} if exists $data->{ecrf_data_truncate_table};
        $ecrf_data_ignore_duplicates = $data->{ecrf_data_ignore_duplicates} if exists $data->{ecrf_data_ignore_duplicates};

        $ecrf_data_trial_id = $data->{ecrf_data_trial_id} if exists $data->{ecrf_data_trial_id};
        if (defined $ecrf_data_trial_id and length($ecrf_data_trial_id) > 0) {
            my $ecrf_data_trial = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($ecrf_data_trial_id);
            configurationerror($configfile,"error loading trial id $ecrf_data_trial_id",getlogger(__PACKAGE__)) unless defined $ecrf_data_trial;
        }
        $job_id = $data->{job_id} if exists $data->{job_id};
        if (defined $job_id and length($job_id) > 0) {
            $job = CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job::get_item($job_id);
            configurationerror($configfile,"error loading job id $job_id",getlogger(__PACKAGE__)) unless defined $job;
            $completionemailrecipient = $job->{emailRecipients};
        }

        $ecrf_data_api_listentries_page_size = $data->{ecrf_data_api_listentries_page_size} if exists $data->{ecrf_data_api_listentries_page_size};
        $ecrf_data_api_ecrfs_page_size = $data->{ecrf_data_api_ecrfs_page_size} if exists $data->{ecrf_data_api_ecrfs_page_size};
        $ecrf_data_api_values_page_size = $data->{ecrf_data_api_values_page_size} if exists $data->{ecrf_data_api_values_page_size};

        $ecrf_data_row_block = $data->{ecrf_data_row_block} if exists $data->{ecrf_data_row_block};

        $ecrf_data_api_tagvalues_page_size = $data->{ecrf_data_api_tagvalues_page_size} if exists $data->{ecrf_data_api_tagvalues_page_size};
        $ecrf_data_api_ecrffields_page_size = $data->{ecrf_data_api_ecrffields_page_size} if exists $data->{ecrf_data_api_ecrffields_page_size};

        $ecrf_data_listentrytags = $data->{ecrf_data_listentrytags} if exists $data->{ecrf_data_listentrytags};

        $ecrf_data_export_upload_folder = $data->{ecrf_data_export_upload_folder} if exists $data->{ecrf_data_export_upload_folder};

        $ecrf_data_export_sqlite_filename = $data->{ecrf_data_export_sqlite_filename} if exists $data->{ecrf_data_export_sqlite_filename};
        $ecrf_data_export_horizontal_csv_filename = $data->{ecrf_data_export_horizontal_csv_filename} if exists $data->{ecrf_data_export_horizontal_csv_filename};
        $ecrf_data_export_xls_filename = $data->{ecrf_data_export_xls_filename} if exists $data->{ecrf_data_export_xls_filename};
        $ecrf_data_export_xlsx = $data->{ecrf_data_export_xlsx} if exists $data->{ecrf_data_export_xlsx};

        $col_per_selection_set_value = $data->{col_per_selection_set_value} if exists $data->{col_per_selection_set_value};
        $selection_set_value_separator = $data->{selection_set_value_separator} if exists $data->{selection_set_value_separator};
        $selection_set_value_separator //= '';

        if (exists $data->{ecrf_data_include_ecrffield_code}) {
            if ('CODE' eq ref $data->{ecrf_data_include_ecrffield_code}) {
                $ecrf_data_include_ecrffield_code = $data->{ecrf_data_include_ecrffield_code};
            } else {
                configurationerror($configfile,"perl code reference required for ecrf_data_include_ecrffield_code",getlogger(__PACKAGE__));
            }
        }

        $ctsms_base_url = $data->{ctsms_base_uri} if exists $data->{ctsms_base_uri};
        $ctsms_base_url = _get_ctsms_baseuri() unless $ctsms_base_url;
        $dbtool = $data->{dbtool} if exists $data->{dbtool};
        $lockfile = $data->{lockfile} if exists $data->{lockfile};
        $ecrf_data_export_pdf_filename = $data->{ecrf_data_export_pdf_filename} if exists $data->{ecrf_data_export_pdf_filename};
        $ecrf_data_export_pdfs_filename = $data->{ecrf_data_export_pdfs_filename} if exists $data->{ecrf_data_export_pdfs_filename};

        $proband_list_filename = $data->{proband_list_filename} if exists $data->{proband_list_filename};

        $audit_trail_export_xls_filename = $data->{audit_trail_export_xls_filename} if exists $data->{audit_trail_export_xls_filename};
        $ecrf_journal_export_xls_filename = $data->{ecrf_journal_export_xls_filename} if exists $data->{ecrf_journal_export_xls_filename};
        $ecrfs_export_xls_filename = $data->{ecrfs_export_xls_filename} if exists $data->{ecrfs_export_xls_filename};

        $export_colname_abbreviation{ignore_external_ids} = $data->{ignore_external_ids} if exists $data->{ignore_external_ids};
        $ecrfname_abbreviate_opts = $data->{ecrfname_abbreviate_opts} if exists $data->{ecrfname_abbreviate_opts};
        $inputfieldname_abbreviate_opts = $data->{inputfieldname_abbreviate_opts} if exists $data->{inputfieldname_abbreviate_opts};
        $selectionvalue_abbreviate_opts = $data->{selectionvalue_abbreviate_opts} if exists $data->{selectionvalue_abbreviate_opts};

        $visit_abbreviate_opts = $data->{visit_abbreviate_opts} if exists $data->{visit_abbreviate_opts};
        $group_abbreviate_opts = $data->{group_abbreviate_opts} if exists $data->{group_abbreviate_opts};
        $section_abbreviate_opts = $data->{section_abbreviate_opts} if exists $data->{section_abbreviate_opts};

        return $result;

    }
    return 0;

}

sub update_job {

    my ($status) = @_;
    if (defined $job) {
        my $in = {
            id => $job->{id},
            version => $job->{version},
            status => $status,
            jobOutput => cat_file($attachmentlogfile,\&fileerror,getlogger(__PACKAGE__)),
        };

        my @args = ($in);
        push(@args,@job_file) if $job->{type}->{outputFile};

        $job = CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job::update_item(@args);
    }

}

sub _prepare_working_paths {

    my ($create) = @_;
    my $result = 1;
    my $path_result;

    ($path_result,$input_path) = create_path($working_path . 'input',$input_path,$create,\&fileerror,getlogger(__PACKAGE__));
    $result &= $path_result;
    ($path_result,$output_path) = create_path($working_path . 'output',$output_path,$create,\&fileerror,getlogger(__PACKAGE__));
    $result &= $path_result;

    return $result;

}

sub _get_ctsms_baseuri {
    my $api = get_ctsms_restapi();
    my $path = $api->path // '';
    $path =~ s!/*$ctsmsrestapi_path/*$!!;

        $path .= '/' if $path !~ m!/$!;

    my $uri = $api->baseuri;
    $uri->path_query($path);
    return $uri->as_string();
}

1;
