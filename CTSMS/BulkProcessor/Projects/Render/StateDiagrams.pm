package CTSMS::BulkProcessor::Projects::Render::StateDiagrams;
use strict;

## no critic

use threads::shared qw();

use GraphViz qw();
use HTML::Entities qw(encode_entities);

use CTSMS::BulkProcessor::Projects::Render::Settings qw(
    $output_path

    $ecrfstatustype_wordwrapcolumns
    $ecrfstatustype_fontsize
    $ecrfstatustype_noderadius
    $ecrfstatustype_usenodecolor
    $ecrfstatustype_fontname
    $ecrfstatustype_width
    $ecrfstatustype_height
    $ecrfstatustype_filename

    $ecrffieldstatustype_wordwrapcolumns
    $ecrffieldstatustype_fontsize
    $ecrffieldstatustype_noderadius
    $ecrffieldstatustype_usenodecolor
    $ecrffieldstatustype_fontname
    $ecrffieldstatustype_width
    $ecrffieldstatustype_height

    $courseparticipationstatustype_wordwrapcolumns
    $courseparticipationstatustype_fontsize
    $courseparticipationstatustype_noderadius
    $courseparticipationstatustype_usenodecolor
    $courseparticipationstatustype_fontname
    $courseparticipationstatustype_width
    $courseparticipationstatustype_height

    $privacyconsentstatustype_wordwrapcolumns
    $privacyconsentstatustype_fontsize
    $privacyconsentstatustype_noderadius
    $privacyconsentstatustype_usenodecolor
    $privacyconsentstatustype_fontname
    $privacyconsentstatustype_width
    $privacyconsentstatustype_height
    $privacyconsentstatustype_filename

    $trialstatustype_wordwrapcolumns
    $trialstatustype_fontsize
    $trialstatustype_noderadius
    $trialstatustype_usenodecolor
    $trialstatustype_fontname
    $trialstatustype_width
    $trialstatustype_height
    $trialstatustype_filename

    $probandliststatustype_wordwrapcolumns
    $probandliststatustype_fontsize
    $probandliststatustype_noderadius
    $probandliststatustype_usenodecolor
    $probandliststatustype_fontname
    $probandliststatustype_width
    $probandliststatustype_height

    $massmailstatustype_wordwrapcolumns
    $massmailstatustype_fontsize
    $massmailstatustype_noderadius
    $massmailstatustype_usenodecolor
    $massmailstatustype_fontname
    $massmailstatustype_width
    $massmailstatustype_height
    $massmailstatustype_filename

);


use CTSMS::BulkProcessor::Logging qw (
    getlogger
    processing_info
    processing_debug
);
use CTSMS::BulkProcessor::LogError qw(
    rowprocessingerror
    rowprocessingwarn
);

use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::EcrfStatusType qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CourseParticipationStatusType qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::PrivacyConsentStatusType qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::TrialStatusType qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandListStatusType qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::EcrfFieldStatusType qw();
use CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::MassMailStatusType qw();

use CTSMS::BulkProcessor::Utils qw(threadid wrap_text);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    create_ecrfstatustype_diagram
    create_courseparticipationstatustype_diagram
    create_privacyconsentstatustype_diagram
    create_trialstatustype_diagram
    create_probandliststatustype_diagram
    create_ecrffieldstatustype_diagram
    create_massmailstatustype_diagram
);

my %color_translation = (
    LIGHTGREEN => 'LIMEGREEN',
    LIME => 'GREEN',
    DARKGREY => 'gray66',
    DARKGRAY => 'gray66',

);

sub create_courseparticipationstatustype_diagram {
    my ($admin,$selfregistration,$filename) = @_;
    _render_state_diagram(
        initial_items => CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CourseParticipationStatusType::get_initial_items(1,$selfregistration),
        get_transition_items_code => sub {
            my ($id) = @_;
            return CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::CourseParticipationStatusType::get_transition_items($id,$admin,$selfregistration);
        },
        wordwrapcolumns => $courseparticipationstatustype_wordwrapcolumns,
        fontsize => $courseparticipationstatustype_fontsize,
        noderadius => $courseparticipationstatustype_noderadius,
        fontname => $courseparticipationstatustype_fontname,
        usenodecolor => $courseparticipationstatustype_usenodecolor,
        width => $courseparticipationstatustype_width,
        height => $courseparticipationstatustype_height,
        filename => $filename,
    );
}

