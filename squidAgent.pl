#!/usr/bin/perl

my $Version = '20090202';

my $arc_mode;
my $log_to_arc;
my $arc_ts;

if ($ARGV[0])
{
	my $run_opt = $ARGV[0];
	$log_to_arc = $ARGV[1];
	my $run_subopt = $ARGV[2];
	$arc_ts = $ARGV[3];
	if ($run_opt eq '-V')
	{
		die "$Version\n";
	}
	elsif ($run_opt eq '-archive')
	{
		$arc_mode = 1;
		die "Cant find logfile ($log_to_arc)!\n"
			unless -e $log_to_arc;
		if ($run_subopt eq '-start_ts')
		{
			die "Invalid timestamp to start from ($arc_ts)!\n"
				unless $arc_ts =~ /^\d+(\.\d+)?$/;
		}
		else
		{
			die "Unknown archive suboption ($run_subopt)! Expected \'-start_ts timestamp\'\n";
		}
	}
	else
	{
		die "Unknown run option ($run_opt)! Expected \'-archive /path/to/logfile\'\n";
	};
};

use strict;
use POSIX qw(strftime);
use SQLayer;
use IO::Handle;
use DaemonLib;

# Disable output buffering
$|=1;           

if (($> == 0) or ($< == 0))
{
	die "Do not run me as root! Its dangerous.\n";
};

my $DLib = DaemonLib->new
(
	logfacility 	=> 'LOG-AGENT'
);

my %config; # = $DLib->get_config_from_file("/usr/local/etc/sparrow.conf"); 
dbmopen(%config, "/var/db/sparrow/config", 0660)
	or $DLib->dielog("Cant open config hash (/var/db/sparrow/config): $!");

# there is nothing harmful if no debug defined by default
$DLib->debug($config{'debug'});

my $squid_accesslog		= $config{'squid_access_log'};
$squid_accesslog 		= $log_to_arc if $arc_mode;
my $pidfile				= $config{'squid_log_agent_pidfile'};
my $count_cached 		= $config{'count_cached_requests'};
my $statis_timepoint	= $config{'statis_timepoint'};

# Now, we should not work if:
$DLib->dielog("Logfile not defined!") unless $config{'logfile'};
$DLib->logfile($config{'logfile'});
$DLib->dielog("No pidfile defined!") unless $pidfile;
$DLib->dielog("Agent already running.") if $DLib->checkpid_byfile($pidfile);
$DLib->dielog("Cant write PID file $pidfile! $!") unless $DLib->writepid_tofile($pidfile);
$DLib->dielog("There is no statis_timepoint defined yet!") unless $statis_timepoint;

# Database connection is mandatory
my $D = SQLayer -> new
(
        database 	=> 'DBI:Pg:dbname='.$config{'dbname'},
        user 		=> $config{'dbuser'},
        password 	=> $config{'dbpassword'}
);
$DLib->dielog("Database ".$config{'dbname'}." connection failed!".$D->errstr) 
	unless $D->{'dbh'}->ping;
$D -> DEBUG(1) if $config{'debug'};

# now we are ready to process squid's access log
open (MAINLOG, $squid_accesslog) 
	or $DLib->dielog("Cant open access log for reading $squid_accesslog: $!!");

if ($arc_mode)
{
	$DLib->debuglog("Archive log started (parsing $squid_accesslog, skip till $arc_ts)...\n");
	$statis_timepoint = $arc_ts;
}
else
{
	$DLib->debuglog("Started (watching $squid_accesslog).");
};

my %id_stats;

