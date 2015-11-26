#!/usr/bin/perl

# Auth helper to Squid to verify user password in sparrowdb
my $Version = '20090111';

if ($ARGV[0] eq '-V')
{
	die "$Version\n";
};

use SQLayer;
use strict;
use DaemonLib;
use Crypt::PasswdMD5;

if (($> == 0) or ($< == 0))
{
	die "Do not run me as root! Its dangerous.\n";
};

# Disable output buffering
$|=1;           

$SIG{TERM} = 'self_destroy';
$SIG{INT} = 'self_destroy';

my $DLib = DaemonLib->new
(
	logfacility 	=> 'EXT-AUTH'
);

my %config; # = $DLib->get_config_from_file("/usr/local/etc/sparrow.conf"); 
dbmopen(%config, "/var/db/sparrow/config", 0660)
	or $DLib->dielog("Cant open config hash (/var/db/sparrow/config): $!");

# there is nothing harmful if no debug defined by default
$DLib->debug($config{'debug'});

$DLib->dielog("Logfile not defined!") unless $config{'logfile'};
$DLib->logfile($config{'logfile'});
my $null_passwords_allowed = $config{'null_passwords_allowed'};

my $D = SQLayer -> new
(
        database 	=> 'DBI:Pg:dbname='.$config{'dbname'},
        user 		=> $config{'dbuser'},
        password 	=> $config{'dbpassword'}
);

$DLib->dielog("Database ".$config{'dbname'}." connection failed!".$D->errstr) 
	unless $D->{'dbh'}->ping;
$D->DEBUG(1) if $config{'debug'};

# Usually squid starts multiple copies of auth helper, so 
# it would be nice to see PID in log.
$DLib->include_pid_in_log(1);
dbmclose(%config);

$DLib->writelog("NOTICE Ready to serve squid queries.");

# Read squid's password check query (%LOGIN %PASS)
while (<STDIN>) 
{
        chop;
        my ( $user, $second ) = $DLib->extract_shellwords($_);
	my $ans = check($user,$second);
	if ($ans)
	{
		$DLib->debuglog("Positive password check for $user.");
		print "OK\n";
	}
	else
	{
		$DLib->debuglog("Negative password check for $user.");
		print "ERR\n";
	}	
}

sub check 
{
	my $user = shift;
	my $given_password = shift;
	# Deny request with empty password.
	return 0 unless $given_password;
	my ($exact_login, $exact_password) = $D -> row
			(
			 "SELECT id, password ".
			 "FROM clients ".
			 "WHERE id = ".$D->quote($user)." AND is_workstation = false;"
		  	);
	unless ($exact_login)
	{
		$DLib->writelog("WARNING User $user doesnt really exists!");
		return 0;
	};
	unless ($exact_password)
	{
		unless ($null_passwords_allowed)
		{
			$DLib->writelog("WARNING User $user has null password, while null passwords not allowed!");
			return 0;
		}
		else
		{
			return 0 if $given_password eq '0';
			return 1 unless $given_password;
			return 0;
		};
	};
	# unix_md5_crypt(password, salt)
	$given_password = unix_md5_crypt($given_password, $exact_password);
	$DLib->debuglog("given password hash = $given_password exact password hash = $exact_password");
        return 1 if $given_password eq $exact_password;
        return 0;
}

sub self_destroy
{
        $DLib->writelog("NOTICE Exiting via SIGnal.");
        exit;
}
