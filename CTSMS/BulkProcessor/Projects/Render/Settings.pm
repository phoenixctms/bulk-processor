package CTSMS::BulkProcessor::Projects::Render::Settings;
use strict;

## no critic

use CTSMS::BulkProcessor::Globals qw(
    $working_path
    $enablemultithreading
    $cpucount
    create_path
);

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    scriptinfo
    configurationinfo
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
use CTSMS::BulkProcessor::Utils qw(format_number prompt get_year_month); #check_ipnet

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    update_settings

    $input_path
    $output_path

    $defaultsettings
    $defaultconfig

    $force

    $ecrfstatustype_wordwrapcolumns
    $ecrfstatustype_fontsize
    $ecrfstatustype_noderadius
    $ecrfstatustype_fontname
    $ecrfstatustype_usenodecolor
    $ecrfstatustype_width
    $ecrfstatustype_height
    $ecrfstatustype_filename

    $ecrffieldstatustype_wordwrapcolumns
    $ecrffieldstatustype_fontsize
    $ecrffieldstatustype_noderadius
    $ecrffieldstatustype_fontname
    $ecrffieldstatustype_usenodecolor
    $ecrffieldstatustype_width
    $ecrffieldstatustype_height
    $ecrffieldstatustype_annotation_filename
    $ecrffieldstatustype_validation_filename
    $ecrffieldstatustype_query_filename

    $courseparticipationstatustype_wordwrapcolumns
    $courseparticipationstatustype_fontsize
    $courseparticipationstatustype_noderadius
    $courseparticipationstatustype_fontname
    $courseparticipationstatustype_usenodecolor
    $courseparticipationstatustype_width
    $courseparticipationstatustype_height
    $courseparticipationstatustype_participant_filename
    $courseparticipationstatustype_admin_filename
    $courseparticipationstatustype_self_registration_participant_filename
    $courseparticipationstatustype_self_registration_admin_filename

    $privacyconsentstatustype_wordwrapcolumns
    $privacyconsentstatustype_fontsize
    $privacyconsentstatustype_noderadius
    $privacyconsentstatustype_fontname
    $privacyconsentstatustype_usenodecolor
    $privacyconsentstatustype_width
    $privacyconsentstatustype_height
    $privacyconsentstatustype_filename


    $trialstatustype_wordwrapcolumns
    $trialstatustype_fontsize
    $trialstatustype_noderadius
    $trialstatustype_fontname
    $trialstatustype_usenodecolor
    $trialstatustype_width
    $trialstatustype_height
    $trialstatustype_filename

    $probandliststatustype_wordwrapcolumns
    $probandliststatustype_fontsize
    $probandliststatustype_noderadius
    $probandliststatustype_fontname
    $probandliststatustype_usenodecolor
    $probandliststatustype_width
    $probandliststatustype_height
    $probandliststatustype_person_filename
    $probandliststatustype_animal_filename

    $massmailstatustype_wordwrapcolumns
    $massmailstatustype_fontsize
    $massmailstatustype_noderadius
    $massmailstatustype_usenodecolor
    $massmailstatustype_fontname
    $massmailstatustype_width
    $massmailstatustype_height
    $massmailstatustype_filename

    $journal_heatmap_filename
    $journal_heatmap_span_days
    $journal_heatmap_start_date
    $journal_heatmap_end_date
    $journal_heatmap_dimension

    $logon_heatmap_filename
    $logon_heatmap_span_days
    $logon_heatmap_start_date
    $logon_heatmap_end_date
    $logon_heatmap_dimension

    $journal_histogram_filename
    $journal_histogram_dimension
    $journal_histogram_interval
    $journal_histogram_year
    $journal_histogram_month

    $magick
);

our $defaultconfig = 'config.cfg';
our $defaultsettings = 'settings.cfg';

our $input_path = $working_path . 'input/';
our $output_path = $working_path . 'output/';
#our $rollback_path = $working_path . 'rollback/';

our $force = 0;

our $ecrfstatustype_wordwrapcolumns = undef;
our $ecrfstatustype_fontsize = undef;
our $ecrfstatustype_noderadius = undef;
our $ecrfstatustype_fontname = undef;
our $ecrfstatustype_usenodecolor = undef;
our $ecrfstatustype_width = undef;
our $ecrfstatustype_height = undef;
our $ecrfstatustype_filename = 'ecrf_states.png';

