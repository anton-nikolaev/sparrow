#!/usr/bin/perl

# Sparrow Periodic maintenance. Run from cron daily.

my $Version = '20090504';

if ($ARGV[0] eq '-V')
{
	die "$Version\n";
};

use SQLayer;
use strict;
use POSIX qw(strftime);
use DaemonLib;

# rotate_needed	(
#	cur_time => time, 
#	max_period_size => 604800, 
#	period_started_at => 1231325477
# );
sub rotate_needed
{
	my %HKeys = @_;
	my $cur_time 		= $HKeys{'cur_time'};
	my $period_started_at 	= $HKeys{'period_started_at'};
	my $max_period_size 	= $HKeys{'max_period_size'};

	# size is in seconds.
	my $cur_period_size = $cur_time - $period_started_at;
	unless ($max_period_size)
	{
		# size is not set.
		# this means, that we should rotate every month.
		my $period_start_month = (localtime($period_started_at))[4];
		my $cur_month = (localtime($cur_time))[4];
		# this should do the trick at most cases (rotate appears, when 
		# month changes - usually at 1 date).
	 	return 1 if $period_start_month != $cur_month;
		# this should work in all other (not common) cases.
		# for example: when this script was not ran for a year,
		# so month remains the same (but year has changed).
		return 1 if $cur_period_size > 2592000; # 30 days in seconds
	}
	else
	{
		return 1 if $cur_period_size > $max_period_size;
	};
	return 0;
};

if (($> == 0) or ($< == 0))
{
	die "Do not run me as root! Its dangerous.\n";
};

my $DLib = DaemonLib->new
(
	logfacility 	=> 'PERIODIC'
);

my %config; # = $DLib->get_config_from_file("/usr/local/etc/sparrow.conf"); 
dbmopen(%config, "/var/db/sparrow/config", 0660)
	or $DLib->dielog("Cant open config hash (/var/db/sparrow/config): $!");

# there is nothing harmful if no debug defined by default
$DLib->debug($config{'debug'});

#my $rotated_accesslog	= $config{'rotated_accesslog'};
#my $archive_dir	= $config{'statis_archive_dir'};
#my $zero_bytecounter 	= $config{'zero_bytecounter_on_period'};
#my $squid_accesslog	= $config{'squid_access_log'};
my $squid_bin		= $config{'squid_bin'};
my $pidfile		= $config{'periodic_pidfile'};
my $access_log		= $config{'squid_access_log'};
my $period_started_at	= $config{'cur_period_start_timepoint'};
my $max_period_size	= $config{'max_period_size'};
my $archive_path = $config{"archive_basedir"};

# Now, we should not work if:
$DLib->dielog("Logfile not defined!") unless $config{'logfile'};
$DLib->logfile($config{'logfile'});
$DLib->dielog("No pidfile defined!") unless $pidfile;
$DLib->dielog("Already running.") if $DLib->checkpid_byfile($pidfile);
$DLib->dielog("Cant write PID file $pidfile! $!") unless $DLib->writepid_tofile($pidfile);
$DLib->dielog("Archive basedir ($archive_path) doesnt exists!") unless -d $archive_path;

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

$DLib->debuglog("All checks done well. Database (".$config{'dbname'}.") connected.");
my $cur_time = time;

# select all dates (except for today) available from statis_summary table
my @all_dates = 
	$D->column("SELECT stat_day FROM statis_summary ".
			"WHERE stat_day != \'today\' GROUP BY stat_day ORDER BY stat_day;");

