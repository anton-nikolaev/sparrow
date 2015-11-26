#!/usr/bin/perl -w

# Ётот скрипт занимаетс€ отображением и редактированием
# системных настроек.

my $SSIDNAME = 'SPARROW_SSID';

my $week_seconds = 601200; # 6 дней и 23 часа
my $two_week_seconds = 1206000; # 13 дней 23 часа
my $day_seconds = 82800; # 23 часа
my $max_squid_agent_idle_time = 300; # 5 минут

use strict;
use CGI::Simple;
use HTML::Template;
use CGI::Session;
use POSIX qw(strftime);

CGI::Session->name($SSIDNAME);

my $cgi = CGI::Simple -> new;
my $http_header = $cgi->header(-charset=>'auto', -expires=>'+1s');

my %config; 
dbmopen(%config, "/var/db/sparrow/config", 0660)
	or die("Cant open config hash (/var/db/sparrow/config): $!\n");
my $tmpl_dir = $config{'tmpl_dir'};
my $dbname = $config{'dbname'};
my $dbuser = $config{'dbuser'};
my $dbpassword = $config{'dbpassword'};

dbmclose(%config);
die("Configuration variable tmpl_dir is empty!\n") unless $tmpl_dir;

my $tmpl;

my $cookie = $cgi->cookie($SSIDNAME);

my $remote_host = $ENV{'REMOTE_ADDR'};
$remote_host = $ENV{'REMOTE_HOST'} unless $remote_host;

# ≈сли не удалось определить IP узла - ругаемс€
unless ($remote_host)
{
	$tmpl = HTML::Template->new(filename => $tmpl_dir.'/not_traceable.html');
	print STDOUT $http_header . $tmpl->output;
	exit;
};

my $cgi_ss = CGI::Session->load($cookie)
	or die CGI::Session->errstr();
my $ident = $cgi_ss->param('ident');

# ѕровер€ем сессию
my $reauth_needed = 0;
$reauth_needed = 1 if $cgi_ss->is_empty;
$reauth_needed = 1 if $cgi_ss->is_expired;
$reauth_needed = 1 if $cgi_ss->param('remote_host')	ne $remote_host;
$reauth_needed = 1 unless $ident;

# «апрашиваем авторизацию, если сесси€ не нравитс€
if ($reauth_needed)
{
	$tmpl = HTML::Template->new(filename => $tmpl_dir.'/reauth_needed.html');
	print STDOUT $http_header.$tmpl->output;
	exit;
};

use SQLayer;
my $D = SQLayer -> new
(
	database    => 'DBI:Pg:dbname='.$dbname,
	user        => $dbuser,
	password    => $dbpassword
);

die "No database connection: ".$D->errstr."\n" unless $D->{'dbh'}->ping();

# ќпредел€ем привелегии 
my $is_admin = $D->row("SELECT is_admin FROM clients WHERE id = ".$D->quote($ident).";");

# ќбычным пользовател€м запрещено мен€ть настройки системы
die("Unpriveleged attempt for $ident to work with system preferences!\n")
	unless $is_admin;

my $action = $cgi->param('action');
my $new_value = $cgi->param('new_value');

if ($action eq 'ch_ccreq')
{
	ch_pref_param('count_cached_requests', $new_value);
}
elsif ($action eq 'ch_null_pwd')
{
	ch_pref_param('null_passwords_allowed', $new_value);
}
elsif ($action eq 'ch_period_rst')
{
	my $rst_period = $cgi->param('period_reset');
	my $max_period_size;
	if ($rst_period eq 'weekly')
	{
		$max_period_size = $week_seconds;
	}
	elsif ($rst_period eq '2week')
	{
		$max_period_size = $two_week_seconds;
	}
	elsif ($rst_period eq 'monthly')
	{
		$max_period_size = 0;
	}
	elsif ($rst_period eq 'daily')
	{
		$max_period_size = $day_seconds;
	}
	else
	{
		die("Unknown period_reset value!\n");
	};
	ch_pref_param('max_period_size', $max_period_size);
};

dbmopen(%config, "/var/db/sparrow/config", 0660)
	or die("Cant open config hash (/var/db/sparrow/config): $!\n");
my $squid_agent_lastrun 	= $config{'squid_log_agent_lastrun'};
my $count_cached_requests 	= $config{'count_cached_requests'};
my $statis_timepoint 		= $config{'statis_timepoint'};
my $null_passwords_allowed	= $config{'null_passwords_allowed'};
my $period_start_time		= $config{'cur_period_start_timepoint'};
my $period_size			= $config{'max_period_size'};
dbmclose(%config);

my $time_format = '%H:%M:%S %d/%m/%Y';
$tmpl = HTML::Template->new(filename => $tmpl_dir.'/sys_prefs.html');

if (not $period_size)
{
	$tmpl->param(monthly_selected => 'selected');
}
elsif ($period_size eq $day_seconds)
{
	$tmpl->param(daily_selected => 'selected');
}
elsif ($period_size eq $week_seconds)
{
	$tmpl->param(weekly_selected => 'selected');
}
elsif ($period_size eq $two_week_seconds)
{
	$tmpl->param(two_week_selected => 'selected');
}
else
{
	die "unknown max_period_size: $period_size!\n";
};

my $cur_time = time;
$tmpl->param(count_cached_requests => $count_cached_requests);
$tmpl->param(null_passwords_allowed => $null_passwords_allowed);
$tmpl->param(squid_agent_lastrun => strftime($time_format, localtime($squid_agent_lastrun)));
$tmpl->param(statis_timepoint => strftime($time_format, localtime($statis_timepoint)));
$tmpl->param(current_time => strftime($time_format, localtime($cur_time)));
$tmpl->param(squid_agent_status => (($cur_time - $squid_agent_lastrun) > $max_squid_agent_idle_time) ? 'red' : 'green');
$tmpl->param(period_start_time => strftime($time_format, localtime($period_start_time)));
print STDOUT $http_header.$tmpl->output;
exit;

sub ch_pref_param
{
	my $tag = shift;
	my $new_value = shift;

	die "ch_pref_param: no tag defined!\n" unless defined $tag;
	die "ch_pref_param: no value defined!\n" unless defined $new_value;

	my %config; 
	dbmopen(%config, "/var/db/sparrow/config", 0660)
		or die("Cant open config hash (/var/db/sparrow/config): $!\n");
	die "ch_pref_param: no record by tag $tag!\n" unless defined $config{$tag};
	$config{$tag} = $new_value;
	dbmclose(%config);

	return 1;
}