our $ecrffieldstatustype_wordwrapcolumns = undef;
our $ecrffieldstatustype_fontsize = undef;
our $ecrffieldstatustype_noderadius = undef;
our $ecrffieldstatustype_fontname = undef;
our $ecrffieldstatustype_usenodecolor = undef;
our $ecrffieldstatustype_width = undef;
our $ecrffieldstatustype_height = undef;
our $ecrffieldstatustype_annotation_filename = 'ecrffield_annotation_states.png';
our $ecrffieldstatustype_validation_filename = 'ecrffield_validation_states.png';
our $ecrffieldstatustype_query_filename = 'ecrffield_query_states.png';

our $courseparticipationstatustype_wordwrapcolumns = undef;
our $courseparticipationstatustype_fontsize = undef;
our $courseparticipationstatustype_noderadius = undef;
our $courseparticipationstatustype_fontname = undef;
our $courseparticipationstatustype_usenodecolor = undef;
our $courseparticipationstatustype_width = undef;
our $courseparticipationstatustype_height = undef;
our $courseparticipationstatustype_participant_filename = 'course_participation_states_participant.png';
our $courseparticipationstatustype_admin_filename = 'course_participation_states_admin.png';
our $courseparticipationstatustype_self_registration_participant_filename = 'course_participation_states_self_registration_participant.png';
our $courseparticipationstatustype_self_registration_admin_filename = 'course_participation_states_self_registration_admin.png';

our $privacyconsentstatustype_wordwrapcolumns = undef;
our $privacyconsentstatustype_fontsize = undef;
our $privacyconsentstatustype_noderadius = undef;
our $privacyconsentstatustype_fontname = undef;
our $privacyconsentstatustype_usenodecolor = undef;
our $privacyconsentstatustype_width = undef;
our $privacyconsentstatustype_height = undef;
our $privacyconsentstatustype_filename = 'privacy_consent_states.png';

our $trialstatustype_wordwrapcolumns = undef;
our $trialstatustype_fontsize = undef;
our $trialstatustype_noderadius = undef;
our $trialstatustype_fontname = undef;
our $trialstatustype_usenodecolor = undef;
our $trialstatustype_width = undef;
our $trialstatustype_height = undef;
our $trialstatustype_filename = 'trial_states.png';

our $probandliststatustype_wordwrapcolumns = undef;
our $probandliststatustype_fontsize = undef;
our $probandliststatustype_noderadius = undef;
our $probandliststatustype_fontname = undef;
our $probandliststatustype_usenodecolor = undef;
our $probandliststatustype_width = undef;
our $probandliststatustype_height = undef;
our $probandliststatustype_person_filename = 'enrollment_states_person.png';
our $probandliststatustype_animal_filename = 'enrollment_states_animal.png';

our $massmailstatustype_wordwrapcolumns = undef;
our $massmailstatustype_fontsize = undef;
our $massmailstatustype_noderadius = undef;
our $massmailstatustype_fontname = undef;
our $massmailstatustype_usenodecolor = undef;
our $massmailstatustype_width = undef;
our $massmailstatustype_height = undef;
our $massmailstatustype_filename = 'mass_mail_states.png';

our $journal_heatmap_filename = 'journal_heatmap.png';
our $journal_heatmap_span_days = undef;
our $journal_heatmap_start_date = undef;
our $journal_heatmap_end_date = undef;
our $journal_heatmap_dimension = undef;

our $logon_heatmap_filename = 'logon_heatmap.png';
our $logon_heatmap_span_days = undef;
our $logon_heatmap_start_date = undef;
our $logon_heatmap_end_date = undef;
our $logon_heatmap_dimension = undef;

our $journal_histogram_filename = 'journal_histogram.png';
our $journal_histogram_dimension = undef;
our $journal_histogram_interval = undef;
our ($journal_histogram_year,$journal_histogram_month) = get_year_month();

our $magick = 'magick'; #'convert'

