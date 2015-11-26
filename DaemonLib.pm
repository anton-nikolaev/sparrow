package DaemonLib;

$DaemonLib::VERSION = '0.080204';

use strict;

sub new
{
	my ($class, %HKeys) = @_;

	my $self = 
	{
		debug 			=> $HKeys{'debug'},
		logfile 		=> $HKeys{'logfile'},
		logfacility 		=> $HKeys{'logfacility'},
		log_pid			=> 0,
		log_timestamp		=> 1,
		errstr  		=> ""
	};	    

	bless $self, $class;

	$self->{'log_pid'} = $HKeys{'log_pid'} if $HKeys{'log_pid'};
	$self->{'log_timestamp'} = $HKeys{'log_timestamp'} if $HKeys{'log_timestamp'};

	return $self
}

sub logfile
{
	my $self = shift;
	return $self->{'logfile'} unless $_[0];
	$self->{'logfile'} = $_[0];
	return 1
}

sub debug
{
	my $self = shift;
	return $self->{'debug'} unless $_[0];
	$self->{'debug'} = $_[0];
	return 1
}

sub include_pid_in_log
{
	my $self = shift;
	# accept only 1 or 0
	return undef if ($_[0] ne "1") and ($_[0] ne "0");
	# Get value (request)
	return $self->{'log_pid'} unless $_[0];
	# Set value
	$self->{'log_pid'} = $_[0];
	return 1
}

sub checkpid_byfile
{
	my $self = shift;
	my $pidfile = shift;
	if (-e $pidfile)
	{
		# Process exists (running)
		return 1 unless system("kill -0 `cat $pidfile`");
	}
	else
	{
		$self->{'errstr'} = "Pid file $pidfile doesnt exists.";
		return 0;
	}
	# Process is dead, or pidfile doesnt exists
	$self->{'errstr'} = "Process is dead.";
	return 0
}

sub writepid_tofile
{
	my $self = shift;
	my $pidfile = shift;
	open (PID, ">$pidfile") or return undef;
	print PID "$$";
	close (PID);
	return 1
}

sub readpid_fromfile
{
	my $self = shift;
	my $pidfile = shift;
	my $ppid;
	open(PID, $pidfile) or return undef;
	while (<PID>) 
	{
		chomp;
		$ppid = $_;
		last;
	};
	return $ppid;
}

sub _log
{
	my $self = shift;
	my $prefix = shift;
	my $message = shift;
	my $output;
	$output .= scalar(localtime)." " if $self->{'log_timestamp'};
	$output .= $self->{'logfacility'}." " if $self->{'logfacility'};
	$output .= "PID $$ " if $self->{'log_pid'};
	$output .= $prefix." " if $prefix;
	$output .= $message."\n";

	# Write to STDERR, if logfile is not specified
	unless ($self->{'logfile'})
	{
		print STDERR $output;
		$self->{'errstr'} = 'Logfile not specified';
		return 0;
	};

	# write to log, if possible
       	if (open (LOG, ">>".$self->{'logfile'}))
	{
		print LOG $output;
		close(LOG);
		return 1;			
	}
	# write to STDERR, if not possible to write to log
	else
	{
		print STDERR $output;
		$self->{'errstr'} = 'Cant open '.$self->{'logfile'}.': '.$!;
		return 0;
	};
}

sub debuglog
{
	my $self = shift;
	my $message = shift;
	# Do not log, if debug level is NOT set.
	return 1 unless $self->{'debug'};
	return $self->_log("DEBUG", $message);
}

sub writelog
{
	my $self = shift;
	my $message = shift;
	return $self->_log("", $message);
}

sub dielog
{
	my $self = shift;
	my $message = shift;
	$self->_log("FATAL", $message);
	exit;
}

sub errstr
{
	my $self = shift;
	return $self->{'errstr'}
}

