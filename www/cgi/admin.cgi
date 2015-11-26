#!/usr/bin/perl -w

# Ётот скрипт занимаетс€:
#  - добавлением пользовател€ / рабочей станции
#  - удалением пользовател€ / рабочей станции
#  - сменой ‘»ќ / описани€
#  - сменой паролей
#  - сменой привелегий
#  - сменой лимита
#  - сменой ограничени€ по лимиту

my $SSIDNAME = 'SPARROW_SSID';

use strict;
use CGI::Simple;
use HTML::Template;
use CGI::Session;
use Crypt::PasswdMD5;
use POSIX qw(strftime);

CGI::Session->name($SSIDNAME);

my $cgi = CGI::Simple -> new;

my %config; 
dbmopen(%config, "/var/db/sparrow/config", 0660)
	or die("Cant open config hash (/var/db/sparrow/config): $!\n");
my $tmpl_dir = $config{'tmpl_dir'};
my $dbname = $config{'dbname'};
my $dbuser = $config{'dbuser'};
my $dbpassword = $config{'dbpassword'};
my $null_passwords_allowed = $config{'null_passwords_allowed'};

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
	print STDOUT $cgi->header(-charset=>'auto') . $tmpl->output;
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
	print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
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

# ќбщие параметры дл€ всех запросов
my $req_action = $cgi->param('action');
my $req_ident = $cgi->param('login');

