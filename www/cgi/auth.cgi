#!/usr/bin/perl -w

# ���� ������ ���������� ����������� ������������ � ������������ ��� �������
# ���� �������� ��� ������ �������. ����� � ������ ������� ������ �������� �� 
# ����������� ������������� ������.

my $SSIDNAME = 'SPARROW_SSID';
my $max_ss_per_ip = 200; # Maximum allowed sessions from one ip
my $max_ss_total = 200;

use strict;
use CGI::Simple;
use HTML::Template;
use CGI::Session;
use Crypt::PasswdMD5;
use POSIX qw(strftime);

CGI::Session->name($SSIDNAME);

my $cgi = CGI::Simple -> new;

# ��������� ��� cookie
my $http_header = $cgi->header(-charset=>'auto', -expires=>'+1s');

my %config; 
dbmopen(%config, "/var/db/sparrow/config", 0660)
	or die("Cant open config hash (/var/db/sparrow/config): $!\n");
my $tmpl_dir = $config{'tmpl_dir'};
my $dbname = $config{'dbname'};
my $dbuser = $config{'dbuser'};
my $dbpassword = $config{'dbpassword'};
my $def_ip_access = $config{'def_ip_access'};
my $def_user_access = $config{'def_user_access'};

dbmclose(%config);
die("Configuration variable tmpl_dir is empty!\n") unless $tmpl_dir;
my $tmpl;

# ����������� ������������ ����� ��������� � ���� �������:
# 1. �� ������-��� ����� (� ���� ��� ������)
# 2. ��� "�������" ���� ���� "��������" ������, ��� ���������� 
# �� "��������" (������ ����, �� ������)

my $cookie = $cgi->cookie($SSIDNAME);

my $remote_host = $ENV{'REMOTE_ADDR'};
$remote_host = $ENV{'REMOTE_HOST'} unless $remote_host;

# ���� �� ������� ���������� IP ���� - ��������
unless ($remote_host)
{
	$tmpl = HTML::Template->new(filename => $tmpl_dir.'/not_traceable.html');
	print STDOUT $http_header . $tmpl->output;
	exit;
};

my $ss_count_by_ip = 0;
my $ss_count_total = 0;
CGI::Session->find(sub
	{
		my ($cgi_ss) = @_;
		# ���� ������ ������� �� ���������� - �������� �� �������
		return 1 if $cgi_ss->is_empty;
		if ($cgi_ss->is_expired)
		{
			# ���� ������ �������� - ������� ��, � �������� �� �������
			$cgi_ss->delete();
			return 1;
		};
		# ��������� ��������
		$ss_count_by_ip++ if $cgi_ss->param('remote_host') eq $remote_host;
		$ss_count_total++;
	} );
# ������ �������� ������ ������������ ������� ������.

my $cgi_ss = CGI::Session->load()
	or die CGI::Session->errstr();
if ($cgi_ss->is_empty)
{
	# ������ ������������, ����� ���������.

	# ������� �������� � ����������� ����������� ����������.
	# ���� ��������� ����� ������������� ������ � ������ IP - ��������
	if ($ss_count_by_ip > $max_ss_per_ip)
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/max_ss_per_ip_reached.html');
		$tmpl->param(ip => $remote_host);
		print STDOUT $http_header . $tmpl->output;
		exit;
	};
	# ���� ��������� ����� ������������� ������ ������ - ���� ��������
	if ($ss_count_total > $max_ss_total)
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/max_ss_total_reached.html');
		print STDOUT $http_header . $tmpl->output;
		exit;
	};

	# ��� ������������ ������, ��� ������ ����� �����������.
	# ��������� ������� ������ ����� ������������ ������ � ���������
	# �� �� "��������". ���� ��������� ������ �� �������� - ��� �������� � ��������
	# �� ���� ������.
	$cgi_ss = CGI::Session -> new($cookie);
	# ��������� ������ �������, �������� ������ ����� ���������� ��������� � cookie
	$http_header =  $cgi_ss->header(-charset=>'auto', -expires=>'+1s');
	$cgi_ss->expire('25m');
}
else
{
	# ������ ��� ����, �������� ����� ���������� ��������� ��� cookie
};

use SQLayer;
my $D = SQLayer -> new
(
	database    => 'DBI:Pg:dbname='.$dbname,
	user        => $dbuser,
	password    => $dbpassword
);

die "No database connection: ".$D->errstr."\n" unless $D->{'dbh'}->ping();

if ($cgi->param('draw_menu_only') or $cgi->param('logout') or defined $cgi_ss->param('ident'))
{
	# ��������� ��������� ������
	my $ident = $cgi_ss->param('ident');
	my $reauth_needed = 0;
	$reauth_needed = 1 if $cgi_ss->param('remote_host') ne $remote_host;
	$reauth_needed = 1 unless defined $ident;

	# ����������� �����������, ���� ������ �� ��������
	if ($reauth_needed)
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/reauth_needed.html');
		print STDOUT $http_header . $tmpl->output;
		exit;
	};

	if ($cgi->param('logout'))
	{
		# ��������� ����� ������
		# ������� ������ � ���������� � ..... :)
		$cgi_ss->delete();
		print STDOUT $cgi->redirect('/');
		exit;
	};

	# ������ ������ ���� 
	if ($D->row("SELECT is_admin FROM clients WHERE id = ".$D->quote($ident).";"))
	{
		draw_menu_for_admin($http_header);
	}
	else
	{
		draw_menu($http_header);
	};
	exit;
};

