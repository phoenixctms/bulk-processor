package CTSMS::BulkProcessor::FileProcessors::XlsxFileSimple;
use strict;

## no critic

use Archive::Zip qw(AZ_OK);
use Spreadsheet::ParseXLSX qw();
use XML::LibXML qw();

use CTSMS::BulkProcessor::Logging qw(
    getlogger
    processing_info
);

use CTSMS::BulkProcessor::LogError qw(
    fileerror
);

use CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor qw();

require Exporter;
our @ISA = qw(Exporter CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor);
our @EXPORT_OK = qw();

my $REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

sub new {

    my $class = shift;

    my $self = CTSMS::BulkProcessor::FileProcessors::SpreadsheetProcessor->new(@_);

    bless($self,$class);

    return $self;

}

sub init_reader_context {

    my $self = shift;
    my ($context) = @_;

    my ($sheets,$error) = _read_package($context->{filename});
    $context->{sheet} = undef;
    $context->{rows} = [];
    $context->{row_index} = 0;

    if (not defined $sheets) {
        fileerror('processing file - error reading file ' . $context->{filename} . ': ' . $error,getlogger(__PACKAGE__));
    } else {
        my $sheet;
        if ($context->{sheet_name}) {
            foreach my $candidate (@$sheets) {
                $sheet = $candidate if $candidate->{name} eq $context->{sheet_name};
            }
        } else {
            $sheet = $sheets->[0];
        }
        if (not defined $sheet) {
            fileerror("processing file - invalid spreadsheet '$context->{sheet_name}'",getlogger(__PACKAGE__));
        } else {
            $context->{sheet} = $sheet;
            $context->{rows} = $sheet->{rows};
            processing_info($context->{tid},"spreadsheet '" . $sheet->{name} . "'",getlogger(__PACKAGE__));
        }
    }

}

sub has_next_row {

    my $self = shift;
    my $context = shift;

    return 0 unless $context->{rows};
    my $index = $context->{row_index};
    return 0 if $index >= scalar @{$context->{rows}};
    $context->{row} = $context->{rows}->[$index];
    $context->{row_index} = $index + 1;
    return 1;

}

sub get_row {

    my $self = shift;
    my $context = shift;

    return [ @{$context->{row}} ];

}

sub get_sheet_names {

    my $self = shift;
    my $file = shift;

    my ($sheets,$error) = _read_package($file);
    die $error unless defined $sheets;
    return map { $_->{name} ; } @$sheets;

}

sub _read_package {

    my ($file) = @_;

    my $parser = Spreadsheet::ParseXLSX->new();
    my $opened = eval { $parser->parse($file); 1 };
    if (not $opened) {
        my $error = $@ || 'cannot read workbook';
        $error =~ s/\s+\z//;
        return (undef,$error);
    }

    my $zip = Archive::Zip->new();
    if ($zip->read($file) != AZ_OK) {
        return (undef,'cannot read workbook zip');
    }

    my $strings = _shared_strings($zip);
    my $rels = _workbook_rels($zip);
    my $workbook = _xml($zip,'xl/workbook.xml');
    return (undef,'workbook.xml missing') unless defined $workbook;

    my @sheets = ();
    foreach my $node ($workbook->findnodes('//*[local-name()="sheets"]/*[local-name()="sheet"]')) {
        my $name = $node->getAttribute('name');
        my $rid = $node->getAttributeNS($REL_NS,'id');
        $rid = $node->getAttribute('r:id') unless defined $rid;
        my $target = defined $rid ? $rels->{$rid} : undef;
        my $path = _package_path($target);
        my $rows = defined $path ? _sheet_rows($zip,$path,$strings) : [];
        push(@sheets,{ name => $name, rows => $rows });
    }

    return (\@sheets,undef);

}

sub _shared_strings {

    my ($zip) = @_;

    my @strings = ();
    my $doc = _xml($zip,'xl/sharedStrings.xml');
    return \@strings unless defined $doc;
    foreach my $si ($doc->findnodes('//*[local-name()="si"]')) {
        push(@strings,$si->textContent());
    }
    return \@strings;

}

sub _workbook_rels {

    my ($zip) = @_;

    my %rels = ();
    my $doc = _xml($zip,'xl/_rels/workbook.xml.rels');
    return \%rels unless defined $doc;
    foreach my $rel ($doc->findnodes('//*[local-name()="Relationship"]')) {
        my $id = $rel->getAttribute('Id');
        $rels{$id} = $rel->getAttribute('Target') if defined $id;
    }
    return \%rels;

}

sub _sheet_rows {

    my ($zip,$path,$strings) = @_;

    my $doc = _xml($zip,$path);
    return [] unless defined $doc;

    my @rows = ();
    foreach my $row ($doc->findnodes('//*[local-name()="row"]')) {
        my @vals = ();
        my $max = -1;
        foreach my $cell ($row->findnodes('./*[local-name()="c"]')) {
            my $ref = $cell->getAttribute('r');
            last unless defined $ref and $ref ne '';
            my $col = _col_index($ref);
            last unless defined $col;
            my $type = $cell->getAttribute('t') // '';
            my $value = '';
            foreach my $child ($cell->childNodes()) {
                next unless $child->nodeType == XML::LibXML::XML_ELEMENT_NODE;
                my $name = $child->localname();
                if ($name eq 'v' or $name eq 'is') {
                    $value = $child->textContent();
                }
            }
            if ($type eq 's') {
                $value = (defined $strings->[$value] ? $strings->[$value] : '');
            }
            $vals[$col] = $value;
            $max = $col if $col > $max;
        }
        my @rowvals = ();
        @rowvals = @vals[0 .. $max] if $max >= 0;
        push(@rows,\@rowvals);
    }
    return \@rows;

}

sub _package_path {

    my ($target) = @_;

    return undef unless defined $target and $target ne '';
    $target =~ s{\\}{/}g;
    $target =~ s{^\./}{};
    if ($target =~ m{^/}) {
        $target =~ s{^/}{};
        return $target;
    }
    return $target if $target =~ m{^xl/};
    return 'xl/' . $target;

}

sub _col_index {

    my ($ref) = @_;

    return undef unless defined $ref and $ref =~ /^([A-Za-z]+)/;
    my $col = uc $1;
    my $n = 0;
    foreach my $ch (split //,$col) {
        $n = $n * 26 + (ord($ch) - ord('A') + 1);
    }
    return $n - 1;

}

sub _xml {

    my ($zip,$name) = @_;

    my $member = $zip->memberNamed($name);
    return undef unless defined $member;
    my $parser = XML::LibXML->new();
    return $parser->parse_string($member->contents());

}

1;