sub update_settings {

    my ($data,$configfile) = @_;

    if (defined $data) {

        my $result = 1;

        #&$configurationinfocode("testinfomessage",$configlogger);

        $result &= _prepare_working_paths(1);
        $ecrfstatustype_filename = $output_path . $ecrfstatustype_filename;
        $courseparticipationstatustype_participant_filename = $output_path . $courseparticipationstatustype_participant_filename;
        $courseparticipationstatustype_admin_filename = $output_path . $courseparticipationstatustype_admin_filename;
        $courseparticipationstatustype_self_registration_participant_filename = $output_path . $courseparticipationstatustype_self_registration_participant_filename;
        $courseparticipationstatustype_self_registration_admin_filename = $output_path . $courseparticipationstatustype_self_registration_admin_filename;
        $ecrffieldstatustype_annotation_filename = $output_path . $ecrffieldstatustype_annotation_filename;
        $ecrffieldstatustype_validation_filename = $output_path . $ecrffieldstatustype_validation_filename;
        $ecrffieldstatustype_query_filename = $output_path . $ecrffieldstatustype_query_filename;
        $privacyconsentstatustype_filename = $output_path . $privacyconsentstatustype_filename;
        $trialstatustype_filename = $output_path . $trialstatustype_filename;
        $probandliststatustype_person_filename = $output_path . $probandliststatustype_person_filename;
        $probandliststatustype_animal_filename = $output_path . $probandliststatustype_animal_filename;
        $journal_heatmap_filename = $output_path . $journal_heatmap_filename;
        $logon_heatmap_filename = $output_path . $logon_heatmap_filename;
        $journal_histogram_filename = $output_path . $journal_histogram_filename;

        $ecrfstatustype_wordwrapcolumns = $data->{ecrfstatustype_wordwrapcolumns} if exists $data->{ecrfstatustype_wordwrapcolumns};
        $ecrfstatustype_fontsize = $data->{ecrfstatustype_fontsize} if exists $data->{ecrfstatustype_fontsize};
        $ecrfstatustype_noderadius = $data->{ecrfstatustype_noderadius} if exists $data->{ecrfstatustype_noderadius};
        $ecrfstatustype_fontname = $data->{ecrfstatustype_fontname} if exists $data->{ecrfstatustype_fontname};
        $ecrfstatustype_usenodecolor = $data->{ecrfstatustype_usenodecolor} if exists $data->{ecrfstatustype_usenodecolor};
        $ecrfstatustype_width = $data->{ecrfstatustype_width} if exists $data->{ecrfstatustype_width};
        $ecrfstatustype_height = $data->{ecrfstatustype_height} if exists $data->{ecrfstatustype_height};
        $ecrfstatustype_filename = $data->{ecrfstatustype_filename} if exists $data->{ecrfstatustype_filename};

        $ecrffieldstatustype_wordwrapcolumns = $data->{ecrffieldstatustype_wordwrapcolumns} if exists $data->{ecrffieldstatustype_wordwrapcolumns};
        $ecrffieldstatustype_fontsize = $data->{ecrffieldstatustype_fontsize} if exists $data->{ecrffieldstatustype_fontsize};
        $ecrffieldstatustype_noderadius = $data->{ecrffieldstatustype_noderadius} if exists $data->{ecrffieldstatustype_noderadius};
        $ecrffieldstatustype_fontname = $data->{ecrffieldstatustype_fontname} if exists $data->{ecrffieldstatustype_fontname};
        $ecrffieldstatustype_usenodecolor = $data->{ecrffieldstatustype_usenodecolor} if exists $data->{ecrffieldstatustype_usenodecolor};
        $ecrffieldstatustype_width = $data->{ecrffieldstatustype_width} if exists $data->{ecrffieldstatustype_width};
        $ecrffieldstatustype_height = $data->{ecrffieldstatustype_height} if exists $data->{ecrffieldstatustype_height};
        $ecrffieldstatustype_annotation_filename = $data->{ecrffieldstatustype_annotation_filename} if exists $data->{ecrffieldstatustype_annotation_filename};
        $ecrffieldstatustype_validation_filename = $data->{ecrffieldstatustype_validation_filename} if exists $data->{ecrffieldstatustype_validation_filename};
        $ecrffieldstatustype_query_filename = $data->{ecrffieldstatustype_query_filename} if exists $data->{ecrffieldstatustype_query_filename};

        $courseparticipationstatustype_wordwrapcolumns = $data->{courseparticipationstatustype_wordwrapcolumns} if exists $data->{courseparticipationstatustype_wordwrapcolumns};
        $courseparticipationstatustype_fontsize = $data->{courseparticipationstatustype_fontsize} if exists $data->{courseparticipationstatustype_fontsize};
        $courseparticipationstatustype_noderadius = $data->{courseparticipationstatustype_noderadius} if exists $data->{courseparticipationstatustype_noderadius};
        $courseparticipationstatustype_fontname = $data->{courseparticipationstatustype_fontname} if exists $data->{courseparticipationstatustype_fontname};
        $courseparticipationstatustype_usenodecolor = $data->{courseparticipationstatustype_usenodecolor} if exists $data->{courseparticipationstatustype_usenodecolor};
        $courseparticipationstatustype_width = $data->{courseparticipationstatustype_width} if exists $data->{courseparticipationstatustype_width};
        $courseparticipationstatustype_height = $data->{courseparticipationstatustype_height} if exists $data->{courseparticipationstatustype_height};
        $courseparticipationstatustype_participant_filename = $data->{courseparticipationstatustype_participant_filename} if exists $data->{courseparticipationstatustype_participant_filename};
        $courseparticipationstatustype_admin_filename = $data->{courseparticipationstatustype_admin_filename} if exists $data->{courseparticipationstatustype_admin_filename};
        $courseparticipationstatustype_self_registration_participant_filename = $data->{courseparticipationstatustype_self_registration_participant_filename} if exists $data->{courseparticipationstatustype_self_registration_participant_filename};
        $courseparticipationstatustype_self_registration_admin_filename = $data->{courseparticipationstatustype_self_registration_admin_filename} if exists $data->{courseparticipationstatustype_self_registration_admin_filename};

        $privacyconsentstatustype_wordwrapcolumns = $data->{privacyconsentstatustype_wordwrapcolumns} if exists $data->{privacyconsentstatustype_wordwrapcolumns};
        $privacyconsentstatustype_fontsize = $data->{privacyconsentstatustype_fontsize} if exists $data->{privacyconsentstatustype_fontsize};
        $privacyconsentstatustype_noderadius = $data->{privacyconsentstatustype_noderadius} if exists $data->{privacyconsentstatustype_noderadius};
        $privacyconsentstatustype_fontname = $data->{privacyconsentstatustype_fontname} if exists $data->{privacyconsentstatustype_fontname};
        $privacyconsentstatustype_usenodecolor = $data->{privacyconsentstatustype_usenodecolor} if exists $data->{privacyconsentstatustype_usenodecolor};
        $privacyconsentstatustype_width = $data->{privacyconsentstatustype_width} if exists $data->{privacyconsentstatustype_width};
        $privacyconsentstatustype_height = $data->{privacyconsentstatustype_height} if exists $data->{privacyconsentstatustype_height};
        $privacyconsentstatustype_filename = $data->{privacyconsentstatustype_filename} if exists $data->{privacyconsentstatustype_filename};

        $trialstatustype_wordwrapcolumns = $data->{trialstatustype_wordwrapcolumns} if exists $data->{trialstatustype_wordwrapcolumns};
        $trialstatustype_fontsize = $data->{trialstatustype_fontsize} if exists $data->{trialstatustype_fontsize};
        $trialstatustype_noderadius = $data->{trialstatustype_noderadius} if exists $data->{trialstatustype_noderadius};
        $trialstatustype_fontname = $data->{trialstatustype_fontname} if exists $data->{trialstatustype_fontname};
        $trialstatustype_usenodecolor = $data->{trialstatustype_usenodecolor} if exists $data->{trialstatustype_usenodecolor};
        $trialstatustype_width = $data->{trialstatustype_width} if exists $data->{trialstatustype_width};
        $trialstatustype_height = $data->{trialstatustype_height} if exists $data->{trialstatustype_height};
        $trialstatustype_filename = $data->{trialstatustype_filename} if exists $data->{trialstatustype_filename};

        $probandliststatustype_wordwrapcolumns = $data->{probandliststatustype_wordwrapcolumns} if exists $data->{probandliststatustype_wordwrapcolumns};
        $probandliststatustype_fontsize = $data->{probandliststatustype_fontsize} if exists $data->{probandliststatustype_fontsize};
        $probandliststatustype_noderadius = $data->{probandliststatustype_noderadius} if exists $data->{probandliststatustype_noderadius};
        $probandliststatustype_fontname = $data->{probandliststatustype_fontname} if exists $data->{probandliststatustype_fontname};
        $probandliststatustype_usenodecolor = $data->{probandliststatustype_usenodecolor} if exists $data->{probandliststatustype_usenodecolor};
        $probandliststatustype_width = $data->{probandliststatustype_width} if exists $data->{probandliststatustype_width};
        $probandliststatustype_height = $data->{probandliststatustype_height} if exists $data->{probandliststatustype_height};
        $probandliststatustype_person_filename = $data->{probandliststatustype_person_filename} if exists $data->{probandliststatustype_person_filename};
        $probandliststatustype_animal_filename = $data->{probandliststatustype_animal_filename} if exists $data->{probandliststatustype_animal_filename};

        $massmailstatustype_wordwrapcolumns = $data->{massmailstatustype_wordwrapcolumns} if exists $data->{massmailstatustype_wordwrapcolumns};
        $massmailstatustype_fontsize = $data->{massmailstatustype_fontsize} if exists $data->{massmailstatustype_fontsize};
        $massmailstatustype_noderadius = $data->{massmailstatustype_noderadius} if exists $data->{massmailstatustype_noderadius};
        $massmailstatustype_fontname = $data->{massmailstatustype_fontname} if exists $data->{massmailstatustype_fontname};
        $massmailstatustype_usenodecolor = $data->{massmailstatustype_usenodecolor} if exists $data->{massmailstatustype_usenodecolor};
        $massmailstatustype_width = $data->{massmailstatustype_width} if exists $data->{massmailstatustype_width};
        $massmailstatustype_height = $data->{massmailstatustype_height} if exists $data->{massmailstatustype_height};
        $massmailstatustype_filename = $data->{massmailstatustype_filename} if exists $data->{massmailstatustype_filename};

        $journal_heatmap_filename = $data->{journal_heatmap_filename} if exists $data->{journal_heatmap_filename};
        $journal_heatmap_span_days = $data->{journal_heatmap_span_days} if exists $data->{journal_heatmap_span_days};
        $journal_heatmap_start_date = $data->{journal_heatmap_start_date} if exists $data->{journal_heatmap_start_date};
        $journal_heatmap_end_date = $data->{journal_heatmap_end_date} if exists $data->{journal_heatmap_end_date};
        $journal_heatmap_dimension = $data->{journal_heatmap_dimension} if exists $data->{journal_heatmap_dimension};

        $logon_heatmap_filename = $data->{logon_heatmap_filename} if exists $data->{logon_heatmap_filename};
        $logon_heatmap_span_days = $data->{logon_heatmap_span_days} if exists $data->{logon_heatmap_span_days};
        $logon_heatmap_start_date = $data->{logon_heatmap_start_date} if exists $data->{logon_heatmap_start_date};
        $logon_heatmap_end_date = $data->{logon_heatmap_end_date} if exists $data->{logon_heatmap_end_date};
        $logon_heatmap_dimension = $data->{logon_heatmap_dimension} if exists $data->{logon_heatmap_dimension};

        $journal_histogram_filename = $data->{journal_histogram_filename} if exists $data->{journal_histogram_filename};
        $journal_histogram_dimension = $data->{journal_histogram_dimension} if exists $data->{journal_histogram_dimension};
        $journal_histogram_interval = $data->{journal_histogram_interval} if exists $data->{journal_histogram_interval};
        $journal_histogram_year = $data->{journal_histogram_year} if exists $data->{journal_histogram_year};
        $journal_histogram_month = $data->{journal_histogram_month} if exists $data->{journal_histogram_month};

        $magick = $data->{magick} if exists $data->{magick};

        return $result;

    }
    return 0;

}

sub _prepare_working_paths {

    my ($create) = @_;
    my $result = 1;
    my $path_result;

    ($path_result,$input_path) = create_path($working_path . 'input',$input_path,$create,\&fileerror,getlogger(__PACKAGE__));
    $result &= $path_result;
    ($path_result,$output_path) = create_path($working_path . 'output',$output_path,$create,\&fileerror,getlogger(__PACKAGE__));
    $result &= $path_result;
    #($path_result,$rollback_path) = create_path($working_path . 'rollback',$rollback_path,$create,\&fileerror,getlogger(__PACKAGE__));
    #$result &= $path_result;

    return $result;

}

1;