# dump statis from database to archive for selected dates
my $cur_date;
foreach $cur_date (@all_dates)
{
	# prepare archive directory for current date
	my $cur_archive_path = $archive_path;
	foreach (split(/\-/, $cur_date))
	{
		$cur_archive_path .= "/".$_;
		if (-d $cur_archive_path)
		{
			$DLib->debuglog("Directory $cur_archive_path exists.");
			next;
		}; 
		mkdir ($cur_archive_path)
		or do
		{
			$DLib->writelog("WARNING Cant create $cur_archive_path: $!");
			last;
		};
		$DLib->debuglog("Directory $cur_archive_path created.");
	};
	unless (-d $cur_archive_path)
	{
		$DLib->writelog("WARNING Archive path for $cur_date not prepared! Date skipped.");
		next;
	};
	
	# select all clients for current date
	my @cur_clients = $D->column("SELECT id, sum(bytecounter) as bytes FROM statis_summary ".
							"WHERE stat_day = ".$D->quote($cur_date).
							" GROUP BY id ORDER BY bytes DESC;");
	
	# dump statis to archive
	open(DATE_ARC, ">$cur_archive_path/TOTAL.txt")
	or do
	{
		$DLib->writelog("WARNING Cant open TOTAL archive in $cur_archive_path: $!");
		next;
	};
	my $cur_id;
	foreach $cur_id (@cur_clients)
	{	
		open(CLIENT_ARC, ">$cur_archive_path/$cur_id.txt")
		or do
		{
			$DLib->writelog("WARNING [Client id = $cur_id] Cant open archive $cur_archive_path/$cur_id: $!");
			next;
		};
		print CLIENT_ARC "\$DESCR=".$D->row("SELECT descr FROM clients WHERE id = ".$D->quote($cur_id).";")."\n";
		foreach ($D->column("SELECT site ".
					"FROM statis_summary ".
					"WHERE stat_day = ".$D->quote($cur_date).
					" AND id = ".$D->quote($cur_id)." ORDER BY bytecounter DESC;"))
		{
			print CLIENT_ARC "$_ ".$D->row("SELECT bytecounter FROM statis_summary ".
					"WHERE stat_day = ".$D->quote($cur_date)." AND id = ".$D->quote($cur_id).
					" AND site = ".$D->quote($_).";")."\n";
		};
		close(CLIENT_ARC);	
		$DLib->debuglog("Date $cur_date archive for $cur_id dumped to file $cur_archive_path/$cur_id.txt.");
		print DATE_ARC 	"$cur_id " .
						$D->row("SELECT sum(bytecounter) FROM statis_summary ".
								"WHERE stat_day = ".$D->quote($cur_date).
								" AND id = ".$D->quote($cur_id).";") .
						" " .
						$D->row("SELECT descr FROM clients WHERE id = ".$D->quote($cur_id).";") . 
						"\n";
	};
	close(DATE_ARC);
	$DLib->debuglog("Date $cur_date TOTAL archive dumpted to file $cur_archive_path/TOTAL.txt.");
	
	# clear statis for current date
	if ($D->proc("DELETE FROM statis_summary WHERE stat_day = ".$D->quote($cur_date).";"))
	{
		$DLib->writelog("Summary statis for date $cur_date cleared.");
	}
	else
	{
		$DLib->writelog("WARNING Table statis_summary with date $cur_date cleanup failed: ".$D->errstr);
	};
}; # foreach $cur_date (@all_dates)
$DLib->debuglog("No dates to dump to archive for now.");