my $timestamp;
my $current_day;
my $log_str_counter = 0;
while (<MAINLOG>)
{
	chomp;
	my @record = split(/\s+/);

	# Skip all processed log records
	$timestamp		= $record[0];
	next if $statis_timepoint > $timestamp;
	next if $statis_timepoint == $timestamp;
#	$DLib->debuglog("statis_timepoint=$statis_timepoint record_timepoint=$timestamp");

	# stop collecting if the date has changed
	my $rec_day = strftime("%Y-%m-%d", localtime($timestamp)); # ex: 1999-01-08 -- ISO 8601
	$current_day = $rec_day unless $current_day;
	if ($rec_day ne $current_day)
	{
		$DLib->writelog("The date has changed. Was $current_day (acct date), now $rec_day.");
		last;
	};

	my $bytes 		= $record[4];
	my $ident 		= $record[7];
	my $url			= $record[6];
	my $http_code 		= $record[3];
	my $ip			= $record[2];

	# assume IP for id, if no ident present
	$ident = $ip if $ident eq '-';

	# Skip all invalid records
	unless (defined validcode($http_code))
	{
		$DLib->debuglog("Negative request ($http_code), skipped.");
		next;
	};
	if ((validcode($http_code) eq "true") and ($count_cached eq "0"))
	{
		$DLib->debuglog("Positive cached request ($http_code), but count_cached_requests is off. Skipped.");	
		next;
	};	


	# Now, prepare the sitename ...
	my $sitename;
	if ($url =~ /\:\/\/([\@\w\d\.\-\:]+)\//)
	{
		$sitename = $1;
	}
	elsif ($url =~ /([\@\w\d\.\-\:]+\:\d{1,5})/)
	{
		$sitename = $1;
	}
	else
	{
		$sitename = "<invalid>";
	};

	$DLib->debuglog("time=$timestamp id=$ident [$ip] traffic=$bytes site=$sitename [$url]");

	# create an empty hash with site's statistics for login, if it doesnt exists
	$id_stats{$ident} = {} unless exists $id_stats{$ident};
	# count traffic
	if (exists ${$id_stats{$ident}}{$sitename})
	{
		# add for site
		${$id_stats{$ident}}{$sitename} += $bytes;
	}
	else
	{
		# create for site
		${$id_stats{$ident}}{$sitename} = $bytes;
	};
	$log_str_counter++;
};

# no modification of config hash needed, when running in -archive mode
unless ($arc_mode)
{
	# remember last processed record (by timestamp)
	# do not touch statis_timepoint if no records processed
	$config{'statis_timepoint'} = $timestamp if $timestamp;
	$config{'squid_log_agent_lastrun'} = time;
	$DLib->debuglog("lastrun time set: ".scalar(localtime($config{'squid_log_agent_lastrun'})));
};

dbmclose(%config)
	or $DLib->writelog("WARNING Cant close config hash: $!");

# now update all clients bytecounters with collected stats
# input data struct:
# id_stats hash 	-|| ident => site_stat (hashref)
# site_stat hash 	-|| sitename => bytes (integer)
while (my ($name, $site_stat) = each %id_stats)
{
	unless ($D->row("SELECT id FROM clients WHERE id = ".$D->quote($name).";"))
	{
		# client doesnt exists
		$DLib->writelog("WARNING Client id $name doesnt exists!");
		next;
	};
	my $overall_traffic = 0;
	while (my ($site, $traffic) = each %{$site_stat})
	{
		$overall_traffic += $traffic;
		# update per site statistics
		if ($D->row("SELECT site FROM statis_summary WHERE site = ".
			$D->quote($site)." AND id = ".$D->quote($name).
			" AND stat_day = ".$D->quote($current_day).";"))
		{
			# site exists - 
			if (
				$D->proc("UPDATE statis_summary SET bytecounter = bytecounter + ".
					$D->quote($traffic)." WHERE id = ".$D->quote($name).
					" AND site = ".$D->quote($site).
					" AND stat_day = ".$D->quote($current_day)." ;")
			)
			{
				# update successful
				$DLib->debuglog("Site $site for client id $name updated with $traffic bytes.");
			}
			else
			{
				# sql error on update?
				$DLib->writelog("WARNING Cant update site $site for client id $name with ".
					"traffic $traffic bytes: ".$D->errstr);
			};
		}
		else
		{
			# site doesnt exists - 
			if (
				$D->proc("INSERT INTO statis_summary (bytecounter, id, site, stat_day) values (".
					$D->quote($traffic).", ".$D->quote($name).", ".$D->quote($site).
					", ".$D->quote($current_day).");")
			)
			{
				# insert successful
				$DLib->debuglog("Site $site for client id $name created with $traffic bytes.");
			}
			else
			{
				# sql error on insert?
				$DLib->writelog("WARNING Cant create (insert) site $site for client id $name with ".
					"traffic $traffic bytes: ".$D->errstr);
			};
		};
	};

	unless ($arc_mode)
	{
		# update overal client statistics
		# client exists - 
		if (
			$D -> proc("UPDATE clients SET bytecounter = bytecounter + ".$D->quote($overall_traffic).
				" WHERE id = ".$D->quote($name).";")
		   )
		{
			# update successful
			$DLib->debuglog("Client id $name updated with $overall_traffic bytes.");
		}
		else
		{
			# sql error on update?
			$DLib->writelog("WARNING Cant update client id $name with $overall_traffic bytes: ".$D->errstr);
		};
	};
};

close(MAINLOG);
$DLib->debuglog("Work done ($log_str_counter log records processed). Exiting...");

if ($arc_mode and $log_str_counter)
{
	warn "Archive for $current_day completed using log $squid_accesslog (started from $arc_ts). \n".
		"If you want to archive next day from this log, run again with -start_ts=$timestamp\n";
};
unlink($pidfile) or $DLib->writelog("WARNING Could not remove $pidfile: $!");
exit;

# returns:
#  - true: positive answer, served from cache.
#  - false: positive answer, served directly.
#  - undef: negative answer (e.g. denied access - usually no ident recorded). 
sub validcode 
{
	my $code = shift;
	return "true" if $code =~ /^(TCP_HIT|TCP_MEM_HIT|TCP_NEGATIVE_HIT|TCP_REFRESH_HIT|TCP_REF_FAIL_HIT|TCP_IMS_HIT|TCP_MEM_HIT|TCP_OFFLINE_HIT|UDP_HIT)/i;
	return "false" if $code =~ /^(TCP_MISS|TCP_REFRESH_MISS|TCP_CLIENT_REFRESH_MISS|TCP_SWAPFAIL_MISS|UDP_MISS|UDP_MISS_NOFETCH|TCP_CLIENT_REFRESH|TCP_SWAPFAIL|TCP_IMS_MISS|UDP_HIT_OBJ|UDP_RELOADING)/i;
	return undef;
}