sub extract_shellwords
{
	my $self = shift;
        local($_) = join('', @_) if @_;
        my (@words,$snippet,$field);

	s/^\s+//;
	while ($_ ne '') 
	{
		$field = '';
		for (;;) 
		{
			if (s/^"(([^"\\]|\\.)*)"//) 
			{
				($snippet = $1) =~ s#\\(.)#$1#g;
			}
			elsif (/^"/) 
			{
				$self->{'errstr'} = "Unmatched double quote: $_";
				return undef;
			}
			elsif (s/^'(([^'\\]|\\.)*)'//) 
			{
				($snippet = $1) =~ s#\\(.)#$1#g;
			}
			elsif (/^'/) 
			{
				$self->{'errstr'} = "Unmatched single quote: $_";
				return undef;
			}
			elsif (s/^\\(.)//) 
			{
				$snippet = $1;
			}
			elsif (s/^([^\s\\'"]+)//) 
			{
				$snippet = $1;
			}
			else 
			{
				s/^\s+//;
				last;
			}
			$field .= $snippet;
		}
		push(@words, $field);
	}
	return @words
}

sub get_config_from_file
{
	my $self = shift;
	my $filename = shift;
	my %config;
	open (CONFIG, $filename) or do 
	{
		$self->{'errstr'} = "Cant open config file ".$filename.": $!";
		return %config;
	};
	while (<CONFIG>)	
	{
		chomp;	
		# Skip comments (begin from #)
		next if $_ =~ /^\s*\#/;
		# Skip empty lines
		next unless $_;
		# All other assumed as key = value. Spaces are removed.
		my ($key,$value) = split(/\s*\=\s*/);
		$key = $1 if $key =~ /\s+(.*)/;
		$config{$key} = $value;	
	};
	$self->{'errstr'} = "No directives found in config file $filename." unless keys %config;
	return %config;	
}

sub DESTROY
{
	# Do nothing yet
}

1;

__END__;

=head1 NAME

=head1 SYNOPSIS

  my $DLib = DaemonLib->new(debug => 1, logfile => '/var/log/mydaemon.log',
		logfacility => 'MYDAEMON');
  my %Config = $DLib->get_config_from_file();
  die "Cant read config file: ".$DLib->errstr unless keys %Config;
  die "already running!" 
	if $DLib->checkpid_byfile("/var/run/mydaemon.pid");
  $DLib->debuglog("checkpid_byfile exit code description = ".$DLib->errstr);
  die "cant write my pid file: $!" 
	unless $DLib->writepid_tofile("/var/run/mydaemon.pid");

  $DLib->writelog("NOTICE MyDaemon is starting...");

=head1 METHODS

  -- new(  debug => "loglevel - 1 or 0", 
	   logfile => "filename")
    Construct a new object. Debug affects only debuglog procedure - it
    writes info to logfile only if debug is set.
    In fact - all parameteris are optional 
     - logfile 	      => '/path/to/logfile'
    No logfile written by default (all log methods just returns 0)
     - logfacility    => 'SCRIPTNAME'
    SCRIPTNAME - every log message will be supplied with it (eg: LOG-AGENT). No 
    logfacility defined by default.
     - log_pid        => 1 
    See include_pid_in_log() method. Turned off by default. 
     - log_timestamp  => 0 
    Default behaviour is to log timestamp in each log method. You can turn off it.

  -- errstr()
    Returns last negative exit code from complex methods (like process methods).

  -- extract_shellwords($line)
  -- extract_shellwords(@lines)
    Returns words in array, extracted from input. Commonly usage in squid external
    scripts (extracting LOGIN PASS queries from string, received on STDIN), such 
    are external_acl and external authenticator. Empty value returned while error, 
    check errstr(). 
    WARNING: You should use AUTHFLUSH ($| = 1) in your script, otherwise script will
    freeze upon request.

  -- get_config_from_file($filename)
    Returns all config directives in hash. Directives assumed in: key = value.
    Empty hash returned while error - check errstr().

  -------------------
  --- log methods ---
  
  All methods in this section writes a message with text given to the logfile 
  (see the new() method). Readable timestamp writed before the message text,
  and a newline character after. SCRIPTNAME also writed, if logfacility defined in new().

  -- writelog("NOTICE message text")
    Just writes a message. As described above.
  
  -- debuglog("some debug text")
    DEBUG clause writed before the message text. This procedure works only if 
    debug is set (see the new() method) - if not set, it's just returns 1.
  
  -- dielog("some dying text")
    FATAL clause writed before the message text. After that die() is called, 
    causing main script to exit with error.

  -- include_pid_in_log(1) 
  -- include_pid_in_log(0)
  -- include_pid_in_log()
    Log PID with each message. Value "1" means that each log message will be logged 
    with current PID. "0" - default value (do not log PID). Empty value cause current 
    switch value to be returned.

  -----------------------
  --- process methods ---

  -- checkpid_byfile("filename_with_pid")
    Fileseek is performed and pid number extracted (plain-text at first
    and usually the one string). Then pid is checked on existance.
    Returns 1 if process is up and running, 0 if not (check $! for details).

  -- writepid_tofile("filename");
    Current process identifier is writed to file specified. Returns 1 on 
    success, undef if not. $! contains open() error in the last case.

  -- readpid_fromfile("filename_with_pid")
    Reads the first string from file and returns it in scalar context. $! contains
    open() error, if undef returned.

=head1 AUTHOR

  Written at february 2006 (till now i hope)
    by Anthony G. Nickolayev (dodger@list.ru)

=head1 BUGS

=head1 SEE ALSO

=cut

