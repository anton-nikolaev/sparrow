#!/usr/bin/perl

my $Version = '20090504';

if ($ARGV[0] eq '-V')
{
	die "$Version\n";
};

my $acl_type = $ARGV[0];

use SQLayer;
use strict;
use DaemonLib;
use Net::Subnets;

if (($> == 0) or ($< == 0))
{
	die "Do not run me as root! Its dangerous.\n";
};

# Disable output buffering
$|=1;           

$SIG{TERM} = 'self_destroy';
$SIG{KILL} = 'self_destroy';
$SIG{INT} = 'self_destroy';
$SIG{QUIT} = 'self_destroy';
$SIG{ABRT} = 'self_destroy';

my $DLib = DaemonLib->new
(
	logfacility 	=> 'EXT-ACL!'.uc($acl_type)
);

my %config; # = $DLib->get_config_from_file("/usr/local/etc/sparrow.conf"); 
dbmopen(%config, "/var/db/sparrow/config", 0660)
	or $DLib->dielog("Cant open config hash (/var/db/sparrow/config): $!");

# there is nothing harmful if no debug defined by default
$DLib->debug($config{'debug'});

$DLib->dielog("Logfile not defined!") unless $config{'logfile'};
$DLib->logfile($config{'logfile'});

my $D = SQLayer -> new
(
        database 	=> 'DBI:Pg:dbname='.$config{'dbname'},
        user 		=> $config{'dbuser'},
        password 	=> $config{'dbpassword'}
);
$DLib->dielog("Database ".$config{'dbname'}." connection failed!".$D->errstr) 
	unless $D->{'dbh'}->ping;
$D->DEBUG(1) if $config{'debug'};

my $sql_query;
if ($acl_type eq 'user_access')
{
	$sql_query = "SELECT cache_access FROM clients WHERE is_workstation = false AND id = ";
	$config{'def_user_access'} = 1;
	$config{'def_ip_access'} = 0;
}
elsif ($acl_type eq 'ip_access')
{
	$sql_query = "SELECT cache_access FROM clients WHERE is_workstation = true AND id = ";
	$config{'def_user_access'} = 0;
	$config{'def_ip_access'} = 1;
}
else
{
	die "Unknown acl_type: $acl_type!\n".
		"Usage: $0 ip_access\n".
		"       $0 user_access\n";
};

dbmclose(%config);

# Usually squid starts multiple copies of external_acl helper, so 
# it would be nice to see PID in log.
$DLib->include_pid_in_log(1);

$DLib->writelog("NOTICE Ready to serve squid queries.");

# Read squid's access query 
while (<STDIN>) 
{
	chomp;

	# refuse all queries, if squidAgent doesnt run within 5 minutes (300 sec)
	dbmopen(%config, "/var/db/sparrow/config", 0660)
		or $DLib->dielog("Cant open config hash (/var/db/sparrow/config): $!");
	if (($config{'squid_log_agent_lastrun'} + 300) < time)
	{
		$DLib->debuglog("SquidAgent last run over 5 minutes ago (".
			scalar(localtime($config{'squid_log_agent_lastrun'})).")!");
		print "ERR\n";
		dbmclose(%config);
		next;
	};
	my $login_ip_acl_enabled = 1 if $config{"client_ip_acl"};
	dbmclose(%config);

	my ($client_id, $src_ip) = $DLib->extract_shellwords($_);
	
	if ($login_ip_acl_enabled)
	{
		# only logins (not IPs) should be checked in ip-acls
		unless ($D->row("SELECT is_workstation FROM clients ".
				"WHERE id = ".$D->quote($client_id).";"))
		{
			my $client_subnets = Net::Subnets -> new();
			# check if this id limited by ip
			my @client_lim_nets = 
				$D->column("SELECT ip_addr FROM client_ip_acl ".
				"WHERE client_id = ".$D->quote($client_id).";");
			if (@client_lim_nets >= 1)
			{
				$client_subnets->subnets(\@client_lim_nets);
				if (my $limit_ref = $client_subnets->check(\$src_ip))
				{
					$DLib->debuglog("Client $client_id ".
							"from $src_ip (limit match $$limit_ref).");
				}
				else
				{
					$DLib->debuglog("Client $client_id access denied ".
							"from $src_ip (no match with limit items).");
					print "ERR\n";
					next;
				};
			}
			else
			{
				$DLib->debuglog("Client $client_id doesnt have any IP-limitations.");
			};
		};
	};

	if ($D -> row($sql_query.$D->quote($client_id).";"))
	{
		$DLib->debuglog("Reply positive for $client_id.");
		print "OK\n";
	}
	else
	{
		$DLib->debuglog("Reply negative for $client_id.");
		print "ERR\n";
	}	
}

sub self_destroy
{
        $DLib->writelog("NOTICE Exiting via SIGnal.");
        exit;
}