sub create_ecrfstatustype_diagram {
    _render_state_diagram(
        initial_items => CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::EcrfStatusType::get_initial_items(),
        get_transition_items_code => \&CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::EcrfStatusType::get_transition_items,
        wordwrapcolumns => $ecrfstatustype_wordwrapcolumns,
        fontsize => $ecrfstatustype_fontsize,
        noderadius => $ecrfstatustype_noderadius,
        fontname => $ecrfstatustype_fontname,
        usenodecolor => $ecrfstatustype_usenodecolor,
        width => $ecrfstatustype_width,
        height => $ecrfstatustype_height,
        filename => $ecrfstatustype_filename,
    );
}

sub create_ecrffieldstatustype_diagram {
    my ($queue,$filename) = @_;
    _render_state_diagram(
        initial_items => CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::EcrfFieldStatusType::get_initial_items($queue),
        get_transition_items_code => \&CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::EcrfFieldStatusType::get_transition_items,
        wordwrapcolumns => $ecrffieldstatustype_wordwrapcolumns,
        fontsize => $ecrffieldstatustype_fontsize,
        noderadius => $ecrffieldstatustype_noderadius,
        fontname => $ecrffieldstatustype_fontname,
        usenodecolor => $ecrffieldstatustype_usenodecolor,
        width => $ecrffieldstatustype_width,
        height => $ecrffieldstatustype_height,
        filename => $filename,
    );
}

sub create_privacyconsentstatustype_diagram {
    _render_state_diagram(
        initial_items => CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::PrivacyConsentStatusType::get_initial_items(),
        get_transition_items_code => \&CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::PrivacyConsentStatusType::get_transition_items,
        wordwrapcolumns => $privacyconsentstatustype_wordwrapcolumns,
        fontsize => $privacyconsentstatustype_fontsize,
        noderadius => $privacyconsentstatustype_noderadius,
        fontname => $privacyconsentstatustype_fontname,
        usenodecolor => $privacyconsentstatustype_usenodecolor,
        width => $privacyconsentstatustype_width,
        height => $privacyconsentstatustype_height,
        filename => $privacyconsentstatustype_filename,
    );
}

sub create_trialstatustype_diagram {
    _render_state_diagram(
        initial_items => CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::TrialStatusType::get_initial_items(),
        get_transition_items_code => \&CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::TrialStatusType::get_transition_items,
        wordwrapcolumns => $trialstatustype_wordwrapcolumns,
        fontsize => $trialstatustype_fontsize,
        noderadius => $trialstatustype_noderadius,
        fontname => $trialstatustype_fontname,
        usenodecolor => $trialstatustype_usenodecolor,
        width => $trialstatustype_width,
        height => $trialstatustype_height,
        filename => $trialstatustype_filename,
    );
}

sub create_probandliststatustype_diagram {
    my ($signup,$person,$filename) = @_;
    _render_state_diagram(
        initial_items => CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandListStatusType::get_initial_items($signup,$person),
        get_transition_items_code => \&CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::ProbandListStatusType::get_transition_items,
        wordwrapcolumns => $probandliststatustype_wordwrapcolumns,
        fontsize => $probandliststatustype_fontsize,
        noderadius => $probandliststatustype_noderadius,
        fontname => $probandliststatustype_fontname,
        usenodecolor => $probandliststatustype_usenodecolor,
        width => $probandliststatustype_width,
        height => $probandliststatustype_height,
        filename => $filename,
    );
}

sub create_massmailstatustype_diagram {
    _render_state_diagram(
        initial_items => CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::MassMailStatusType::get_initial_items(),
        get_transition_items_code => \&CTSMS::BulkProcessor::RestRequests::ctsms::shared::SelectionSetService::MassMailStatusType::get_transition_items,
        wordwrapcolumns => $massmailstatustype_wordwrapcolumns,
        fontsize => $massmailstatustype_fontsize,
        noderadius => $massmailstatustype_noderadius,
        fontname => $massmailstatustype_fontname,
        usenodecolor => $massmailstatustype_usenodecolor,
        width => $massmailstatustype_width,
        height => $massmailstatustype_height,
        filename => $massmailstatustype_filename,
    );
}

