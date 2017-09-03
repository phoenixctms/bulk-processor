#!/usr/bin/perl
use warnings;
use strict;

use File::Basename;
use Cwd;
use lib Cwd::abs_path(File::Basename::dirname(__FILE__) . '/../../../../');

use CTSMS::BulkProcessor::LoadConfig qw(
    load_config
);

use CTSMS::BulkProcessor::RestRequests::Trunk::SystemContacts qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::Contracts qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::Resellers qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::BillingProfiles qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::BillingZones qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::BillingFees qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::Domains qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::CustomerContacts qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::Customers qw();
use CTSMS::BulkProcessor::RestRequests::Trunk::Subscribers qw();

load_config('config.cfg');

{
    my $t = time();
    my $systemcontact_id = CTSMS::BulkProcessor::RestRequests::Trunk::SystemContacts::create_item({
        email => "test$t\@system.com",
    });
    my $contract_id = CTSMS::BulkProcessor::RestRequests::Trunk::Contracts::create_item({
   		contact_id => $systemcontact_id,
		billing_profile_id => 1, #default profile id
		type => 'reseller',
        status => 'active',
    });
    my $reseller_id = CTSMS::BulkProcessor::RestRequests::Trunk::Resellers::create_item({
        contract_id => $contract_id,
        name => "reseller$t",
        status => 'active',
    });

    my $billing_profile_id = CTSMS::BulkProcessor::RestRequests::Trunk::BillingProfiles::create_item({
        handle => "profile$t",
        name => "profile$t",
        reseller_id => $reseller_id,
    });

    my $billing_zone_id = CTSMS::BulkProcessor::RestRequests::Trunk::BillingZones::create_item({
        billing_profile_id => $billing_profile_id,
        zone => "zone$t",
    });

    my $billing_fee_id = CTSMS::BulkProcessor::RestRequests::Trunk::BillingFees::create_item({
        billing_profile_id => $billing_profile_id,
        billing_zone_id => $billing_zone_id,
                direction => 'out',
                destination => '.*',
                onpeak_init_rate        => 10,
                onpeak_init_interval    => 1,
                onpeak_follow_rate      => 5,
                onpeak_follow_interval  => 2,
                offpeak_init_rate        => 8,
                offpeak_init_interval    => 1,
                offpeak_follow_rate      => 4,
                offpeak_follow_interval  => 2,
    });

    my $success = CTSMS::BulkProcessor::RestRequests::Trunk::BillingFees::delete_item($billing_fee_id);

    my $contract = CTSMS::BulkProcessor::RestRequests::Trunk::Contracts::set_item($contract_id,{
   		contact_id => $systemcontact_id,
		billing_profile_id => $billing_profile_id,
		type => 'reseller',
        status => 'active',
    });

    $contract = CTSMS::BulkProcessor::RestRequests::Trunk::Contracts::update_item($contract_id,{
   		contact_id => $systemcontact_id,
		billing_profile_id => $billing_profile_id,
		#type => 'reseller',
        status => 'active',
    });

    my $domain_id = CTSMS::BulkProcessor::RestRequests::Trunk::Domains::create_item({
        domain => "test$t.com",
        reseller_id => $reseller_id,
    });

    my $customercontact_id = CTSMS::BulkProcessor::RestRequests::Trunk::CustomerContacts::create_item({
        email => "test$t\@customer.com",
        reseller_id => $reseller_id,
    });

    my $customer_id = CTSMS::BulkProcessor::RestRequests::Trunk::Customers::create_item({
		contact_id => $customercontact_id,
		billing_profile_id => $billing_profile_id,
        status => "active",
		type => "sipaccount",
    });

    my $subscriber_id = CTSMS::BulkProcessor::RestRequests::Trunk::Subscribers::create_item({
        customer_id => $customer_id,
        domain_id => $domain_id,
        username => "subscriber$t",
        password => "subscriber$t",
        primary_number => { cc => '99', ac=> '', sn => '12345678' },
    });

    $success = CTSMS::BulkProcessor::RestRequests::Trunk::Subscribers::delete_item($subscriber_id);

    my $customer = CTSMS::BulkProcessor::RestRequests::Trunk::Customers::update_item($customer_id,{
        status => "terminated",
    });

    $customer_id = CTSMS::BulkProcessor::RestRequests::Trunk::Customers::create_item({
		contact_id => $customercontact_id,
		billing_profile_id => $billing_profile_id,
        status => "active",
		type => "sipaccount",
    });

    $subscriber_id = CTSMS::BulkProcessor::RestRequests::Trunk::Subscribers::create_item({
        customer_id => $customer_id,
        domain_id => $domain_id,
        username => "subscriber$t",
        password => "subscriber$t",
        primary_number => { cc => '99', ac=> '', sn => '12345678' },
    });

    print "blah";
}

exit;
