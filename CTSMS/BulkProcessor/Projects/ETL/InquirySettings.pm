package CTSMS::BulkProcessor::Projects::ETL::InquirySettings;
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
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings
    update_job
    get_proband_columns

    $input_path
    $output_path
    $sqlite_db_file
    $csv_dir

    $skip_errors

    $inquiry_data_truncate_table
    $inquiry_data_ignore_duplicates
    $inquiry_data_trial_id
    $job_id
    @job_file

    $active
    $active_signup

    $inquiry_data_truncate_table
    $inquiry_data_ignore_duplicates
    $inquiry_data_trial_id

    $inquiry_data_api_probands_page_size
    $inquiry_data_api_inquiries_page_size
    $inquiry_data_api_values_page_size
    $inquiry_data_row_block

    %colname_abbreviation
    inquiry_data_include_inquiry
    $col_per_selection_set_value
    $selection_set_value_separator

    $inquiry_data_export_upload_folder
    $inquiry_data_export_sqlite_filename
    $inquiry_data_export_horizontal_csv_filename
    $inquiry_data_export_xls_filename
    $inquiry_data_export_xlsx

    $inquiry_data_export_pdfs_filename

    $inquiry_proband_alias_column_name
    $inquiry_proband_category_column_name
    $inquiry_proband_department_column_name
    $inquiry_proband_gender_column_name

    $ctsms_base_url

    $lockfile

);

our $input_path = $working_path . 'input/';
our $output_path = $working_path . 'output/';

our $sqlite_db_file = 'inquiry';
our $csv_dir = 'inquiry';

our $skip_errors = 0;

our $inquiry_data_truncate_table = 1;
our $inquiry_data_ignore_duplicates = 0;
our $inquiry_data_trial_id = undef;
our $job_id = undef;
my $job = undef;
our @job_file = ();

our $inquiry_data_api_probands_page_size = 10;
our $inquiry_data_api_inquiries_page_size = 10;
our $inquiry_data_api_values_page_size = 10;
our $inquiry_data_row_block = 100;

our $inquiry_data_export_upload_folder = '';
our $inquiry_data_export_sqlite_filename = '%s%s';
our $inquiry_data_export_horizontal_csv_filename = '%s%s';
our $inquiry_data_export_xls_filename = '%s%s';
our $inquiry_data_export_xlsx = 0;

our $inquiry_proband_alias_column_name = 'alias';
our $inquiry_proband_category_column_name;
our $inquiry_proband_department_column_name;
our $inquiry_proband_gender_column_name;

our $ctsms_base_url = undef;

our $lockfile = undef;

our $inquiry_data_export_pdfs_filename = '%s_%s%s';

my $ecrfname_abbreviate_opts = {};


my $category_abbreviate_opts = {};
my $inputfieldname_abbreviate_opts = {};
my $selectionvalue_abbreviate_opts = {};

our $col_per_selection_set_value = 1;
our $selection_set_value_separator = ',';

my $inquiry_data_include_inquiry_code = sub {
    my ($inquiry) = @_;
    return 1;
};

our %colname_abbreviation = (
    ignore_external_ids => undef,

    inquiry_position_digits => 2,


    abbreviate_category_code => sub {
        my $category = shift;

        $category = abbreviate(string => $category, %$category_abbreviate_opts);
        return $category;
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
        $word_blacklist, #slurp certain words
        $word_separator) = #symbol to join abbreviated words again
        @params{qw/
            string
            limit
            word_count_limit
            word_abbreviation_length
            word_limit
            word_blacklist
            word_separator
    /};

    $limit //= 1;
    $word_count_limit //= 2;
    $word_abbreviation_length //= 3;
    $word_limit //= $word_abbreviation_length + 2;
    $word_blacklist = {} unless 'HASH' eq ref $word_blacklist;
    $word_separator //= '';
    return $string if length($string) <= $limit;
    $string =~ s/[^a-zA-Z0-9 <>=äöüÄÖÜß_-]//g;
    $string =~ s/[ _-]+/ /g;
    my @words = grep { local $_ = $_; (not exists $word_blacklist->{$_}) or (not $word_blacklist->{$_}); } split(/ /,$string,-1);
    return join(' ',@words) if (scalar grep { local $_ = $_; length($_) > $word_abbreviation_length; } @words) <= $word_count_limit;
    my @abbreviated_words = ();
    foreach my $word (@words) {
        push(@abbreviated_words,(length($word) > $word_limit ? chopstring($word,$word_abbreviation_length,'') : $word));
    }
    return join($word_separator,@abbreviated_words);
}