########################################
# now, make stats for years and months #
my $arc_year;
foreach $arc_year (get_stat_dir_list($archive_path))
{
	$DLib->debuglog("Looking for stat in year $arc_year ...");
	my $arc_month;
	foreach $arc_month (get_stat_dir_list("$archive_path/$arc_year"))
	{
		# running over months ...
		$DLib->debuglog("Looking for stat in month $arc_month (year $arc_year) ...");
		# do not try to process stats for month, if next month hasnt been started
		my $next_month_path;
		if ($arc_month eq '12')
		{
			# check next year, if this is the last month or this year
			$next_month_path = "$archive_path/".($arc_year + 1);
			unless (-d $next_month_path)
			{
				$DLib->debuglog("Archive for January ".($arc_year + 1).
					" doent exists, so this month (December $arc_year) appears to be active. ".
					"Skipped for now. Checked next month path = $next_month_path.");
				next;
			};
		}
		else
		{
			# check next month
			$next_month_path = "$archive_path/$arc_year/".sprintf("%02d", ($arc_month + 1));
			unless (-d $next_month_path)
			{
				$DLib->debuglog("Archive for month (".($arc_month + 1)." $arc_year) doesnt exists, ".
					"so this month ($arc_month $arc_year) appears to be active. Skipped for now.".
					" Checked next month path = $next_month_path.");
				next;
			};
		};
		my $month_path = "$archive_path/$arc_year/$arc_month";
		if ((-e "$month_path/DAYS.txt") and (-e "$month_path/TOTAL.txt"))
		{
			$DLib->debuglog("Overall stat for month ($arc_month $arc_year) already exists. Skipped.");
			next;
		};
		$DLib->debuglog("Month ($arc_month) of the year ($arc_year) not processed yet.");
		open (MONTHLY_DAYS, ">$month_path/DAYS.txt") # dates with bytes for this month
		or do
		{
			$DLib->writelog("WARNING Cant open $month_path/DAYS.txt for writing: ".$!);
			next;
		};
		my $s_date;
		my %monthly_users; # id -- bytes
		my %monthly_sites; # monthly site -- bytes
		my %id_descr; # id -- descr
		foreach $s_date (get_stat_dir_list($month_path))
		{
			# running over dates ...
			open (DAY_TOTAL, "$month_path/$s_date/TOTAL.txt")
			or do
			{
				$DLib->writelog("WARNING Cant open $month_path/$s_date/TOTAL.txt for reading: ".$!);
				next;
			};
			my $date_cnt = 0;
			my @date_users;
			while (<DAY_TOTAL>)
			{
				chomp;
				/^(\S+)\s+(\S+)\s+(.*)$/;
				my ($id, $cnt, $descr) = ($1, $2, $3);
				next if $cnt !~ /^\d+$/; # counter should be numeric
				# fill up hash with bytes by id
				$monthly_users{$id} = 
					(exists $monthly_users{$id}) ? 
					($monthly_users{$id} + $cnt) : 0; 
				$id_descr{$id} = $descr; # id description from last day will be used below
				push (@date_users, $id); # users at this date
				$date_cnt += $cnt; # this date counter
			};
			close(DAY_TOTAL);
			print MONTHLY_DAYS "$s_date $date_cnt\n"; # date -- bytes
			foreach (@date_users)
			{
				# running over users at this date ...
				open (DAY_ID, "$month_path/$s_date/$_.txt")
				or do
				{
					$DLib->writelog("WARNING Cant open $month_path/$s_date/$_.txt for reading: ".$!);
					next;
				};
				while (<DAY_ID>)
				{
					chomp;
					my ($site, $cnt) = split(/\s+/);
					next if $cnt !~ /^\d+$/; # counter should be numeric
					$monthly_sites{$site} = 
						(exists $monthly_sites{$site}) ?
						($monthly_sites{$site} + $cnt) : 0;
				};
				close(DAY_ID);
			};
			open (DAY_SITES, ">$month_path/DAY-$s_date.txt")
			or do
			{
				$DLib->writelog("WARNING Cant open $month_path/DAY-$s_date.txt for writing: ".$!);
			};
			foreach (keys %monthly_sites)
			{
				print DAY_SITES $_." ".$monthly_sites{$_}."\n"; # site -- bytes
			};
			close(DAY_SITES);
			$DLib->writelog("Monthly date ($s_date) stats (sites with bytes) ".
				"for month ($arc_month) dumped to file $month_path/$s_date.txt.");
		}; # // foreach $s_date (get_stat_dir_list($month_path))
		close(MONTHLY_DAYS);
		$DLib->writelog("Monthly days stats (dates with bytes) for month ($arc_month) ".
				"dumped to file $month_path/DAYS.txt.");
		open (MONTHLY_TOTAL, ">$month_path/TOTAL.txt") # users with bytes for this month
		or do
		{
			$DLib->writelog("WARNING Cant open $month_path/TOTAL.txt for writing: ".$!);
			next;
		};
		foreach (keys %monthly_users)
		{
			print MONTHLY_TOTAL $_." ".$monthly_users{$_}." ".$id_descr{$_}."\n"; # id -- bytes -- descr
		};
		close(MONTHLY_TOTAL);
		$DLib->writelog("Monthly total stats (users with bytes) for month ($arc_month) ".
			"dumped to file $month_path/TOTAL.txt.");
		my $month_user;
		$s_date = "";
		foreach $month_user (keys %id_descr)
		{
			# running over users at this month ...
			open (MONTHLY_USER, ">$month_path/$month_user.txt")
			or do
			{
				$DLib->writelog("WARNING Cant open $month_path/$month_user.txt for writing: ".$!);
				next;
			};
			my %month_user_sites;
			foreach $s_date (get_stat_dir_list($month_path))
			{
				# running over dates at this month ...
				open (DAILY_USER_STAT, "$month_path/$s_date/$month_user.txt")
				or do
				{
#					$DLib->writelog("WARNING Cant open $month_path/$s_date/$month_user.txt for reading: ".$!);
					# user may not have any stats for particular date
					next;
				};
				while (<DAILY_USER_STAT>)
				{
					chomp;
					my ($site, $cnt) = split(/\s+/);
					next if $cnt !~ /^\d+$/; # counter should be numeric
					$month_user_sites{$site} = 
						(exists $month_user_sites{$site}) ?
						($month_user_sites{$site} + $cnt) : 0;
				};
				close(DAILY_USER_STAT);
			};
			print MONTHLY_USER "\$DESCR=".$id_descr{$month_user}."\n";
			foreach (keys %month_user_sites)
			{
				print MONTHLY_USER "$_ ".$month_user_sites{$_}."\n"; # site -- bytes
			};
			close(MONTHLY_USER);
			$DLib->writelog("Monthly user ($month_user) stats (sites with bytes) ".
				"for month ($arc_month) dumped to file $month_path/$month_user.txt.");
		};
	}; # // foreach $arc_month (get_stat_dir_list("$archive_path/$arc_year"))
};
# stats for years and months dump work completed #
##################################################

