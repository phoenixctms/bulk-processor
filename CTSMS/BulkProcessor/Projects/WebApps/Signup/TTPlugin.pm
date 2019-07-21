package CTSMS::BulkProcessor::Projects::WebApps::Signup::TTPlugin;
use base qw( Template::Plugin );
use Template::Plugin;
use CTSMS::BulkProcessor::Utils qw();

sub new {
    my $class   = shift;
    my $context = shift;
    bless { context => $context, }, $class;
}

sub stringtobool {
    my ($self,$string) = @_;
    return CTSMS::BulkProcessor::Utils::stringtobool($string);
}

#sub test {
#    return "test";
#}

1;