#!/usr/bin/perl

# ���� ������ ���������� ���������� � ������������ ����������.

my $SSIDNAME = 'SPARROW_SSID';

my %month_names = 
(
	'01' => '������',
	'02' => '�������',
	'03' => '����',
	'04' => '������',
	'05' => '���',
	'06' => '����',
	'07' => '����',
	'08' => '������',
	'09' => '��������',
	'10' => '�������',
	'11' => '������',
	'12' => '�������'
);

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
my $archive_basedir = $config{'archive_basedir'};

dbmclose(%config);
die("Configuration variable tmpl_dir is empty!\n") unless $tmpl_dir;
die("Archive basedir ($archive_basedir) doesnt exists!") unless -d $archive_basedir;

my $tmpl;

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

my $cgi_ss = CGI::Session->load($cookie)
	or die CGI::Session->errstr();
my $ident = $cgi_ss->param('ident');

# ��������� ������
my $reauth_needed = 0;
$reauth_needed = 1 if $cgi_ss->is_empty;
$reauth_needed = 1 if $cgi_ss->is_expired;
$reauth_needed = 1 if $cgi_ss->param('remote_host')	ne $remote_host;
$reauth_needed = 1 unless $ident;

# ����������� �����������, ���� ������ �� ��������
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

# ���������� ���������� ������������
my $is_admin = $D->row("SELECT is_admin FROM clients WHERE id = ".$D->quote($ident).";");

# ���������� ������ ������������ ���������?
my $req_ident = $cgi->param('login');
if ($req_ident)
{
	die "Invalid login requested! ($req_ident)\n"
		unless $req_ident =~ /[\d\w\_\-\.]+/;
};

# ������� ������������� ����� �������� ������ ���� ����������
$req_ident = $ident unless $is_admin;

my $arc_year = $cgi->param('arc_year');
my $arc_month = $cgi->param('arc_month');
my $arc_day = $cgi->param('arc_day');

$tmpl = HTML::Template->new(filename => $tmpl_dir.'/statis.html');
$tmpl->param(today => strftime("%Y-%m-%d", localtime(time))); # ex: 1999-01-08 -- ISO 8601

# ���� ������ ���� - ������ ����� ��������� �� ���
my $arc_workpath; 
if (get_stat_dir_list($archive_basedir))
{
	$tmpl->param(display_archive_form => 1);

	# � ����� ��������� �� ������� ��� ������ ���� �������, ���� �� ������� � �������,
	# � ��������� <SELECT> - ���� �� �������.
	if ($arc_year)	
	{
		die "Requested archive year is invalid ($arc_year).\n" if $arc_year !~ /^\d{4}$/;
		$tmpl->param(cur_year => $arc_year);

		$arc_workpath = join ('/', $archive_basedir, $arc_year);
		# ���������� �����: ���� �������, �� ����� �������, ���� ��� - <SELECT>-��
		if ($arc_month)
		{
			die "Requested archive month is invalid ($arc_month).\n" 
				if $arc_month !~ /^\d{2}$/;
			$tmpl->param(cur_month => $arc_month);
			$tmpl->param(cur_month_name => $month_names{$arc_month});

			$arc_workpath = join ('/', $archive_basedir, $arc_year, $arc_month);
			# ���������� � ����..
			if ($arc_day)
			{
				die "Requested archive day is invalid ($arc_day).\n"
					if $arc_day !~ /^\d{2}$/;
				$tmpl->param(cur_day => $arc_day);
				$arc_workpath = join ('/', $archive_basedir, $arc_year, $arc_month, $arc_day);
			} 
			else
			{
				my @ahref_day_list;
				my $last_day;
				foreach (get_stat_dir_list($arc_workpath))
				{
					push (@ahref_day_list, { 'arc_day' => $_ } );
					$last_day = $_;
				};
				$tmpl->param(day_select_list => \@ahref_day_list);
				$tmpl->param(last_day => $last_day);
			};
		}
		else #// if ($arc_month)
		{
			my @ahref_month_list;
			my $last_month;
			foreach (get_stat_dir_list($arc_workpath))
			{
				push (@ahref_month_list, 
				{ 
					'arc_month' => $_,
					'month_name' => $month_names{$_}
				} );
				$last_month = $_;
			};
			die "Requested archive year ($arc_year) is empty!\n" unless @ahref_month_list;
			$tmpl->param(month_select_list => \@ahref_month_list);
			$tmpl->param(last_month => $last_month);
		};
	}
	else #// if ($arc_year)
	{
		my @ahref_year_list;
		my $last_year;
		foreach (get_stat_dir_list($archive_basedir))
		{
			push (@ahref_year_list, { 'arc_year' => $_ } );
			$last_year = $_;
		};
		$tmpl->param(year_select_list => \@ahref_year_list);
		$tmpl->param(last_year => $last_year);
	};
}; # // ������ ����� ��������� �� ���

# ������, ����� �� ������� ���������� (���� ����� �������);
# � �����, ���� ������������ ����� "��������" � ������ - ����������� ���� $arc_workpath (���� �� �����
# �� ��� ���������� - �����).

############
#	my $arc_workpath = "$archive_basedir/$req_year/$req_month/$req_day";
############