if ($req_action eq 'chpass')
{
	my $new_password = $cgi->param('new_value');
	
	# провер€ем привелегии
	unless ($is_admin)
	{
		# обычный пользователь - можно мен€ть только себе.
		$req_ident = $ident;

		# свер€ем текущий пароль
		my $req_password = $cgi->param('current_value');
		my $passhash = $D->row("SELECT password FROM clients WHERE id = ".$D->quote($ident).";");
		my $cur_pass_invalid = 0;
		if (defined $passhash)
		{
			# в базе лежит зашифрованный непустой пароль
			$cur_pass_invalid = 1 unless unix_md5_crypt($req_password, $passhash) eq $passhash;
		}
		else
		{
			# в базе лежит пустой пароль
			$cur_pass_invalid = 1 if $req_password or ($req_password eq "0");
		};
		if ($cur_pass_invalid)
		{
			# введенный пароль не совпадает с текущим
			$tmpl = HTML::Template->new(filename => $tmpl_dir.'/cur_pass_invalid.html');
			print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
			exit;
		};
	};

	# мен€ем пароль. 
	if (not $new_password and ($new_password ne "0"))
	{
		# приехал пустой пароль
		if (not $null_passwords_allowed)
		{
			$tmpl = HTML::Template->new(filename => $tmpl_dir.'/null_pwd_not_allowed.html');
			print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
			exit;
		};
		
		# шифровать нечего.
		# вставл€ем в базу пустой пароль
		unless($D->proc("UPDATE clients SET password = NULL WHERE id = ".$D->quote($req_ident).";") == 1)
		{
			die("Password remove for $ident failed (requested id = $req_ident, ".
				"is_admin = $is_admin): ".$D->errstr."\n");
		};
	}
	else
	{
		# шифруем пароль, и вставл€ем его в базу
		unless ($D->proc("UPDATE clients SET password = ".
					$D->quote(unix_md5_crypt($new_password, '1a')).
					" WHERE id = ".$D->quote($req_ident).";") == 1)
		{
			die("Password update for $ident failed (requested id = $req_ident, ".
				"is_admin = $is_admin): ".$D->errstr."\n");
		};
	};
	$tmpl = HTML::Template->new(filename => $tmpl_dir.'/password_updated.html');
	$tmpl->param(login => $req_ident);
	print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
	exit;
}
elsif ($req_action eq 'chlimit')
{
	my $new_limit = $cgi->param('new_value');
	# «начение приезжает в мегабайтах, а вставл€ть в базу надо в байтах
	$new_limit *= 1000000; 
	# обычным пользовател€м запрещено редактировать лимиты
	die("Unpriveleged attempt for $ident to change bytelimit (requested id = $req_ident, ".
		"$new_limit Mbytes)!\n") unless $is_admin;

	if ($D->proc("UPDATE clients SET bytelimit = ".$D->quote($new_limit).
			" WHERE id = ".$D->quote($req_ident).";") == 1)
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/limit_updated.html');
		$tmpl->param(login => $req_ident);
		print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
		exit;
	}
	else
	{
		die("Bytelimit update for $ident failed (requested id = $req_ident, ".
			"new bytelimit = $new_limit): ".$D->errstr."\n");
	}
}
elsif ($req_action eq 'chdescr')
{
	# обычным пользовател€м запрещено редактировать описание / ‘»ќ
	die("Unpriveleged attempt for $ident to change description (requested id = $req_ident)!\n")
		unless $is_admin;

	my $new_descr = $cgi->param('new_value');
	if ($D->proc("UPDATE clients SET descr = ".$D->quote($new_descr).
			" WHERE id = ".$D->quote($req_ident).";") == 1)
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/descr_updated.html');
		$tmpl->param(login => $req_ident);
		print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
		exit;
	}
	else
	{
		die("Description update for $ident failed (requested id = $req_ident): ".
			$D->errstr."\n");
	}
}
elsif ($req_action eq 'rmuser')
{
	# обычным пользовател€м запрещено удал€ть учетные записи
	die("Unpriveleged attempt for $ident to remove account (requested id = $req_ident)!\n")
		unless $is_admin;

	# нельз€ удал€ть самого себ€, если больше нет админов!
	if ($ident eq $req_ident)
	{
		if ($D->row("SELECT SUM(*) FROM clients WHERE is_admin = true;") == 1)
		{
			$tmpl = HTML::Template->new(filename => $tmpl_dir.'/last_admin.html');
			print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
			exit;
		}
	};

	if ($D->proc("DELETE FROM clients WHERE id = ".$D->quote($req_ident).";") == 1)
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/account_removed.html');
		$tmpl->param(login => $req_ident);
		print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
		exit;
	}
	else
	{
		die("Account remove for $ident failed (requested id = $req_ident): ".
			$D->errstr."\n");
	}
}
elsif (($req_action eq 'adduser') or ($req_action eq 'addws'))
{
	# обычным пользовател€м запрещено добавл€ть учетные записи
	die("Unpriveleged attempt for $ident to create account (new id = $req_ident)!\n")
		unless $is_admin;
		
	my $descr = $cgi->param('fullname');
	my $new_pass = $cgi->param('newpass');
	my $bytelimit = $cgi->param('bytelimit');
	my $bytecounter = $cgi->param('bytecounter');
	my $ignorelimit = $cgi->param('ignorelimit');
	$is_admin = $cgi->param('is_admin');

	if (not $new_pass and ($new_pass ne "0"))
	{
		if ((not $null_passwords_allowed) and ($req_action eq 'adduser'))
		{
			# настройка запрета пустых паролей действует только на юзеров 
			$tmpl = HTML::Template->new(filename => $tmpl_dir.'/null_pwd_not_allowed.html');
			print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
			exit;
		};

		# пустой пароль
		$new_pass = 'NULL';
	}
	else
	{
		# непустой пароль
		$new_pass = $D->quote(unix_md5_crypt($new_pass, '1a'));
	};

	$ignorelimit = $ignorelimit eq 'on' ? 'true' : 'false';
	$is_admin = $is_admin eq 'on' ? 'true' : 'false';
	my $is_ws = $req_action eq 'addws' ? 'true' : 'false';

	if ($D->proc("INSERT INTO clients (id, descr, password, bytelimit, bytecounter, ignorelimit, ".
			"is_admin, is_workstation) values (".$D->quote($req_ident).", ".$D->quote($descr).
			", $new_pass, ".$D->quote($bytelimit * 1000000).", ".$D->quote($bytecounter * 1000000).
			", ".$D->quote($ignorelimit).", ".$D->quote($is_admin).", $is_ws);") == 1)
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/account_created.html');
		$tmpl->param(login => $req_ident);
		print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
		exit;
	}
	else
	{
		die("Account create for $ident failed (id = $req_ident): ".$D->errstr."\n");
	};
}
elsif ($req_action eq 'chadmin')
{
	my $new_flag = $cgi->param('new_value');
	# обычным пользовател€м запрещено мен€ть привелегии
	die("Unpriveleged attempt for $ident to modify privileges (requested id = $req_ident, ".
		"new is_admin flag = $new_flag)!\n") unless $is_admin;

	$new_flag = $new_flag == 1 ? 'true' : 'false';

	# нельз€ снимать с себ€ привелегии админа, если больше нет админов
	if (($ident eq $req_ident) and ($new_flag eq 'false'))
	{
		if ($D->row("SELECT SUM(*) FROM clients WHERE is_admin = true;") == 1)
		{
			$tmpl = HTML::Template->new(filename => $tmpl_dir.'/last_admin.html');
			print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
			exit;
		}
	};

	if ($D->proc("UPDATE clients SET is_admin = $new_flag WHERE id = ".$D->quote($req_ident).";"))	
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/privileges_modified.html');
		$tmpl->param(login => $req_ident);
		print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
		exit;
	}
	else
	{
		die("Privileges modify for $ident failed (requested id = $req_ident, ".
			"is_admin = $new_flag)!\n");
	};
}
elsif ($req_action eq 'ignorelimit')
{
	my $new_flag = $cgi->param('new_value');
	# обычным пользовател€м запрещено мен€ть ограничение
	die("Unpriveleged attempt for $ident to modify ignorelimit (requested id = $req_ident, ".
		"ignorelimit flag = $new_flag)!\n") unless $is_admin;

	$new_flag = $new_flag == 1 ? 'true' : 'false';
	
	if ($D->proc("UPDATE clients SET ignorelimit = $new_flag WHERE id = ".$D->quote($req_ident).";"))	
	{
		$tmpl = HTML::Template->new(filename => $tmpl_dir.'/ignorelimit_modified.html');
		$tmpl->param(login => $req_ident);
		print STDOUT $cgi->header(-charset=>'auto').$tmpl->output;
		exit;
	}
	else
	{
		die("Ignorelimit modify for $ident failed (requested id = $req_ident, ".
			"ignorelimit = $new_flag)!\n");
	};
};

print STDOUT $cgi->header(-charset=>'auto')."Not implemented yet.";
exit;