$cgi_ss->param('remote_host', $remote_host);
my $edtLogin = $cgi->param('edtLogin');
my $edtPass = $cgi->param('edtPass');

# ����� � ������ ��������, �������� �����������.
my $query_str;
if ($edtLogin or ($edtLogin eq "0"))
{
	# ����� ������ �� ������	
	$query_str = "WHERE id = ".$D->quote($edtLogin)." AND is_workstation = false;";
}
else
{
	# ����� ������ �� IP
	$query_str = "WHERE id = ".$D->quote($remote_host)." AND is_workstation = true;";
};
# ������� ������������� ������
my ($control_id, $is_admin, $exact_passhash) = 
	$D->row("SELECT id, is_admin, password FROM clients ".$query_str);

my $auth_failed = 0;
unless (defined $control_id)
{
	# ��� ������ ������� � ����
	$auth_failed = 1;
	print STDERR scalar(localtime)." User [$edtLogin], IP [$remote_host] doesnt exists!\n";
}
else
{
	# ������ (������) ����
	unless ($exact_passhash)
	{
		# ������ ������ � ����.
		# ���� ������ ����� ���� �������� ������ - ����������� �� ������
		if ($edtPass or ($edtPass eq "0"))
		{
			$auth_failed = 1;
			print STDERR scalar(localtime)." User [$control_id], IP [$remote_host] ".
				"some password entered, while no passhash defined in database (auth failed)!\n";
		}
	}
	else
	{
		# �������� ������ � ����
		use Crypt::PasswdMD5;
		# ������� ��������� ������ � ���������� ��������� � ������ �� �������
		# ���� ����� �� ������������� - ����������� �� ������
		$auth_failed = 1 
			unless unix_md5_crypt($edtPass, $exact_passhash) eq $exact_passhash;
		no Crypt::PasswdMD5;
		print STDERR scalar(localtime)." User [$control_id], IP [$remote_host] auth failed!\n";
	};
};

if ($auth_failed)
{
	$tmpl = HTML::Template->new(filename => $tmpl_dir.'/auth_failed.html');
	print STDOUT $http_header . $tmpl->output;
	exit;
};


# ��������������
$cgi_ss->param('ident', $control_id);

# ������ ����
if ($is_admin)
{
	draw_menu_for_admin($http_header);
}
else
{
	draw_menu($http_header);
};
undef $D;
exit;

sub draw_menu
{
	my $http_header = shift;
	die "No database connection available!\n" unless defined $D;
	my $tmpl;
	my $ident = $cgi_ss->param('ident');
	my ($descr, $bytelimit, $bytecounter, $ignorelimit, $cache_access) = 
		$D->row("SELECT descr, bytelimit, bytecounter, ignorelimit, ".
			"cache_access FROM clients WHERE id = ".$D->quote($ident).";");
	$tmpl = HTML::Template->new(filename => $tmpl_dir.'/profile.html');
	$tmpl->param(login => $ident);
	$tmpl->param(fullname => $descr);
	$tmpl->param(bytelimit => int($bytelimit / 1000000));
	$tmpl->param(bytecounter => int($bytecounter / 1000000));
	$tmpl->param(ignorelimit => $ignorelimit);
	$tmpl->param(cache_access => $cache_access);
	print STDOUT $http_header . $tmpl->output;
	return 1;
}

sub draw_menu_for_admin
{
	my $http_header = shift;
	die "No database connection available!\n" unless defined $D;
	my $tmpl;
	$tmpl = HTML::Template->new(filename => $tmpl_dir.'/admin.html');
	$tmpl->param
	(
		users => $D->row_hash("SELECT id as login, descr, is_workstation, is_admin, ".
			"(bytelimit / 1000000) as bytelimit, ".
    			"(bytecounter / 1000000) as bytecounter, ".
			"cache_access, ignorelimit FROM clients ORDER BY descr;")
	);
	$tmpl->param(total_bytes => $D->row("SELECT sum(bytecounter / 1000000) FROM clients;"));
	$tmpl->param(total_limit => $D->row("SELECT sum(bytelimit / 1000000) FROM clients;"));
	$tmpl->param(def_ip_access => $def_ip_access);
	$tmpl->param(def_user_access => $def_user_access);

	print STDOUT $http_header . $tmpl->output;
	return 1;
}

sub read_values_from_file
{
	my $filename = shift;
	open (FILE, $filename) or return undef;
	my @values;
	while (<FILE>)
	{
		chomp;
		next unless defined $_;
		push (@values, $_);	
	};
	close (FILE);
	return @values;
}