# ������ ������ ����������.....
if ($req_ident or ($req_ident eq '0'))
{
	# ������� �����, ������ ����� �������� ��������� ���������� �� ������
	if ($arc_workpath)
	{
		# �������� � �������
		$tmpl->param(site_stat => get_ahref_arcstat_login_block($arc_workpath."/$req_ident.txt"));
		$tmpl->param(descr => get_login_descr($arc_workpath."/$req_ident.txt"));
		$tmpl->param(working_with_archive => 1);
	#	$tmpl->param(null_data => 1);
	}
	else
	{
		# �������� � ������� ����������� � ����
		$tmpl->param
		(
			site_stat => $D->row_hash("SELECT site, ".
				"\'\' || (bytecounter / 1000000) || \'.\' || to_char(((bytecounter % 1000000)/10000),\'09\') || \'\' as bytes ".
				"FROM statis_summary WHERE id = ".$D->quote($req_ident).
				"AND stat_day = \'today\' ORDER BY bytecounter DESC;")
		);
		$tmpl->param(descr => $D->row("SELECT descr FROM clients WHERE id = ".$D->quote($req_ident)));
	};
	$tmpl->param(req_ident => $req_ident);
	print STDOUT $http_header . $tmpl->output;
	exit;
}
else
{
	# ����� �� ������� - ����� �������� ����� ���������� �� ���� �������
	if ($arc_workpath)
	{
		# �������� � �������
		$tmpl->param(user_stat => get_ahref_arcstat_total_block($arc_workpath."/TOTAL.txt"));
		$tmpl->param(working_with_archive => 1);
	}
	else
	{
		# �������� � ������� ����������� � ����
		$tmpl->param
		(
			user_stat => $D->row_hash("SELECT clients.id as login, ".
				"round((sum(statis_summary.bytecounter) / 1000000), 2) as bytes, ".
				"clients.descr as descr ".
				"FROM statis_summary, clients WHERE clients.id = statis_summary.id ".
				"AND stat_day = \'today\' GROUP BY clients.id, clients.descr ORDER BY bytes DESC;")
		);
	};
	print STDOUT $http_header . $tmpl->output;
	exit;
};


# ������� ���������� ������ ���������� � ��������, ���� ��� ������ ��� ����
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
	@dir_list = sort @dir_list;
	return @dir_list;
};

# ������� ���������� ������ �� ������ ������ �� ����, 
# ���������� ������ ���������� �� ���� �������
# (�������� ��� HTML-Template LOOP)
# ������� �������� - ���� � ����� TOTAL.txt
sub get_ahref_arcstat_total_block
{
	my $stat_file = shift;
	my @arc_list;
	my $total_bytes = 0;
	if (open (ARC_WORK, $stat_file))
	{
		while (<ARC_WORK>)
		{
			chomp;
			my %arc_str;
			/^(\S+)\s+(\S+)\s(.*)$/;
			$arc_str{'login'} = $1;
			$arc_str{'bytes'} = $2;
			$arc_str{'descr'} = $3;
			unless ($arc_str{'bytes'} =~ /^\d+$/)
			{
				warn("Bytecounter for login ".$arc_str{'login'}." is not numeric! file=$stat_file\n");
				next;
			};
			$total_bytes += $arc_str{'bytes'};
			$arc_str{'bytes'} = sprintf('%.2f',($arc_str{'bytes'} / 1000000));
			push (@arc_list, \%arc_str);
		};
		close (ARC_WORK);
	};
	if (@arc_list)
	{
		push (@arc_list, { 
			'bytes' => sprintf('%.2f', ($total_bytes / 1000000)),
			'total_line' => 1
		} );
	}
	else
	{
		push (@arc_list, {'null_data' => 1});
	};
	return \@arc_list;
}

# ������� ���������� �������� �� ������
# ������� �������� - ���� � ����� <client_id>.txt
sub get_login_descr
{
	my $stat_file = shift;
	return undef unless open (ARC_WORK, $stat_file);
	my $descr;
	while (<ARC_WORK>)
	{
		chomp;
		if (/^\$DESCR\=(.*)/)
		{
			$descr = $1;
			last;
		};
	};
	return $descr;
}

# ������� ���������� ������ �� ������ ������ �� ����, 
# ���������� ������ ���������� �� ������������� ������
# (�������� ��� HTML-Template LOOP)
# ������� �������� - ���� � ����� <client_id>.txt
sub get_ahref_arcstat_login_block
{
	my $stat_file = shift;
	my @arc_list;
	my $total_bytes = 0;
	if (open (ARC_WORK, $stat_file))
	{
		while (<ARC_WORK>)
		{
			chomp;
			next if /^\$\w+\=/;
			my %arc_str;
			($arc_str{'site'}, $arc_str{'bytes'}) = split(/\s+/);
			unless ($arc_str{'bytes'} =~ /^\d+$/)
			{
				warn("Bytecounter for site ".$arc_str{'site'}." is not numeric! file=$stat_file\n");
				next;
			};
			$total_bytes += $arc_str{'bytes'};
			$arc_str{'bytes'} = sprintf('%.2f',($arc_str{'bytes'} / 1000000));
			push (@arc_list, \%arc_str);
		};
		close (ARC_WORK);
	};
	if (@arc_list)
	{
		push (@arc_list, { 
			'bytes' => sprintf('%.2f', ($total_bytes / 1000000)),
			'total_line' => 1
		} );
	}
	else
	{
		push (@arc_list, {'null_data' => 1});
	};
	return \@arc_list;
}