#foreach (sort keys %years)
#{
#	next unless /^\d{4}$/; # only years wanted
#	my $prev_year = $_ - 1;
#	my $prev_year_path = "$archive_path/$prev_year";
#	next unless -d $prev_year_path; # no year - no stats
#	next if -e $prev_year_path."/TOTAL.txt"; # year appears to be processed already
#	$DLib->debuglog("Year $prev_year archive not processed yet.");
#
#	unless (opendir(YEARDIR, $prev_year_path))
#	{
#		$DLib->writelog("WARNING Cant read directory content $prev_year_path (for overall stats).");
#	};
#	foreach (readdir(YEARDIR))
#	{
#		# wanted monthly directories only 
#		next unless -d $cur_archive_path."/$_";
#		next unless /^\d{2}$/; 
#		$DLib->debuglog("This dir entry ($_) appears to be monthly.");
#	};
#	closedir(YEARDIR);
#};

if (
	rotate_needed	(
		cur_time => $cur_time, 
		max_period_size => $max_period_size, 
		period_started_at => $period_started_at
	)
)
{
	# do log rotation with squid
	$DLib->dielog("Cant do $squid_bin -k rotate!") 
		if system("$squid_bin -k rotate");
	$DLib->debuglog("Squid logs rotated ($squid_bin -k rotate).");
	#sleep(30);

	# reset all bytecounters
	my $zeroed_counters = $D->proc("UPDATE clients SET bytecounter = 0;");
	$DLib->writelog("WARNING Cant reset bytecounters! ".$D->errstr) unless $zeroed_counters;
	$DLib->writelog("NOTICE $zeroed_counters bytecounters zeroed.") if $zeroed_counters;

	# create a new period
	$config{'cur_period_start_timepoint'} = $cur_time;
	$DLib->writelog("A new period start timepoint is: ".scalar(localtime($cur_time)));
};

unlink($pidfile);

# функция возвращает список директорий с архивами, если они вообще там есть
sub get_stat_dir_list
{
	my $listdir = shift;
	my @dir_list;
	opendir (LISTDIR, $listdir)	
		or die "Cant open $listdir for reading: $!\n";
	while (my $dir_entry = readdir (LISTDIR))
	{
		next unless $dir_entry =~ /^\d+$/; # only numeric directories wanted
		unless (-d "$listdir/$dir_entry")
		{
			# not a directory
			next;
		};
		push (@dir_list, $dir_entry);
	};
	closedir (LISTDIR);
	return @dir_list;
};

