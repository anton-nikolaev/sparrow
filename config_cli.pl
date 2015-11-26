#!/usr/bin/perl

# ���� ������ ��������� � ��������� ������ ������ ������������ �������.
# ������ "���������" � webgui �� ���� ����������� ������������� ������
# ��������� (� ����� ������������).

my $Version = '20090504';

if ($ARGV[0] eq '-V')
{
	die "$Version\n";
};

use strict;

my $param = $ARGV[0];
my $value = $ARGV[1];
my $runflags = $ARGV[2];

my %config;
$config{"debug"} 			= "bool";
$config{"logfile"} 			= "pid_path";
$config{"dbname"} 			= "text";
$config{"dbuser"} 			= "text";
$config{"dbpassword"} 			= "text";
$config{"dbhost"}			= "text";
$config{"squid_access_log"} 		= "file_path";
$config{"squid_bin"} 			= "file_path";
$config{"squid_log_agent_pidfile"} 	= "pid_path";
$config{"squid_log_agent_lastrun"} 	= "int";
$config{"periodic_pidfile"} 		= "pid_path";
$config{"count_cached_requests"} 	= "bool";
$config{"statis_timepoint"} 		= "int";
$config{"tmpl_dir"} 			= "dir_path"; 
$config{"null_passwords_allowed"}	= "bool"; # ��������� �� ������ ������
$config{"cur_period_start_timepoint"}	= "int"; # �����, ����� ������� ������� ������
$config{"max_period_size"}		= "int"; # ������������ ������ ������� � �������� (0 - �����)
$config{"def_user_access"}		= "bool"; # ��������� ������������� ������� �� ������ � ������ 
$config{"def_ip_access"}		= "bool"; # ��������� ������������� ������� �� IP-������
$config{"archive_basedir"}		= "dir_path"; # ����������, ���� ������������ ������ ����������
$config{"client_ip_acl"}		= "bool"; # ��������� �� ������������ ������ �� IP-�������

# ������ ��������� �� (M.m[A]) M - �����, m - �����, A - ������ ����������.
$config{"database_version"}		= "text"; 

my $print_all;
if (defined $param)
{
	die_with_usage("Unknown parameter: $param.") unless $config{$param}; 
	if (defined $value)
	{
		die_with_usage("Value missing for $param while upgrading.") if $value eq 'upgrade';
		# ���� ����� ��������� ������ ���� �������� ����� ������
		my $type = $config{$param};
		if ($type eq 'bool')
		{
			die_with_usage("Only '1' or '0' values accepted for $param.") 
				if ($value ne '1') and ($value ne '0');
		}
		elsif ($type eq 'pid_path')
		{
			$value =~ /(.*)\/[\w\d\.]+$/;
			$type = $1;
			die("$value has no parent directory!\n") unless -d $type;
		}
		elsif ($type eq 'text')
		{
		}
		elsif ($type eq 'file_path')
		{
			die("File $value doesnt exists!\n") unless -e $value;
		}
		elsif ($type eq 'int')
		{
			die_with_usage("Invalid value for parameter $param.") 
				unless $value =~ /^\d+$/;
		};
	};
}
else
{
	# ���� ������� ��������� ���, ������ ������ ���������� ���
	$print_all = 1;
};

my %cdb;
dbmopen(%cdb, "/var/db/sparrow/config", 0660)
	or die "Cant open config /var/db/sparrow/config: $!\n";
if ($print_all)
{
	print STDOUT "For usage details, run $0 with some junk as argument.\nAll parameters:\n";
	foreach (keys %cdb)
	{
		print STDOUT "$_ = ".$cdb{$_}."\n";
	};
}
else
{
	if ($runflags eq 'upgrade')
	{
		# ��� ���������� ������ ������� ��� �������� �����
		$cdb{$param} = $value if (not $cdb{$param}) and ($cdb{$param} ne 0);
	}
	else
	{
		if (not defined $value)
		{
			# ����� ������ �����
			print STDOUT $cdb{$param}."\n";
		}
		else
		{
			$cdb{$param} = $value;
		};
	};
};

dbmclose(%cdb);

sub die_with_usage
{
	my $message = shift;
	die "ERROR! $message\n\n".
		"Usage: $0 <param_name> <value>\n".
		"Script prints out all config parameters with their actual values when used ".
		"without any arguments.\n\n".
		"Valid parameters: \n".
		" dbuser,dbpassword,dbname,dbhost - database authentication parameters.\n".
		" debug - verbose begaviour of the sparrow or not (webgui not affected).\n".
		" logfile - full path to sparrow.log.\n".
		" squid_access_log - full path to squid access.log.\n".
		" squid_bin - full path to squid binary executable.\n".
		" squid_log_agent_pidfile - full path to squidAgent pidfile.\n".
		" squid_log_agent_lastrun - unix timestamp of squidAgent last execution.\n".
		" periodic_pidfile - full path to periodic script pid file.\n".
		" count_cached_requests - count served fully from cache requests or not.\n".
		" statis_timepoint - unix timestamp of last processed squid access.log record.\n".
		" tmpl_dir - full path, where cgi script should look for HTML templates.\n".
		" null_passwords_allowed - allow users to have empty passwords or not.\n".
		" max_period_size - maximum amount of seconds to pass in period to reset counters.\n".
		" archive_basedir - full path, where statistics archive located at.\n".
		" client_ip_acl - allow access limitation based on IP for logins or not.\n";
}

$config{"debug"} 			= "bool";
$config{"logfile"} 			= "pid_path";
$config{"dbname"} 			= "text";
$config{"dbuser"} 			= "text";
$config{"dbpassword"} 			= "text";
$config{"dbhost"}			= "text";
$config{"squid_access_log"} 		= "file_path";
$config{"squid_bin"} 			= "file_path";
$config{"squid_log_agent_pidfile"} 	= "pid_path";
$config{"squid_log_agent_lastrun"} 	= "int";
$config{"periodic_pidfile"} 		= "pid_path";
$config{"count_cached_requests"} 	= "bool";
$config{"statis_timepoint"} 		= "int";
$config{"tmpl_dir"} 			= "dir_path"; 
$config{"null_passwords_allowed"}	= "bool"; # ��������� �� ������ ������
$config{"cur_period_start_timepoint"}	= "int"; # �����, ����� ������� ������� ������
$config{"max_period_size"}		= "int"; # ������������ ������ ������� � �������� (0 - �����)
$config{"def_user_access"}		= "bool"; # ��������� ������������� ������� �� ������ � ������ 
$config{"def_ip_access"}		= "bool"; # ��������� ������������� ������� �� IP-������
$config{"archive_basedir"}		= "dir_path"; # ����������, ���� ������������ ������ ����������
$config{"client_ip_acl"}		= "bool"; # ��������� �� ������������ ������ �� IP-�������
$config{"database_version"}		= "text"; # ������ ��������� �� (�������� ��������, ���� ������ �� �������������)