sub _render_state_diagram {

    my %params = @_;
    my ($initial_items,
        $get_transition_items_code,
        $get_edge_label_code,
        $wordwrapcolumns,
        $fontsize,
        $noderadius,
        $fontname,
        $usenodecolor,
        $width,
        $height,
        $filename) = @params{qw/
            initial_items
            get_transition_items_code
            get_edge_label_code
            wordwrapcolumns
            fontsize
            noderadius
            fontname
            usenodecolor
            width
            height
            filename
        /};
    if (not defined $get_edge_label_code or 'CODE' ne ref $get_edge_label_code) {
        $get_edge_label_code = sub {
            my ($item_from,$item_to) = @_;
            return undef;
        };
    }
    my $context = {
        wordwrapcolumns => $wordwrapcolumns,
        get_transition_items_code => $get_transition_items_code,
        get_edge_label_code => $get_edge_label_code,
        fontsize => $fontsize,
        noderadius => $noderadius,
        fontname => $fontname,
        usenodecolor => $usenodecolor,
    };
    $context->{gv} = GraphViz->new(
        layout => 'dot',
        directed => 1,
        rankdir => 'LR',

        epsilon => 0.01,
        ratio => 'compress',

        width => $width,
        height => $height,
        concentrate=> 1,
    );
    $context->{node_map} = {};
    foreach my $initial_item (@$initial_items) {


        $context->{gv}->add_node($initial_item->{id},
            label => _prepare_node_label($initial_item->{name},$wordwrapcolumns),
            ($usenodecolor ? (style => 'filled', fillcolor => _translate_color($initial_item->{color})) : ()),
            rank => '0',
            fixedsize=>'shape',
            fontsize => $fontsize,
            shape => 'doublecircle',
            width => $noderadius,
            fontname => $fontname,
        );
        $context->{node_map}->{$initial_item->{id}} = $initial_item;
    }

    foreach my $id (keys %{$context->{node_map}}) {

        _append_transition_nodes($context,$id,'1');
    }


    $context->{gv}->as_png($filename);
    _info($filename . ' created');
}

sub _append_transition_nodes {
    my ($context,$id,$depth) = @_;
    my $transition_nodes = &{$context->{get_transition_items_code}}($id);
    if ((scalar @$transition_nodes) > 0) {
        foreach my $item (@$transition_nodes) {
            if (not exists $context->{node_map}->{$item->{id}}) {
                $context->{gv}->add_node($item->{id},
                    label => _prepare_node_label($item->{name},$context->{wordwrapcolumns}),
                    ($context->{usenodecolor} ? (style => 'filled', fillcolor => _translate_color($item->{color})) : ()),
                    rank => $depth,
                    fixedsize=>'shape',
                    fontsize => $context->{fontsize},
                    shape => 'circle',
                    width => $context->{noderadius},
                    fontname => $context->{fontname},
                );
                $context->{node_map}->{$item->{id}} = $item;
                _append_transition_nodes($context,$item->{id},$depth + 1);
            }
            my $edge_label = &{$context->{get_edge_label_code}}($context->{node_map}->{$id},$item);
            $context->{gv}->add_edge($id => $item->{id},
                ((defined $edge_label and length($edge_label)) > 0 ? ( label => $edge_label ) : ()),
                fontsize => $context->{fontsize},
                fontname => $context->{fontname},
            );
        }
    } else {
        $context->{gv}->add_node($id,
            ($context->{usenodecolor} ? (style => 'filled,bold') : (style => 'bold')),
        );
    }
}

sub _translate_color {
    my ($color) = @_;
    if (exists $color_translation{$color}) {
        return $color_translation{$color};
    }
    return $color;
}

sub _prepare_node_label {
    my ($label,$wordwrapcolumns) = @_;
    if (defined $wordwrapcolumns and $wordwrapcolumns > 0) {
        $label = wrap_text($label,$wordwrapcolumns);
    }
    return encode_entities($label);
}

sub _error {

    my ($message) = @_;

    rowprocessingerror(threadid(),$message,getlogger(__PACKAGE__));

}

sub _warn {

    my ($message) = @_;

    rowprocessingwarn(threadid(),$message,getlogger(__PACKAGE__));

}

sub _info {

    my ($message,$debug) = @_;
    if ($debug) {
        processing_debug(threadid(),$message,getlogger(__PACKAGE__));
    } else {
        processing_info(threadid(),$message,getlogger(__PACKAGE__));
    }
}

1;