sub inquiry_data_include_inquiry {
    return &$inquiry_data_include_inquiry_code(shift);
}

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;

        $result &= _prepare_working_paths(1);

        $sqlite_db_file = $data->{sqlite_db_file} if exists $data->{sqlite_db_file};
        $csv_dir = $data->{csv_dir} if exists $data->{csv_dir};

        $skip_errors = $data->{skip_errors} if exists $data->{skip_errors};

        $inquiry_data_truncate_table = $data->{inquiry_data_truncate_table} if exists $data->{inquiry_data_truncate_table};
        $inquiry_data_ignore_duplicates = $data->{inquiry_data_ignore_duplicates} if exists $data->{inquiry_data_ignore_duplicates};

        $inquiry_data_trial_id = $data->{inquiry_data_trial_id} if exists $data->{inquiry_data_trial_id};
        if (defined $inquiry_data_trial_id and length($inquiry_data_trial_id) > 0) {
            my $inquiry_data_trial = CTSMS::BulkProcessor::RestRequests::ctsms::trial::TrialService::Trial::get_item($inquiry_data_trial_id);
            if (defined $inquiry_data_trial) {
                scriptinfo("trial '$inquiry_data_trial->{name}'",getlogger(__PACKAGE__));
            } else {
                scripterror("error loading trial id $inquiry_data_trial_id",getlogger(__PACKAGE__));
            }
        }
        $job_id = $data->{job_id} if exists $data->{job_id};
        if (defined $job_id and length($job_id) > 0) {
            $job = CTSMS::BulkProcessor::RestRequests::ctsms::shared::JobService::Job::get_item($job_id, { _file => 1, });
            if (defined $job) {
                scriptinfo("job '$job->{type}->{name}' id $job_id",getlogger(__PACKAGE__));
                #_download_job_file() if $job->{type}->{inputFile};
            } else {
                scripterror("error loading job id $job_id",getlogger(__PACKAGE__));
            }
            $completionemailrecipient = $job->{emailRecipients};
        }

        $inquiry_proband_alias_column_name = $data->{inquiry_proband_alias_column_name} if exists $data->{inquiry_proband_alias_column_name};
        $inquiry_proband_category_column_name = $data->{inquiry_proband_category_column_name} if exists $data->{inquiry_proband_category_column_name};
        $inquiry_proband_department_column_name = $data->{inquiry_proband_department_column_name} if exists $data->{inquiry_proband_department_column_name};
        $inquiry_proband_gender_column_name = $data->{inquiry_proband_gender_column_name} if exists $data->{inquiry_proband_gender_column_name};

        $inquiry_data_api_probands_page_size = $data->{inquiry_data_api_probands_page_size} if exists $data->{inquiry_data_api_probands_page_size};
        $inquiry_data_api_inquiries_page_size = $data->{inquiry_data_api_inquiries_page_size} if exists $data->{inquiry_data_api_inquiries_page_size};
        $inquiry_data_api_values_page_size = $data->{inquiry_data_api_values_page_size} if exists $data->{inquiry_data_api_values_page_size};
        $inquiry_data_row_block = $data->{inquiry_data_row_block} if exists $data->{inquiry_data_row_block};

        $inquiry_data_export_upload_folder = $data->{inquiry_data_export_upload_folder} if exists $data->{inquiry_data_export_upload_folder};

        $inquiry_data_export_sqlite_filename = $data->{inquiry_data_export_sqlite_filename} if exists $data->{inquiry_data_export_sqlite_filename};
        $inquiry_data_export_horizontal_csv_filename = $data->{inquiry_data_export_horizontal_csv_filename} if exists $data->{inquiry_data_export_horizontal_csv_filename};
        $inquiry_data_export_xls_filename = $data->{inquiry_data_export_xls_filename} if exists $data->{inquiry_data_export_xls_filename};
        $inquiry_data_export_xlsx = $data->{inquiry_data_export_xlsx} if exists $data->{inquiry_data_export_xlsx};

        $col_per_selection_set_value = $data->{col_per_selection_set_value} if exists $data->{col_per_selection_set_value};
        $selection_set_value_separator = $data->{selection_set_value_separator} if exists $data->{selection_set_value_separator};
        $selection_set_value_separator //= '';

        if (exists $data->{inquiry_data_include_inquiry_code}) {
            if ('CODE' eq ref $data->{inquiry_data_include_inquiry_code}) {
                $inquiry_data_include_inquiry_code = $data->{inquiry_data_include_inquiry_code};
            } else {
                configurationerror($configfile,"perl code reference required for inquiry_data_include_inquiry_code",getlogger(__PACKAGE__));
            }
        }

        $ctsms_base_url = $data->{ctsms_base_uri} if exists $data->{ctsms_base_uri};
        $ctsms_base_url = _get_ctsms_baseuri() unless $ctsms_base_url;

        $lockfile = $data->{lockfile} if exists $data->{lockfile};

        $inquiry_data_export_pdfs_filename = $data->{inquiry_data_export_pdfs_filename} if exists $data->{inquiry_data_export_pdfs_filename};

        $colname_abbreviation{ignore_external_ids} = $data->{ignore_external_ids} if exists $data->{ignore_external_ids};
        $ecrfname_abbreviate_opts = $data->{ecrfname_abbreviate_opts} if exists $data->{ecrfname_abbreviate_opts};
        $inputfieldname_abbreviate_opts = $data->{inputfieldname_abbreviate_opts} if exists $data->{inputfieldname_abbreviate_opts};
        $selectionvalue_abbreviate_opts = $data->{selectionvalue_abbreviate_opts} if exists $data->{selectionvalue_abbreviate_opts};

        $category_abbreviate_opts = $data->{category_abbreviate_opts} if exists $data->{category_abbreviate_opts};

        return $result;

    }
    return 0;

}

sub get_proband_columns {
    my $proband = shift;
    my @columns = ();
    if ($proband) {
        push(@columns,$proband->{alias}) if length($inquiry_proband_alias_column_name);
        push(@columns,$proband->{category}->{nameL10nKey}) if length($inquiry_proband_category_column_name);
        push(@columns,$proband->{department}->{nameL10nKey}) if length($inquiry_proband_department_column_name);
        push(@columns,$proband->{gender}->{sex}) if length($inquiry_proband_gender_column_name);
    } else {
        push(@columns,$inquiry_proband_alias_column_name) if length($inquiry_proband_alias_column_name);
        push(@columns,$inquiry_proband_category_column_name) if length($inquiry_proband_category_column_name);
        push(@columns,$inquiry_proband_department_column_name) if length($inquiry_proband_department_column_name);
        push(@columns,$inquiry_proband_gender_column_name) if length($inquiry_proband_gender_column_name);
    }
    return @columns;
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
        if ($job->{type}->{outputFile}
            or ($job->{hasFile} and $job->{type}->{inputFile})) {
            push(@args,@job_file);
        } else {
            push(@args,undef,undef,undef);
        }
        push(@args, { _file => 1, });

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
