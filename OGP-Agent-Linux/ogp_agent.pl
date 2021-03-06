#!/usr/bin/perl
#
# OGP - Open Game Panel
# Copyright (C) 2008 - 2014 The OGP Development Team
#
# http://www.opengamepanel.org/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

use warnings;
use strict;

use Cwd;			 # Fast way to get the current directory
use lib getcwd();
use Frontier::Daemon::Forking;	# Forking XML-RPC server
use File::Copy;				   # Simple file copy functions
use File::Copy::Recursive
  qw(fcopy rcopy dircopy fmove rmove dirmove pathempty pathrmdir)
  ;							   # Used to copy whole directories
use File::Basename; # Used to get the file name or the directory name from a given path
use Crypt::XXTEA;	# Encryption between webpages and agent.
use Cfg::Config;	 # Config file
use Cfg::Preferences;   # Preferences file
use Fcntl ':flock';  # Import LOCK_* constants for file locking
use LWP::UserAgent; # Used for fetching URLs
use MIME::Base64;	# Used to ensure data travelling right through the network.
use Getopt::Long;	# Used for command line params.
use Path::Class::File;	# Used to handle files and directories.
use File::Path qw(mkpath);
use Archive::Extract;	 # Used to handle archived files.
use File::Find;

# Compression tools
use IO::Compress::Bzip2 qw(bzip2 $Bzip2Error); # Used to compress files to bz2.
use Compress::Zlib; # Used to compress file download buffers to zlib.
use Archive::Tar; # Used to create tar, tgz or tbz archives.
use Archive::Zip qw( :ERROR_CODES :CONSTANTS ); # Used to create zip archives.

# Current location of the agent.
use constant AGENT_RUN_DIR => getcwd();

# Load our config file values
use constant AGENT_KEY	  => $Cfg::Config{key};
use constant AGENT_IP	   => $Cfg::Config{listen_ip};
use constant AGENT_LOG_FILE => $Cfg::Config{logfile};
use constant AGENT_PORT	 => $Cfg::Config{listen_port};
use constant AGENT_VERSION  => $Cfg::Config{version};
use constant SCREEN_LOG_LOCAL  => $Cfg::Preferences{screen_log_local};
use constant DELETE_LOGS_AFTER  => $Cfg::Preferences{delete_logs_after};
use constant AGENT_PID_FILE =>
  Path::Class::File->new(AGENT_RUN_DIR, 'ogp_agent.pid');
use constant STEAM_LICENSE_OK => "Accept";
use constant STEAM_LICENSE	=> $Cfg::Config{steam_license};
use constant GAME_DIR => $Cfg::Config{game_dir};
use constant MANUAL_TMP_DIR   => Path::Class::Dir->new(AGENT_RUN_DIR, 'tmp');
use constant STEAMCMD_CLIENT_DIR => Path::Class::Dir->new(AGENT_RUN_DIR, 'steamcmd');
use constant STEAMCMD_CLIENT_BIN =>
  Path::Class::File->new(STEAMCMD_CLIENT_DIR, 'steamcmd.sh');
use constant SCREEN_LOGS_DIR =>
  Path::Class::Dir->new(AGENT_RUN_DIR, 'screenlogs');
use constant GAME_STARTUP_DIR =>
  Path::Class::Dir->new(AGENT_RUN_DIR, 'startups');
use constant SCREENRC_FILE =>
  Path::Class::File->new(AGENT_RUN_DIR, 'ogp_screenrc');
use constant SCREENRC_TMP_FILE =>
  Path::Class::File->new(AGENT_RUN_DIR, 'ogp_screenrc.tmp');
use constant SCREEN_TYPE_HOME   => "HOME";
use constant SCREEN_TYPE_UPDATE => "UPDATE";
use constant FD_DIR => Path::Class::Dir->new(AGENT_RUN_DIR, 'FastDownload');
use constant FD_ALIASES_DIR => Path::Class::Dir->new(FD_DIR, 'aliases');
use constant FD_PID_FILE => Path::Class::File->new(FD_DIR, 'fd.pid');
use constant SCHED_PID => Path::Class::File->new(AGENT_RUN_DIR, 'scheduler.pid');
use constant SCHED_TASKS => Path::Class::File->new(AGENT_RUN_DIR, 'scheduler.tasks');
use constant SCHED_LOG_FILE => Path::Class::File->new(AGENT_RUN_DIR, 'scheduler.log');

$Cfg::Config{sudo_password} =~ s/('+)/'\"$1\"'/g;
our $SUDOPASSWD = $Cfg::Config{sudo_password};
my $no_startups	= 0;
my $clear_startups = 0;
our $log_std_out = 0;

GetOptions(
		   'no-startups'	=> \$no_startups,
		   'clear-startups' => \$clear_startups,
		   'log-stdout'	 => \$log_std_out
		  );

# Starting the agent as root user is not supported anymore.
if ($< == 0)
{
	print "ERROR: You are trying to start the agent as root user.";
	print "This is not currently supported. If you wish to start the";
	print "you need to create a normal user account for it.";
	exit 1;
}

### Logger function.
### @param line the line that is put to the log file.
sub logger
{
	my $logcmd	 = $_[0];
	my $also_print = 0;

	if (@_ == 2)
	{
		($also_print) = $_[1];
	}

	$logcmd = localtime() . " $logcmd\n";

	if ($log_std_out == 1)
	{
		print "$logcmd";
		return;
	}
	if ($also_print == 1)
	{
		print "$logcmd";
	}

	open(LOGFILE, '>>', AGENT_LOG_FILE)
	  or die("Can't open " . AGENT_LOG_FILE . " - $!");
	flock(LOGFILE, LOCK_EX) or die("Failed to lock log file.");
	seek(LOGFILE, 0, 2) or die("Failed to seek to end of file.");
	print LOGFILE "$logcmd" or die("Failed to write to log file.");
	flock(LOGFILE, LOCK_UN) or die("Failed to unlock log file.");
	close(LOGFILE) or die("Failed to close log file.");
}

# Rotate the log file
if (-e AGENT_LOG_FILE)
{
	if (-e AGENT_LOG_FILE . ".bak")
	{
		unlink(AGENT_LOG_FILE . ".bak");
	}
	logger "Rotating log file";
	move(AGENT_LOG_FILE, AGENT_LOG_FILE . ".bak");
	logger "New log file created";
}

open INPUTFILE, "<", SCREENRC_FILE or die $!;
open OUTPUTFILE, ">", SCREENRC_TMP_FILE or die $!;
my $dest = SCREEN_LOGS_DIR . "/screenlog.%t";
while (<INPUTFILE>)
{
	$_ =~ s/logfile.*/logfile $dest/g;
	print OUTPUTFILE $_;
}
close INPUTFILE;
close OUTPUTFILE;
unlink SCREENRC_FILE;
move(SCREENRC_TMP_FILE,SCREENRC_FILE);

# Check the screen logs folder
if (!-d SCREEN_LOGS_DIR && !mkdir SCREEN_LOGS_DIR)
{
	logger "Could not create " . SCREEN_LOGS_DIR . " directory $!.", 1;
	exit -1;
}

if (check_steam_cmd_client() == -1)
{
	print "ERROR: You must download and uncompress the new steamcmd package.";
	print "BE SURE TO INSTALL IT IN " . AGENT_RUN_DIR . "/steamcmd directory,";
	print "so it can be managed by the agent to install servers.";
	exit 1;
}

# create the directory for startup flags
if (!-e GAME_STARTUP_DIR)
{
	logger "Creating the startups directory " . GAME_STARTUP_DIR . "";
	if (!mkdir GAME_STARTUP_DIR)
	{
		my $message =
			"Failed to create the "
		  . GAME_STARTUP_DIR
		  . " directory - check permissions. Errno: $!";
		logger $message, 1;
		exit 1;
	}
}
elsif ($clear_startups)
{
	opendir(STARTUPDIR, GAME_STARTUP_DIR);
	while (my $startup_file = readdir(STARTUPDIR))
	{

		# Skip . and ..
		next if $startup_file =~ /^\./;
		$startup_file = Path::Class::File->new(GAME_STARTUP_DIR, $startup_file);
		logger "Removing " . $startup_file . ".";
		unlink($startup_file);
	}
	closedir(STARTUPDIR);
}
# If the directory already existed check if we need to start some games.
elsif ($no_startups != 1)
{

	# Loop through all the startup flags, and call universal startup
	opendir(STARTUPDIR, GAME_STARTUP_DIR);
	logger "Reading startup flags from " . GAME_STARTUP_DIR . "";
	while (my $dirlist = readdir(STARTUPDIR))
	{

		# Skip . and ..
		next if $dirlist =~ /^\./;
		logger "Found $dirlist";
		open(STARTFILE, '<', Path::Class::Dir->new(GAME_STARTUP_DIR, $dirlist))
		  || logger "Error opening start flag $!";
		while (<STARTFILE>)
		{
			my (
				$home_id,   $home_path,   $server_exe,
				$run_dir,   $startup_cmd, $server_port,
				$server_ip, $cpu, $nice, $preStart, $envVars
			   ) = split(',', $_);

			if (is_screen_running_without_decrypt(SCREEN_TYPE_HOME, $home_id) ==
				1)
			{
				logger
				  "This server ($server_exe on $server_ip : $server_port) is already running (ID: $home_id).";
				next;
			}

			logger "Starting server_exe $server_exe from home $home_path.";
			universal_start_without_decrypt(
										 $home_id,   $home_path,   $server_exe,
										 $run_dir,   $startup_cmd, $server_port,
										 $server_ip, $cpu,	$nice, $preStart, $envVars
										   );
		}
		close(STARTFILE);
	}
	closedir(STARTUPDIR);
}

# Create the pid file
open(PID, '>', AGENT_PID_FILE)
  or die("Can't write to pid file - " . AGENT_PID_FILE . "\n");
print PID "$$\n";
close(PID);

logger "Open Game Panel - Agent started - "
  . AGENT_VERSION
  . " - port "
  . AGENT_PORT
  . " - PID $$", 1;

if(-e Path::Class::File->new(FD_DIR, 'Settings.pm'))
{
	require "FastDownload/Settings.pm"; # Settings for Fast Download Daemon.
	if(defined($FastDownload::Settings{autostart_on_agent_startup}) && $FastDownload::Settings{autostart_on_agent_startup} eq "1")
	{
		start_fastdl();
	}
}

my $d = Frontier::Daemon::Forking->new(
			 methods => {
				 is_screen_running				=> \&is_screen_running,
				 universal_start			  	=> \&universal_start,
				 renice_process					=> \&renice_process,
				 cpu_count						=> \&cpu_count,
				 rfile_exists				 	=> \&rfile_exists,
				 quick_chk						=> \&quick_chk,
				 steam_cmd						=> \&steam_cmd,
				 fetch_steam_version			=> \&fetch_steam_version,
				 installed_steam_version		=> \&installed_steam_version,
				 automatic_steam_update			=> \&automatic_steam_update,
				 get_log					  	=> \&get_log,
				 stop_server				  	=> \&stop_server,
				 send_rcon_command				=> \&send_rcon_command,
				 dirlist						=> \&dirlist,
				 dirlistfm						=> \&dirlistfm,
				 readfile					 	=> \&readfile,
				 writefile						=> \&writefile,
				 rebootnow						=> \&rebootnow,
				 what_os					  	=> \&what_os,
				 start_file_download		  	=> \&start_file_download,
				 lock_additional_files          => \&mocked_lock_additional_files,
				 is_file_download_in_progress 	=> \&is_file_download_in_progress,
				 uncompress_file			  	=> \&uncompress_file,
				 discover_ips					=> \&discover_ips,
				 mon_stats						=> \&mon_stats,
				 exec						 	=> \&exec,
				 clone_home				   		=> \&clone_home,
				 remove_home					=> \&remove_home,
				 start_rsync_install			=> \&start_rsync_install,
				 rsync_progress			   		=> \&rsync_progress,
				 restart_server			   		=> \&restart_server,
				 sudo_exec						=> \&sudo_exec,
				 master_server_update			=> \&master_server_update,
				 secure_path					=> \&secure_path,
				 get_chattr						=> \&get_chattr,
				 ftp_mgr						=> \&mock_ftp_mgr,
				 compress_files					=> \&compress_files,
				 stop_fastdl					=> \&stop_fastdl,
				 restart_fastdl					=> \&restart_fastdl,
				 fastdl_status					=> \&fastdl_status,
				 fastdl_get_aliases				=> \&fastdl_get_aliases,
				 fastdl_add_alias				=> \&fastdl_add_alias,
				 fastdl_del_alias				=> \&fastdl_del_alias,
				 fastdl_get_info				=> \&fastdl_get_info,
				 fastdl_create_config			=> \&fastdl_create_config,
				 agent_restart					=> \&agent_restart,
				 scheduler_add_task				=> \&scheduler_add_task,
				 scheduler_del_task				=> \&scheduler_del_task,
				 scheduler_list_tasks			=> \&scheduler_list_tasks,
				 scheduler_edit_task			=> \&scheduler_edit_task,
				 get_file_part					=> \&get_file_part,
				 stop_update					=> \&stop_update,
				 shell_action					=> \&shell_action,
				 remote_query					=> \&remote_query
			 },
			 debug	 => 4,
			 LocalPort => AGENT_PORT,
			 LocalAddr => AGENT_IP,
			 ReuseAddr => '1'
) or die "Couldn't start OGP Agent: $!";

sub backup_home_log
{
	my ($home_id, $log_file) = @_;

	my $home_backup_dir = SCREEN_LOGS_DIR . "/home_id_" . $home_id;

	if( ! -e $home_backup_dir )
	{
		if( ! mkdir $home_backup_dir )
		{
			logger "Can not create a backup directory at $home_backup_dir.";
			return 1;
		}
	}

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	my $backup_file_name =  $mday . $mon . $year . '_' . $hour . 'h' . $min . 'm' . $sec . "s.log";

	my $output_path = $home_backup_dir . "/" . $backup_file_name;

	# Used for deleting log files older than DELETE_LOGS_AFTER
	my @file_list;
	my @find_dirs; # directories to search
	my $now = time(); # get current time
	my $days;
	if((DELETE_LOGS_AFTER =~ /^[+-]?\d+$/) && (DELETE_LOGS_AFTER > 0)){
		$days = DELETE_LOGS_AFTER; # how many days old
	}else{
		$days = 30; # how many days old
	}
	my $seconds_per_day = 60*60*24; # seconds in a day
	my $AGE = $days*$seconds_per_day; # age in seconds
	push (@find_dirs, $home_backup_dir);

	# Create local copy of log file backup in the log_backups folder and current user home directory if SCREEN_LOG_LOCAL = 1
	if(SCREEN_LOG_LOCAL == 1)
	{
		# Create local backups folder
		my $local_log_folder = Path::Class::Dir->new("logs_backup");

		if(!-e $local_log_folder){
			mkdir($local_log_folder);
		}

		# Add full path to @find_dirs so that log files older than DELETE_LOGS_AFTER are deleted
		my $fullpath_to_local_logs = Path::Class::Dir->new(getcwd(), "logs_backup");
		push (@find_dirs, $fullpath_to_local_logs);

		my $log_local = $local_log_folder . "/" . $backup_file_name;

		# Delete the local log file if it already exists
		if(-e $log_local){
			unlink $log_local;
		}

		# If the log file contains UPDATE in the filename, do not allow users to see it since it will contain steam credentials
		# Will return -1 for not existing
		my $isUpdate = index($log_file,SCREEN_TYPE_UPDATE);

		if($isUpdate == -1){
			copy($log_file,$log_local);
		}
	}

	# Delete all files in @find_dirs older than DELETE_LOGS_AFTER days
	find ( sub {
		my $file = $File::Find::name;
		if ( -f $file ) {
			push (@file_list, $file);
		}
	}, @find_dirs);

	for my $file (@file_list) {
		my @stats = stat($file);
		if ($now-$stats[9] > $AGE) {
			unlink $file;
		}
	}

	move($log_file,$output_path);

	return 0;
}

sub get_home_pids
{
	my ($home_id) = @_;
	my $screen_id = create_screen_id(SCREEN_TYPE_HOME, $home_id);
	my ($pid, @pids);
	($pid) = split(/\./, `screen -ls | grep -E -o "[0-9]+\.$screen_id"`, 2);
	chomp($pid);
	while ($pid =~ /^[0-9]+$/)
	{
		push(@pids,$pid);
		$pid = `pgrep -P $pid`;
		chomp($pid);
	}
	return @pids;
}

sub create_screen_id
{
	my ($screen_type, $home_id) = @_;
	return sprintf("OGP_%s_%09d", $screen_type, $home_id);
}

sub create_screen_cmd
{
	my ($screen_id, $exec_cmd) = @_;
	$exec_cmd = replace_OGP_Vars($screen_id, $exec_cmd);
	return
	  sprintf('export WINEDEBUG="fixme-all" && export DISPLAY=:1 && screen -d -m -t "%1$s" -c ' . SCREENRC_FILE . ' -S %1$s %2$s',
			  $screen_id, $exec_cmd);

}

sub create_screen_cmd_loop
{
	my ($screen_id, $exec_cmd, $envVars) = @_;
	my $server_start_bashfile = $screen_id . "_startup_scr.sh";

	$exec_cmd = replace_OGP_Vars($screen_id, $exec_cmd);

	# Allow file to be overwritten
	if(-e $server_start_bashfile){
		secure_path_without_decrypt('chattr-i', $server_start_bashfile);
	}

	# Create bash file that screen will run which spawns the server
	# If it crashes without user intervention, it will restart
	open (SERV_START_SCRIPT, '>', $server_start_bashfile);

	my $respawn_server_command = "#!/bin/bash" . "\n"
	. "function startServer(){" . "\n" ;

	if(defined $envVars && $envVars ne ""){
		$respawn_server_command .= $envVars;
	}

	$respawn_server_command .= "NUMSECONDS=`expr \$(date +%s)`" . "\n"
	. "until " . $exec_cmd . "; do" . "\n"
	. "let DIFF=(`date +%s` - \"\$NUMSECONDS\")" . "\n"
	. "if [ \"\$DIFF\" -gt 15 ]; then" . "\n"
	. "NUMSECONDS=`expr \$(date +%s)`" . "\n"
	. "echo \"Server '" . $exec_cmd . "' crashed with exit code \$?.  Respawning...\" >&2 " . "\n"
	. "fi" . "\n"
	. "sleep 3" . "\n"
	. "done" . "\n"
	. "let DIFF=(`date +%s` - \"\$NUMSECONDS\")" . "\n"

	. "if [ ! -e \"SERVER_STOPPED\" ] && [ \"\$DIFF\" -gt 15 ]; then" . "\n"
	. "startServer" . "\n"
	. "fi" . "\n"
	. "}" . "\n"
	. "startServer" . "\n";

	print SERV_START_SCRIPT $respawn_server_command;
	close (SERV_START_SCRIPT);

	# Secure file
	secure_path_without_decrypt('chattr+i', $server_start_bashfile);

	my $screen_exec_script = "bash " . $server_start_bashfile;

	return
	  sprintf('export WINEDEBUG="fixme-all" && export DISPLAY=:1 && screen -d -m -t "%1$s" -c ' . SCREENRC_FILE . ' -S %1$s %2$s',
			  $screen_id, $screen_exec_script);

}

sub replace_OGP_Vars{
	# This function replaces constants from game server XML Configs with OGP paths for Steam Auto Updates for example
	my ($screen_id, $exec_cmd) = @_;
	my $screen_id_for_txt_update = substr ($screen_id, rindex($screen_id, '_') + 1);
	my $steamInsFile = $screen_id_for_txt_update . "_install.txt";
	my $steamCMDPath = STEAMCMD_CLIENT_DIR;
	my $fullPath = Path::Class::File->new($steamCMDPath, $steamInsFile);

	# If the install file exists, the game can be auto updated, else it will be ignored by the game for improper syntax
	# To generate the install file, the "Install/Update via Steam" button must be clicked on at least once!
	if(-e $fullPath){
		$exec_cmd =~ s/{OGP_STEAM_CMD_DIR}/$steamCMDPath/g;
		$exec_cmd =~ s/{STEAMCMD_INSTALL_FILE}/$steamInsFile/g;
	}

	return $exec_cmd;
}

sub replace_OGP_Env_Vars{
	# This function replaces constants from environment variables set in the XML
	my ($homeid, $homepath, $strToReplace) = @_;

	$strToReplace =~ s/{OGP_HOME_DIR}/$homepath/g;

	return $strToReplace;
}

sub encode_list
{
	my $encoded_content = '';
	if(@_)
	{
		foreach my $line (@_)
		{
			$encoded_content .= encode_base64($line, "") . '\n';
		}
	}
	return $encoded_content;
}

sub decrypt_param
{
	my ($param) = @_;
	$param = decode_base64($param);
	$param = Crypt::XXTEA::decrypt($param, AGENT_KEY);
	$param = decode_base64($param);
  logger "Param  $param";
	return $param;
}

sub decrypt_params
{
	my @params;
  logger "vvvvvvvvvvvvvvvvvvv";
	foreach my $param (@_)
	{
		$param = &decrypt_param($param);
		push(@params, $param);
	}
  logger "^^^^^^^^^^^^^^^^^";
	return @params;
}

sub check_steam_cmd_client
{
	logger "STEAM CALLED check_steam_cmd_client";

	return 1;
}

sub is_screen_running
{
  logger "is_screen_running";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($screen_type, $home_id) = decrypt_params(@_);
	return is_screen_running_without_decrypt($screen_type, $home_id);
}

sub is_screen_running_without_decrypt
{
  logger "is_screen_running_without_decrypt";
	my ($screen_type, $home_id) = @_;

  my $service_name = $home_id . '_game';
  logger '$service_name ' .  $service_name;

  my $is_service_running = `sudo ./helpers/isServiceRunning.sh '$service_name'`;
  logger 'is_service_running' . $is_service_running;

  if ($is_service_running > 0) {
    return 1;
  }
  else
  {
    return 0;
  }
}

# Delete Server Stopped Status File:
sub deleteStoppedStatFile
{
  logger "deleteStoppedStatFile";
	my ($home_path) = @_;
	my $server_stop_status_file = Path::Class::File->new($home_path, "SERVER_STOPPED");
	if(-e $server_stop_status_file)
	{
		unlink $server_stop_status_file;
	}
}


sub gomplate_compose
{
  my ($home_id) = @_;

	my $installCmd = 'sudo ./helpers/gomplateInstallSetup.sh ' . GAME_DIR . ' ' . $home_id;
	logger 'gomplate command: ' . $installCmd;
	sudo_exec_without_decrypt($installCmd);

	my $cmd = 'sudo ./helpers/gomplateSetup.sh ' . GAME_DIR . ' ' . $home_id;
	logger 'gomplate command: ' . $cmd;
	sudo_exec_without_decrypt($cmd);

  return 1;
}

# Universal startup function
sub universal_start
{
  logger "universal_start";
	chomp(@_);
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return universal_start_without_decrypt(decrypt_params(@_));
}

# Split to two parts because of internal calls.
sub universal_start_without_decrypt
{
  logger "universal_start_without_decrypt";
	my (
		$home_id, $home_path, $server_exe, $run_dir,
		$startup_cmd, $server_port, $server_ip, $cpu, $nice, $preStart, $envVars
	   ) = @_;

	# Replace any {OGP_HOME_DIR} in the $start_cmd with the server's home directory path
	$startup_cmd = replace_OGP_Env_Vars($home_id, $home_path, $startup_cmd);

  logger "=================================";
  logger "HOME_id $home_id";
  logger "home_path $home_path";
  logger "server_exe $server_exe";
  logger "run_dir $run_dir";
  logger "startup command: $startup_cmd";

  logger "server_port $server_port";
  logger "server_ip $server_ip";
  logger "cpu $cpu";
  logger "nice $nice";
  logger "preStart $preStart";
  logger "envVars $envVars";
  logger "=================================";

  my $game_instance_dir = GAME_DIR . '/' . $home_id;
  logger "game_instance_dir   $game_instance_dir";

  if (is_screen_running_without_decrypt(SCREEN_TYPE_HOME, $home_id) == 1)
    {
    logger "This server is already running (ID: $home_id).";
    return -14;
  }

  start_docker_install($home_id);

  my $cmd = 'sudo ./helpers/startService.sh ' . GAME_DIR . ' ' . $home_id;
  logger 'start command: ' . $cmd;
  sudo_exec_without_decrypt($cmd);

  return 1;

}

# This is used to change the priority of process
# @return 1 if successfully set prosess priority
# @return -1 in case of an error.
sub renice_process
{
  logger "renice_process";
	return 1;
}

# This is used to force a process to run on a particular CPU
sub force_cpu
{
  logger "force_cpu";
	return 1;
}

# Returns the number of CPUs available.
sub cpu_count
{
  return "0";
}

### File exists check ####
# Simple a way to check if a file exists using the remote agent
#
# @return 0 when file exists.
# @return 1 when file does not exist.
sub rfile_exists
{
  logger "rfile_exists";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");

	chdir AGENT_RUN_DIR;
	my $checkFile = decrypt_param(@_);

  # Speacial handling for 'startup' which is used to know if a service has been started
  # This may not be needed...
  if (index($checkFile, 'startups') != -1) {
     logger 'Its a health check, say its down!';
     return 1;
  }
  else
  {
    return 0;
  }

	if (-e $checkFile)
	{
		return 0;
	}
	else
	{
		return 1;
	}
}

#### Quick check to verify agent is up and running
# Used to quickly see if the agent is online, and if the keys match.
# The message that is sent to the agent must be hello, if not then
# it is intrepret as encryption key missmatch.
#
# @return 1 when encrypted message is not 'hello'
# @return 0 when check is ok.
sub quick_chk
{
  logger "Doing a quick_chk";
	my $dec_check = &decrypt_param(@_);
	if ($dec_check ne 'hello')
	{
		logger "ERROR - Encryption key mismatch! Returning 1 to asker.";
		return 1;
	}
	return 0;
}

sub log_rpc
{
  my @newlist = @{my $self->{@_}};
  logger "vvvvvvvvvv START vvvvvvvvvvv";
  foreach (&decrypt_params(@newlist))
  {
    logger "PARAM " . $_;
  }
  logger "^^^^^^^^^^^^^^ Done ^^^^^^^^^^^^^";
  # logger "Logged RPC params (sub) " . decrypt_params(@_);
	# return 0;
}

### Return -10 If home path is not found.
### Return -9  If log type was invalid.
### Return -8  If log file was not found.
### 0 reserved for connection problems.
### Return 1;content If log found and screen running.
### Return 2;content If log found but screen is not running.
sub get_log
{
  logger "get_log";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");

	my ($screen_type, $home_id, $home_path, $nb_of_lines, $log_file) = decrypt_params(@_);

  my $service_name = $home_id . '_game';
  logger '$service_name ' .  $service_name;

	# Return a few lines of output to the web browser
	# my(@modedlines) = `tail -n $nb_of_lines $log_file`;

  my(@modedlines) = `sudo docker service logs --raw --tail 2 $service_name`;

  if(is_screen_running_without_decrypt($screen_type, $home_id) == 1)
	{
    my $containerId = `sudo docker ps --filter label=com.docker.swarm.service.name=$service_name --format='table {{.ID}}'`;

    #TODO: Doing something like the follwoing line would give better logging if the service is up
    # push @modedlines `docker exec $containerId tail -n $nb_of_lines tail ./log/console/gmodserver-console.log`;
  }

	my $linecount = 0;

	foreach my $line (@modedlines) {
    logger ' Log Line: (' . $linecount . ')' . $line;
		#Text replacements to remove the Steam user login from steamcmd logs for security reasons.
		$line =~ s/login .*//g;
		$line =~ s/Logging .*//g;
		$line =~ s/set_steam_guard_code.*//g;
		$line =~ s/force_install_dir.*//g;
		#Text replacements to remove empty lines.
		$line =~ s/^ +//g;
		$line =~ s/^\t+//g;
		$line =~ s/^\e+//g;
		#Remove � from console output when master server update is running.
		$line =~ s/�//g;
		$modedlines[$linecount]=$line;
		$linecount++;
	}

	my $encoded_content = encode_list(@modedlines);
  return "1;" . $encoded_content;
}

# stop server function
sub stop_server
{
	chomp(@_);
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return stop_server_without_decrypt(decrypt_params(@_));
}

##### Stop server without decrypt
### Return 1 when error occurred on decryption.
### Return 0 on success
sub stop_server_without_decrypt
{
  logger "stop_server_without_decrypt";
	my ($home_id, $server_ip, $server_port, $control_protocol,
		$control_password, $control_type, $home_path) = @_;

  	my $service_name = $home_id . '_game';

  	my $docker_run_command = `sudo ./helpers/scaleService.sh '$service_name' 0`;
	logger 'docker command: ' . $docker_run_command;
	sudo_exec_without_decrypt($docker_run_command);
	return 0;
}

##### Send RCON command
### Return 0 when error occurred on decryption.
### Return 1 on success
sub send_rcon_command
{
  logger "send_rcon_command";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($home_id, $server_ip, $server_port, $control_protocol,
		$control_password, $control_type, $rconCommand) = decrypt_params(@_);

	# legacy console
	if ($control_protocol eq "lcon")
	{
		my $screen_id = create_screen_id(SCREEN_TYPE_HOME, $home_id);
		system('screen -S '.$screen_id.' -p 0 -X stuff "'.$rconCommand.'$(printf \\\\r)"');
		logger "Sending legacy console command to ".$screen_id.": \n$rconCommand \n .";
		if ($? == -1)
		{
			my(@modedlines) = "$rconCommand";
			my $encoded_content = encode_list(@modedlines);
			return "1;" . $encoded_content;
		}
		return 0;
	}

	# Some validation checks for the variables.
	if ($server_ip =~ /^\s*$/ || $server_port < 0 || $server_port > 65535)
	{
		logger("Invalid IP:Port given $server_ip:$server_port.");
		return 0;
	}

	if ($control_password !~ /^\s*$/)
	{
		if ($control_protocol eq "rcon")
		{
			use KKrcon::KKrcon;
			my $rcon = new KKrcon(
								  Password => $control_password,
								  Host	 => $server_ip,
								  Port	 => $server_port,
								  Type	 => $control_type
								 );

			logger "Sending RCON command to $server_ip:$server_port: \n$rconCommand \n  .";

			my(@modedlines) = $rcon->execute($rconCommand);
			my $encoded_content = encode_list(@modedlines);
			return "1;" . $encoded_content;
		}
		else
		{
			if ($control_protocol eq "rcon2")
			{
				use KKrcon::HL2;
				my $rcon2 = new HL2(
									  hostname => $server_ip,
									  port	 => $server_port,
									  password => $control_password,
									  timeout  => 2
									 );

				logger "Sending RCON command to $server_ip:$server_port: \n $rconCommand \n  .";

				my(@modedlines) = $rcon2->run($rconCommand);
				my $encoded_content = encode_list(@modedlines);
				return "1;" . $encoded_content;
			}
		}
	}
	else
	{
		logger "Control protocol PASSWORD NOT SET.";
		return -10;
	}
}

##### Returns a directory listing
### @return List of directories if everything OK.
### @return 0 If the directory is not found.
### @return -1 If cannot open the directory.
sub dirlist
{
  logger "dirlist";
  return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
  my ($datadir) = &decrypt_param(@_);
  logger "Asked for dirlist of $datadir directory.";
  return "foo;bar";
}

##### Returns a directory listing with extra info the filemanager
### @return List of directories if everything OK.
### @return 1 If the directory is empty.
### @return -1 If the directory is not found.
### @return -2 If cannot open the directory.
sub dirlistfm
{
  logger "send_rcon_command";
  return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
  my $datadir = &decrypt_param(@_);

  logger "Asked for dirlist of $datadir directory.";
  return 1;
}

sub map_filepath
{
  my ($filepath) = @_;
  logger "Mapping filepath ". $filepath;
  my $find    = '/home/ogp_agent/OGP_User_Files/';
  my $replace = GAME_DIR;

  $filepath =~ s/$find/$replace/g;
  logger "Mapped filepath ". $filepath;
  return $filepath;
}


###### Returns the contents of a text file
sub readfile
{
  logger "readfile";
  return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
#   chdir AGENT_RUN_DIR;
  my $userfile = &decrypt_param(@_);

  $userfile = map_filepath($userfile);
  parse_create_home_dir($userfile);

  return "1; ";

}

sub parse_create_home_dir
{
	my ( $path ) = @_;

	my $game_dir = GAME_DIR;

	my $home_id = `sudo ./helpers/getHomeId.sh '$game_dir' '$path'`;
  	logger 'home_id' . $home_id;
	  if ( ($home_id ne "0") && ($home_id > 0))
  	  { 
			logger 'home_id IS VALID';
			create_home_dir($home_id);
  	  }

}

###### Backs up file, then writes data to new file
### @return 1 On success
### @return 0 In case of a failure
sub writefile
{
  logger "writefile";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	chdir AGENT_RUN_DIR;
	# $writefile = file we're editing, $filedata = the contents were writing to it
	my ($writefile, $filedata) = &decrypt_params(@_);



  $writefile = map_filepath($writefile);
  parse_create_home_dir($writefile);
  

  my 	$filedata2 = decode_base64($filedata);
  $filedata2 =~ s/\r//g;
  logger "vvvvvvvvvvvvvvvvvvvvvvvv";
  logger "writefile $writefile";
  logger "filedata $filedata";
  logger "filedata2 $filedata2";
  logger "^^^^^^^^^^^^^^^^^^^^^^^^^";

	if (!-e $writefile)
	{
		open FILE, ">", $writefile;
	}
	else
	{
		# backup the existing file
		logger
		  "Backing up file $writefile to $writefile.bak before writing new data.";
		if (!copy("$writefile", "$writefile.bak"))
		{
			logger
			  "ERROR - Failed to backup $writefile to $writefile.bak. Error: $!";
			return 0;
		}
	}
	if (!-w $writefile)
	{
		logger "ERROR - File [ $writefile ] is not writeable!";
		return 0;
	}
	if (!open(WRITER, '>', $writefile))
	{
		logger "ERROR - Failed to open $writefile for writing.";
		return 0;
	}

  # Always clear out the file before writing the new one
  my $trunc_file = 'truncate -s 0 ' . $writefile;
  sudo_exec_without_decrypt($trunc_file);

	$filedata = decode_base64($filedata);
	$filedata =~ s/\r//g;
	print WRITER "$filedata";
	close(WRITER);
	logger "Wrote $writefile successfully!";
	return 1;
}

###### Reboots the server remotely through panel
### @return 1 On success
### @return 0 In case of a failure
sub rebootnow
{
  logger "rebootnow";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	sudo_exec_without_decrypt('sleep 10s; shutdown -r now');
	logger "Scheduled system reboot to occur in 10 seconds successfully!";
	return 1;
}

# Determine the os of the agent machine.
sub what_os
{
  logger "what_os";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");

	logger "Asking for OS type JOSH";
	my $which_uname = `which uname`;
	chomp $which_uname;
	if ($which_uname ne "")
	{
		my $os;
		my $os_name;
		my $os_arch;
		my $wine_ver = "";
		$os_name = `$which_uname`;
		chomp $os_name;
		$os_arch = `$which_uname -m`;
		chomp $os_arch;
		my $which_wine = `which wine`;
		chomp $which_wine;
		if ($which_wine ne "")
		{
			$wine_ver = `$which_wine --version`;
			chomp $wine_ver;
			$wine_ver = "|".$wine_ver;
		}
		$os = $os_name." ".$os_arch.$wine_ver;
		logger "OS is $os";
		return "$os";
	}
	else
	{
		logger "Cannot determine OS..that is odd";
		return "Unknown";
	}
}

### @return PID of the download process if started succesfully.
### @return -1 If could not create temporary download directory.
### @return -2 If could not create destination directory.
### @return -3 If resources unavailable.
sub start_file_download
{
  logger "start_file_download";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($url, $destination, $filename, $action, $post_script) = &decrypt_params(@_);
	logger
	  "Starting to download URL $url. Destination: $destination - Filename: $filename";

	if (!-e $destination)
	{
		logger "Creating destination directory.";
		if (!mkpath $destination )
		{
			logger "Could not create destination '$destination' directory : $!";
			return -2;
		}
	}

	my $download_file_path = Path::Class::File->new($destination, "$filename");

	my $pid = fork();
	if (not defined $pid)
	{
		logger "Could not allocate resources for download.";
		return -3;
	}

	# Only the forked child goes here.
	elsif ($pid == 0)
	{
		my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0,
													SSL_verify_mode => 0x00 } );
		$ua->agent('Mozilla/5.0');
		my $response = $ua->get($url, ':content_file' => "$download_file_path");

		if ($response->is_success)
		{
			logger "Successfully fetched $url and stored it to $download_file_path. Retval: ".$response->status_line;

			if (!-e $download_file_path)
			{
				logger "File $download_file_path does not exist.";
				exit(0);
			}

			if ($action eq "uncompress")
			{
				logger "Starting file uncompress as ordered.";
				uncompress_file_without_decrypt($download_file_path,
												$destination);
			}
		}
		else
		{
			logger
			  "Unable to fetch $url, or save to $download_file_path. Retval: ".$response->status_line;
			exit(0);
		}

		# Child process must exit.
		exit(0);
	}
	else
	{
		if ($post_script ne "")
		{
			logger "Running postscript commands.";
			my @postcmdlines = split /[\r\n]+/, $post_script;
			my $postcmdfile = $destination."/".'postinstall.sh';
			open  FILE, '>', $postcmdfile;
			print FILE "cd $destination\n";
			print FILE "while kill -0 $pid >/dev/null 2>&1\n";
			print FILE "do\n";
			print FILE "	sleep 1\n";
			print FILE "done\n";
			foreach my $line (@postcmdlines) {
				print FILE "$line\n";
			}
			print FILE "rm -f $destination/postinstall.sh\n";
			close FILE;
			chmod 0755, $postcmdfile;
			my $screen_id = create_screen_id("post_script", $pid);
			my $cli_bin = create_screen_cmd($screen_id, "bash $postcmdfile");
			system($cli_bin);
		}
		logger "Download process for $download_file_path has pid number $pid.";
		return "$pid";
	}
}

sub mocked_lock_additional_files{
  logger "MOCKED lock_additional_files";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return ""
}

sub run_before_start_commands
{
  logger "run_before_start_commands";
	#return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($server_id, $homedir, $beforestartcmd, $envVars) = @_;

	if ($homedir ne "" && $server_id ne ""){
		# Run any prestart scripts
		if (defined $beforestartcmd && $beforestartcmd ne "")
		{
			logger "Running pre-start XML commands before starting server ID $server_id with a home directory of $homedir.";
			my @prestartcmdlines = split /[\r\n]+/, $beforestartcmd;
			my $prestartcmdfile = $homedir."/".'prestart_ogp.sh';
			open  FILE, '>', $prestartcmdfile;
			print FILE "#!/bin/bash" . "\n";
			print FILE "cd $homedir\n";
			foreach my $line (@prestartcmdlines) {
				print FILE "$line\n";
			}
			print FILE "rm -f $prestartcmdfile\n";
			close FILE;
			chmod 0755, $prestartcmdfile;
			system("bash $prestartcmdfile");
		}


		# Set and export any environment variables for game server developers unwilling to properly learn Linux
		if (defined $envVars && $envVars ne ""){
			my @prestartenvvars = split /[\r\n]+/, $envVars;
			foreach my $line (@prestartenvvars) {
				$line = replace_OGP_Env_Vars($server_id, $homedir, $line);
				if($line ne ""){
					logger "Configuring environment variable: $line";
					system($line);
				}
			}
		}

	}else{
		return -2;
	}

	return 1;
}

sub multiline_to_startup_comma_format{
  logger "multiline_to_startup_comma_format";
	my ($multiLineVar) = @_;
	$multiLineVar =~ s/,//g; # commas are invalid anyways in bash
	$multiLineVar =~ s/[\r]+//g;
	$multiLineVar =~ s/[\n]+/{OGPNEWLINE}/g;
	return $multiLineVar;
}

sub startup_comma_format_to_multiline{
  logger "startup_comma_format_to_multiline";
	my ($multiLineVar) = @_;
	$multiLineVar =~ s/{OGPNEWLINE}/\n/g;
	return $multiLineVar;
}

sub create_secure_script
{
  logger "create_secure_script";
	my ($home_path, $exec_folder_path, $exec_path) = @_;
	secure_path_without_decrypt('chattr-i', $home_path);
	my $secure = "$home_path/secure.sh";
	$home_path =~ s/('+)/'\"$1\"'/g;
	$exec_folder_path =~ s/('+)/'\"$1\"'/g;
	$exec_path =~ s/('+)/'\"$1\"'/g;
	my $sec = $secure;
	$sec =~ s/('+)/'\"$1\"'/g;
	open  FILE, '>', $secure;
	print FILE	"chmod 771 '$exec_folder_path'\n".
				"chmod 750 '$exec_path'\n".
				"chmod +x '$exec_path'\n".
				"chattr +i '$exec_path'\n".
				"rm -f '$sec'";
	close FILE;
	chmod 0770, $secure;
	sudo_exec_without_decrypt("chown 0:0 '$sec'");
	return 0;
}

sub create_bash_scripts
{
	my ( $home_path, $bash_scripts_path, $precmd, $postcmd, @installcmds ) = @_;

	$home_path         =~ s/('+)/'\"$1\"'/g;
	$bash_scripts_path =~ s/('+)/'\"$1\"'/g;

	my @precmdlines = split /[\r\n]+/, $precmd;
	my $precmdfile = 'preinstall.sh';
	open  FILE, '>', $precmdfile;
	print FILE "cd '$home_path'\n";
	foreach my $line (@precmdlines) {
		print FILE "$line\n";
	}
	close FILE;
	chmod 0755, $precmdfile;

	my @postcmdlines = split /[\r\n]+/, $postcmd;
	my $postcmdfile = 'postinstall.sh';
	open  FILE, '>', $postcmdfile;
	print FILE "cd '$home_path'\n";
	foreach my $line (@postcmdlines) {
		print FILE "$line\n";
	}
	print FILE "cd '$home_path'\n".
			   "echo '".$SUDOPASSWD."' | sudo -S -p \"\" bash secure.sh\n".
			   "rm -f secure.sh\n".
			   "cd '$bash_scripts_path'\n".
			   "rm -f preinstall.sh\n".
			   "rm -f postinstall.sh\n".
			   "rm -f runinstall.sh\n";
	close FILE;
	chmod 0755, $postcmdfile;

	my $installfile = 'runinstall.sh';
	open  FILE, '>', $installfile;
	print FILE "#!/bin/bash\n".
			   "cd '$bash_scripts_path'\n".
			   "./$precmdfile\n";
	foreach my $installcmd (@installcmds)
	{
		print FILE "$installcmd\n";
	}
	print FILE "wait ".'${!}'."\n".
			   "cd '$bash_scripts_path'\n".
			   "./$postcmdfile\n";
	close FILE;
	chmod 0755, $installfile;

	return $installfile;
}

#### Run the rsync update ####
### @return 1 If update started
### @return 0 In error case.
sub start_rsync_install
{
  #TODO: This function should create the directory and copy the base docker-compose file into Place

	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($home_id, $home_path, $url, $exec_folder_path, $exec_path, $precmd, $postcmd, $filesToLockUnlock) = decrypt_params(@_);

  logger "=================================";
  logger "HOME_id $home_id";
  logger "home_path $home_path";
  logger "=================================";

  start_docker_install($home_id);

  return 1;

}







sub start_docker_install
{
	my ($home_id) = @_;

	create_home_dir($home_id);

	gomplate_compose($home_id);

	my $installImageCmd = 'sudo ./helpers/doLocalInstall.sh ' . GAME_DIR . ' ' . $home_id;
	logger 'start command: ' . $installImageCmd;
	sudo_exec_without_decrypt($installImageCmd);	

    return 1;
}

sub create_home_dir
{
	my ($home_id) = @_;

	my $cmd = 'sudo ./helpers/setupHome.sh ' . GAME_DIR . ' ' . $home_id;
	logger 'docker command: ' . $cmd;
	sudo_exec_without_decrypt($cmd);
}







### @return PID of the download process if started succesfully.
### @return -1 If could not create temporary download directory.
### @return -2 If could not create destination directory.
### @return -3 If resources unavailable.
sub master_server_update
{
	logger "CALLED master_server_update";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($home_id,$home_path,$ms_home_id,$ms_home_path,$exec_folder_path,$exec_path,$precmd,$postcmd) = decrypt_params(@_);

	start_docker_install($home_id);

	return 1;
}

sub steam_cmd
{
	chomp(@_);
	logger "STEAM CALLED steam_cmd";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return steam_cmd_without_decrypt(decrypt_params(@_));
}

#### Run the steam client ####
### @return 1 If update started
### @return 0 In error case.
sub steam_cmd_without_decrypt
{
	my ($home_id, $home_path, $mod, $modname, $betaname, $betapwd, $user, $pass, $guard, $exec_folder_path, $exec_path, $precmd, $postcmd, $cfg_os, $filesToLockUnlock) = @_;
	logger "STEAM CALLED steam_cmd_without_decrypt";

	start_docker_install($home_id);

	return 1;
}

sub fetch_steam_version
{
	logger "STEAM CALLED fetch_steam_version";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($appId, $pureOutput) = &decrypt_params(@_);

	my $steam_binary = Path::Class::File->new(STEAMCMD_CLIENT_DIR, "steamcmd.sh");
	my $steam_options = "+login anonymous +app_info_update 1 +app_info_print \"$appId\" +quit";
	my $grep = $pureOutput != "0" ? "" : '| grep -EA 1000 "^\s+\"branches\"$" | grep -EA 5 "^\s+\"public\"$" | grep -m 1 -EB 10 "^\s+}$" | grep -E "^\s+\"buildid\"\s+" | tr \'[:blank:]"\' \' \' | tr -s \' \' | cut -d\' \' -f3';

	logger "Getting latest version info for AppId $appId";
	my $response = `$steam_binary $steam_options $grep`;

	return $response;
}

sub installed_steam_version
{
	logger "STEAM CALLED installed_steam_version";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($game_home, $mod, $pureOutput) = &decrypt_params(@_);
	my $appFile = $game_home."/steamapps/appmanifest_$mod.acf";
	my $grep = $pureOutput != "0" ? "" : '| grep buildid | tr \'[:blank:]"\' \' \' | tr -s \' \' | cut -d\' \' -f3';

	if ( ! -f $appFile)
	{
		return "-10";
	}

	return `cat $appFile $grep`;
}

sub automatic_steam_update
{
	logger "STEAM CALLED automatic_steam_update";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($home_id, $game_home, $server_ip, $server_port, $exec_path, $exec_folder_path,
		$control_protocol, $control_password, $control_type,
		$appId, $modname, $betaname, $betapwd, $user, $pass, $guard, $precmd, $postcmd, $cfg_os, $filesToLockUnlock,
		$startup_cmd, $cpu, $nice, $preStart, $envVars) = &decrypt_params(@_);

	# Is the server currently running? if it is, we'll try to start it after updating.
	my $isServerRunning = is_screen_running_without_decrypt(SCREEN_TYPE_HOME, $home_id) == 1 ? 1 : 0;

	# Check if an update is already happening.
	if (is_screen_running_without_decrypt(SCREEN_TYPE_UPDATE, $home_id) == 1)
	{
		logger("Update already running for server $home_id, unable to start automatic update.");
		return -10;
	}

	# Stop the server if it's running.
	if ($isServerRunning == 1)
	{
		logger("Stopping server $home_id for automatic update.");

		if (stop_server_without_decrypt($home_id, $server_ip, $server_port, $control_protocol, $control_password, $control_type, $game_home) != 0)
		{
			logger("Failed to stop server $home_id for automatic update. Exiting update procedure.");
			return -9
		}

	}

	# steam_cmd: Returns 0 if the update failed, in which case, don't try starting the server - because we may have an incomplete or corrupt installation.
	if (steam_cmd_without_decrypt($home_id, $game_home, $appId, $modname, $betaname, $betapwd, $user, $pass, $guard, $exec_folder_path, $exec_path, $precmd, $postcmd, $cfg_os, $filesToLockUnlock) == 0)
	{
		logger("Failed to start steam_cmd for server $home_id.");
		return -8;

	} else {

		if ($isServerRunning == 1)
		{
			while (1)
			{
				# If the update screen for $home_id isn't running, attempt to start the server.
				if (is_screen_running_without_decrypt(SCREEN_TYPE_UPDATE, $home_id) == 0)
				{

					if (universal_start_without_decrypt($home_id, $game_home, $exec_path, $exec_folder_path, $startup_cmd, $server_port, $server_ip, $cpu, $nice, $preStart, $envVars) != 1)
					{
						logger("Failed to start server $home_id after automatic update.");
						return -7;
					} else {
						logger("Starting server $home_id after automatic update.");
						return 1;
					}

					last;
				}

				sleep 5;
			}

		} else {
			# Update was started, but server wasn't initially running.
			return 2;
		}

	}

}

sub rsync_progress
{
	logger "CALLED rsyn progress";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($running_home) = &decrypt_param(@_);
	logger "User requested progress on rsync job on home $running_home.";
	if (-r $running_home)
	{
		$running_home =~ s/('+)/'"$1"'/g;
		my $progress = `du -sk '$running_home'`;
		chomp($progress);
		my ($bytes, $junk) = split(/\s+/, $progress);
		logger("Found $bytes and $junk");
		return $bytes;
	}
	return "0";
}

sub is_file_download_in_progress
{
	logger "CALLED is file download in progress";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($pid) = &decrypt_param(@_);
	logger "User requested if download is in progress with pid $pid.";
	my @pids = `ps -ef`;
	@pids = grep(/$pid/, @pids);
	logger "Number of pids for file download: @pids";
	if (@pids > '0')
	{
		return 1;
	}
	return 0;
}

### \return 1 If file is uncompressed succesfully.
### \return 0 If file does not exist.
### \return -1 If file could not be uncompressed.
sub uncompress_file
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return uncompress_file_without_decrypt(decrypt_params(@_));
}

sub uncompress_file_without_decrypt
{

	logger "CALLED uncomress";

	# File must include full path.
	my ($file, $destination) = @_;

	logger "Uncompression called for file $file to dir $destination.";

	if (!-e $file)
	{
		logger "File $file could not be found for uncompression.";
		return 0;
	}

	if (!-e $destination)
	{
		mkpath($destination, {error => \my $err});
		if (@$err)
		{
			logger "Failed to create destination dir $destination.";
			return 0;
		}
	}

	my $ae = Archive::Extract->new(archive => $file);

	if (!$ae)
	{
		logger "Could not create archive instance for file $file.";
		return -1;
	}

	my $ok = $ae->extract(to => $destination);

	if (!$ok)
	{
		logger "File $file could not be uncompressed.";
		return -1;
	}

	logger "File uncompressed/extracted successfully.";
	return 1;
}

### \return 1 If files are compressed succesfully.
### \return -1 If files could not be compressed.
sub compress_files
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return compress_files_without_decrypt(decrypt_params(@_));
}

sub compress_files_without_decrypt
{
	logger "CALLED compress";
	
	my ($files,$destination,$archive_name,$archive_type) = @_;

	if (!-e $destination)
	{
		logger "compress_files: Destination path ( $destination ) could not be found.";
		return -1;
	}

	chdir $destination;
	my @items = split /\Q\n/, $files;
	my @inventory;
	if($archive_type eq "zip")
	{
		logger $archive_type." compression called, destination archive is: $destination$archive_name.$archive_type";
		my $zip = Archive::Zip->new();
		foreach my $item (@items) {
			if(-e $item)
			{
				if (-f $item)
				{
					$zip->addFile( $item );
				}
				elsif (-d $item)
				{
					$zip->addTree( $item, $item );
				}
			}
		}
		# Save the file
		unless ( $zip->writeToFileNamed($archive_name.'.zip') == AZ_OK ) {
			logger "Write Error at $destination/$archive_name.$archive_type";
			return -1
		}
		logger $archive_type." archive $destination$archive_name.$archive_type created successfully";
		return 1;
	}
	elsif($archive_type eq "tbz")
	{
		logger $archive_type." compression called, destination archive is: $destination$archive_name.$archive_type";
		my $tar = Archive::Tar->new;
		foreach my $item (@items) {
			if(-e $item)
			{
				if (-f $item)
				{
					$tar->add_files( $item );
				}
				elsif (-d $item)
				{
					@inventory = ();
					find (sub { push @inventory, $File::Find::name }, $item);
					$tar->add_files( @inventory );
				}
			}
		}
		# Save the file
		unless ( $tar->write("$archive_name.$archive_type", COMPRESS_BZIP) ) {
			logger "Write Error at $destination/$archive_name.$archive_type";
			return -1
		}
		logger $archive_type." archive $destination$archive_name.$archive_type created successfully";
		return 1;
	}
	elsif($archive_type eq "tgz")
	{
		logger $archive_type." compression called, destination archive is: $destination$archive_name.$archive_type";
		my $tar = Archive::Tar->new;
		foreach my $item (@items) {
			if(-e $item)
			{
				if (-f $item)
				{
					$tar->add_files( $item );
				}
				elsif (-d $item)
				{
					@inventory = ();
					find (sub { push @inventory, $File::Find::name }, $item);
					$tar->add_files( @inventory );
				}
			}
		}
		# Save the file
		unless ( $tar->write("$archive_name.$archive_type", COMPRESS_GZIP) ) {
			logger "Write Error at $destination/$archive_name.$archive_type";
			return -1
		}
		logger $archive_type." archive $destination$archive_name.$archive_type created successfully";
		return 1;
	}
	elsif($archive_type eq "tar")
	{
		logger $archive_type." compression called, destination archive is: $destination$archive_name.$archive_type";
		my $tar = Archive::Tar->new;
		foreach my $item (@items) {
			if(-e $item)
			{
				if (-f $item)
				{
					$tar->add_files( $item );
				}
				elsif (-d $item)
				{
					@inventory = ();
					find (sub { push @inventory, $File::Find::name }, $item);
					$tar->add_files( @inventory );
				}
			}
		}
		# Save the file
		unless ( $tar->write("$archive_name.$archive_type") ) {
			logger "Write Error at $destination/$archive_name.$archive_type";
			return -1
		}
		logger $archive_type." archive $destination$archive_name.$archive_type created successfully";
		return 1;
	}
	elsif($archive_type eq "bz2")
	{
		logger $archive_type." compression called.";
		foreach my $item (@items) {
			if(-e $item)
			{
				if (-f $item)
				{
					bzip2 $item => "$item.bz2";
				}
				elsif (-d $item)
				{
					@inventory = ();
					find (sub { push @inventory, $File::Find::name }, $item);
					foreach my $relative_item (@inventory) {
						bzip2 $relative_item => "$relative_item.bz2";
					}
				}
			}
		}
		logger $archive_type." archives created successfully at $destination";
		return 1;
	}
}

sub discover_ips
{
	logger "CALLED discover ips";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($check) = decrypt_params(@_);

	if ($check ne "chk")
	{
		logger "Invalid parameter '$check' given for discover_ips function.";
		return "";
	}

	my $iplist = '0.0.0.0';
	my $ipfound;
	my $junk;

	my @ipraw = `/sbin/ifconfig`;
	while (<@ipraw>)
	{
		chomp;
		next if $_ !~ /^inet:/ ;
		logger "Found addr on line: $_";
		($junk, $ipfound) = split(":", $_);
		next if $ipfound eq '';
		next if $ipfound eq '127.0.0.1';

		logger "Found an IP $ipfound";
		$iplist .= "$ipfound,";
		logger "IPlist is now $iplist";
	}
	while (<@ipraw>)
	{
		chomp;
		next if $_ !~ /^addr:/ ;
		logger "Found addr on line: $_";
		($junk, $ipfound) = split(":", $_);
		next if $ipfound eq '';
		next if $ipfound eq '127.0.0.1';

		logger "Found an IP $ipfound";
		$iplist .= "$ipfound,";
		logger "IPlist is now $iplist";
	}
	chop $iplist;
	return "$iplist";
}

### Return -1 In case of invalid param
### Return 1;content in case of success
sub mon_stats
{
	logger "CALLED mon stats";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($mon_stats) = decrypt_params(@_);
	if ($mon_stats ne "mon_stats")
	{
		logger "Invalid parameter '$mon_stats' given for $mon_stats function.";
		return -1;
	}

	my @disk			= `df -hP -x tmpfs`;
	my $encoded_content = encode_list(@disk);
	my @uptime			= `uptime`;
	$encoded_content   .= encode_list(@uptime);
	return "1;$encoded_content";
}

sub exec
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($command) 		= decrypt_params(@_);
	my @cmdret			= `$command 2>/dev/null`;
	my $encoded_content	= encode_list(@cmdret);
	return "1;$encoded_content";
}

# used in conjunction with the clone_home feature in the web panel
# this actually does the file copies
sub clone_home
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($source_home, $dest_home, $owner) = decrypt_params(@_);
	my ($time_start, $time_stop, $time_diff);
	logger "Copying from $source_home to $dest_home...";
	return 1;
}

# used to delete the game home from the file system when it's removed from the panel
sub remove_home
{
	logger "CALLED remove home";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($home_path_del) = decrypt_params(@_);

	if (!-e $home_path_del)
	{
		logger "ERROR - $home_path_del does not exist...nothing to do";
		return 0;
	}

	secure_path_without_decrypt('chattr-i', $home_path_del);
	sleep 1 while ( !pathrmdir("$home_path_del") );
	logger "Deletetion of $home_path_del successful!";
	return 1;
}

sub restart_server
{
	chomp(@_);
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return restart_server_without_decrypt(decrypt_params(@_));
}

### Restart the server
## return -2 CANT STOP
## return -1  CANT START (no startup file found that mach the home_id, port and ip)
## return 1 Restart OK
sub restart_server_without_decrypt
{
	logger "CALLED restart server";
	
	my ($home_id, $server_ip, $server_port, $control_protocol,
		$control_password, $control_type, $home_path, $server_exe, $run_dir,
		$cmd, $cpu, $nice, $preStart, $envVars) = @_;

	if (stop_server_without_decrypt($home_id, $server_ip,
									$server_port, $control_protocol,
									$control_password, $control_type, $home_path) == 0)
	{
		if (universal_start_without_decrypt($home_id, $home_path, $server_exe, $run_dir,
											$cmd, $server_port, $server_ip, $cpu, $nice, $preStart, $envVars) == 1)
		{
			return 1;
		}
		else
		{
			return -1;
		}
	}
	else
	{
		return -2;
	}
}

sub sudo_exec
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my $sudo_exec = &decrypt_param(@_);
	return sudo_exec_without_decrypt($sudo_exec);
}

sub sudo_exec_without_decrypt
{
	my ($sudo_exec) = @_;
	$sudo_exec =~ s/('+)/'"$1"'/g;
	# my $command = "echo '$SUDOPASSWD'|sudo -kS -p \"\" su -c '$sudo_exec;echo \$?' root 2>&1";
	my $command = "echo '$SUDOPASSWD'|sudo -kS -p \"\" su -c '$sudo_exec;echo \$?' root 2>>/opt/OGP/ogp_agent_sudo.log";
	my @cmdret = qx($command);
	chomp(@cmdret);
	my $ret = pop(@cmdret);
	chomp($ret);
	if ("X$ret" eq "X0")
	{
		return "1;".encode_list(@cmdret);
	}
	return -1;
}

sub secure_path
{
	chomp(@_);
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return secure_path_without_decrypt(decrypt_params(@_));
}

sub secure_path_without_decrypt
{
	logger "CALLED secure path";
	
	my ($action, $file_path, $returnType) = @_;
	my $checkIfFileExists = 1;

	if(defined $returnType && $returnType eq "str"){
		$checkIfFileExists = 0;
	}

	if($checkIfFileExists){
		if(! -e $file_path){
			return -1;
		}
	}

	my $uid = `id -u`;
	chomp $uid;
	my $gid = `id -g`;
	chomp $gid;
	$file_path =~ s/('+)/'\"$1\"'/g;
	if($action eq "chattr+i")
	{
		if(defined $returnType && $returnType eq "str"){
			return 'chown -Rf '.$uid.':'.$gid.' \''.$file_path.'\' && chattr -Rf +i \''.$file_path.'\'';
		}else{
			return sudo_exec_without_decrypt('chown -Rf '.$uid.':'.$gid.' \''.$file_path.'\' && chattr -Rf +i \''.$file_path.'\'');
		}
	}
	elsif($action eq "chattr-i")
	{
		if(defined $returnType && $returnType eq "str"){
			return 'chattr -Rf -i \''.$file_path.'\' && chown -Rf '.$uid.':'.$gid.' \''.$file_path.'\'';
		}else{
			return sudo_exec_without_decrypt('chattr -Rf -i \''.$file_path.'\' && chown -Rf '.$uid.':'.$gid.' \''.$file_path.'\'');
		}
	}

	return -1;
}

sub get_chattr
{
	logger "CALLED chattr";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($file_path) = decrypt_params(@_);
	my $file = $file_path;
	$file_path =~ s/('+)/'\"$1\"'/g;
	return sudo_exec_without_decrypt('(lsattr \''.$file_path.'\' | sed -e "s#'.$file.'##g")|grep -o i');
}

sub mock_ftp_mgr
{
  logger "Mocked ftp_mgr";
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");

	return 0;
}

sub start_fastdl
{
	logger "CALLED start fastdl";
	
	if(-e Path::Class::File->new(FD_DIR, 'Settings.pm'))
	{
		system('perl FastDownload/ForkedDaemon.pm &');
		sleep(1);
		return 1;
	}
	else
	{
		return -2;
	}
}

sub stop_fastdl
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return stop_fastdl_without_decrypt();
}

sub stop_fastdl_without_decrypt
{
	logger "CALLED stop fastdl";
	
	my $pid;
	open(PIDFILE, '<', FD_PID_FILE)
	  || logger "Error reading pid file $!",1;
	while (<PIDFILE>)
	{
		$pid = $_;
		chomp $pid;
	}
	close(PIDFILE);
	my $cnt = kill 9, $pid;
	if ($cnt == 1)
	{
		logger "Fast Download Daemon Stopped.",1;
		return 1;
	}
	else
	{
		logger "Fast Download Daemon with pid $pid can not be stopped.",1;
		return -1;
	}
}

sub restart_fastdl
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return restart_fastdl_without_decrypt();
}

sub restart_fastdl_without_decrypt
{
	logger "CALLED restart fastdl";
	
	if((fastdl_status_without_decrypt() == -1) || (stop_fastdl_without_decrypt() == 1))
	{
		if(start_fastdl() == 1)
		{
			# Success
			return 1;
		}
		# Cant start
		return -2;
	}
	# Cant stop
	return -3;
}

sub fastdl_status
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	return fastdl_status_without_decrypt();
}

sub fastdl_status_without_decrypt
{
	logger "CALLED fastdl status";
	
	my $pid;
	if(!open(PIDFILE, '<', FD_PID_FILE))
	{
		logger "Error reading pid file $!";
		return -1;
	}
	while (<PIDFILE>)
	{
		$pid = $_;
		chomp $pid;
	}
	close(PIDFILE);
	my $cnt = kill 0, $pid;
	if ($cnt == 1)
	{
		return 1;
	}
	else
	{
		return -1;
	}
}

sub fastdl_get_aliases
{
	logger "CALLED fastdl get aliases";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my %aliases;
	my $i;
	my @file_lines;
	if(-d FD_ALIASES_DIR)
	{
		if( !opendir(ALIASES, FD_ALIASES_DIR) )
		{
			logger "Error openning aliases directory " . FD_ALIASES_DIR . ", $!";
		}
		else
		{
			while (my $alias = readdir(ALIASES))
			{
				# Skip . and ..
				next if $alias =~ /^\./;
				if( !open(ALIAS, '<', Path::Class::Dir->new(FD_ALIASES_DIR, $alias)) )
				{
					logger "Error reading alias '$alias', $!";
				}
				else
				{
					$i = 0;
					@file_lines = ();
					while (<ALIAS>)
					{
						chomp $_;
						$file_lines[$i] = $_;
						$i++;
					}
					close(ALIAS);
					$aliases{$alias}{home}                  = $file_lines[0];
					$aliases{$alias}{match_file_extension}  = $file_lines[1];
					$aliases{$alias}{match_client_ip}       = $file_lines[2];
				}
			}
			closedir(ALIASES);
		}
	}
	else
	{
		logger "Aliases directory '" . FD_ALIASES_DIR . "' does not exist or is inaccessible.";
	}
	return {%aliases};
}

sub fastdl_del_alias
{
	logger "CALLED fastdl del alias";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	foreach my $alias (decrypt_params(@_))
	{
		unlink Path::Class::File->new(FD_ALIASES_DIR, $alias);
	}
	return restart_fastdl_without_decrypt();
}

sub fastdl_add_alias
{
	logger "CALLED fastdl add alias";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($alias,$home,$match_file_extension,$match_client_ip) = decrypt_params(@_);
	if(!-e FD_ALIASES_DIR)
	{
		if(!mkdir FD_ALIASES_DIR)
		{
			logger "ERROR - Failed to create " . FD_ALIASES_DIR . " directory.";
			return -1;
		}
	}
	my $alias_path = Path::Class::File->new(FD_ALIASES_DIR, $alias);
	if (!open(ALIAS, '>', $alias_path))
	{
		logger "ERROR - Failed to open ".$alias_path." for writing.";
		return -1;
	}
	else
	{
		print ALIAS "$home\n";
		print ALIAS "$match_file_extension\n";
		print ALIAS "$match_client_ip";
		close(ALIAS);
		return restart_fastdl_without_decrypt();
	}
}

sub fastdl_get_info
{
	logger "CALLED fastdl get info";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	if(-e Path::Class::File->new(FD_DIR, 'Settings.pm'))
	{
		delete $INC{"FastDownload/Settings.pm"};
		require "FastDownload/Settings.pm"; # Settings for Fast Download Daemon.
		if(not defined $FastDownload::Settings{autostart_on_agent_startup})
		{
			$FastDownload::Settings{autostart_on_agent_startup} = 0;
		}
		return {'port'						=>	$FastDownload::Settings{port},
				'ip'						=>	$FastDownload::Settings{ip},
				'listing'					=>	$FastDownload::Settings{listing},
				'autostart_on_agent_startup'=>	$FastDownload::Settings{autostart_on_agent_startup}};
	}
	return -1
}

sub fastdl_create_config
{
	logger "CALLED fastdl create config";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	if(!-e FD_DIR)
	{
		if(!mkdir FD_DIR)
		{
			logger "ERROR - Failed to create " . FD_DIR . " directory.";
			return -1;
		}
	}
	my ($fd_address, $fd_port, $listing, $autostart_on_agent_startup) = decrypt_params(@_);
	my $settings_string = "%FastDownload::Settings = (\n".
						  "\tport  => $fd_port,\n".
						  "\tip => '$fd_address',\n".
						  "\tlisting => $listing,\n".
						  "\tautostart_on_agent_startup => $autostart_on_agent_startup,\n".
						  ");";
	my $settings = Path::Class::File->new(FD_DIR, 'Settings.pm');
	if (!open(SETTINGS, '>', $settings))
	{
		logger "ERROR - Failed to open $settings for writing.";
		return -1;
	}
	else
	{
		print SETTINGS $settings_string;
		close(SETTINGS);
	}
	logger "$settings file written successfully.";
	return 1;
}

sub agent_restart
{
	logger "CALLED agent restart";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my $dec_check = decrypt_param(@_);
	if ($dec_check eq 'restart')
	{
		chdir AGENT_RUN_DIR;
		if(-e "ogp_agent_run.pid")
		{
			my $init_pid	= `cat ogp_agent_run.pid`;
			chomp($init_pid);

			if(kill 0, $init_pid)
			{
				my $or_exist	= "";
				my $rm_pid_file	= "";
				if(-e "ogp_agent.pid")
				{
					$rm_pid_file	= " ogp_agent.pid";
					my $agent_pid	= `cat ogp_agent.pid`;
					chomp($agent_pid);
					if( kill 0, $agent_pid )
					{
						$or_exist = " -o -e /proc/$agent_pid";
					}
				}

				open (AGENT_RESTART_SCRIPT, '>', 'tmp_restart.sh');
				my $restart = "echo -n \"Stopping OGP Agent...\"\n".
							  "kill $init_pid\n".
							  "while [ -e /proc/$init_pid $or_exist ];do echo -n .;sleep 1;done\n".
							  "rm -f ogp_agent_run.pid $rm_pid_file\necho \" [OK]\"\n".
							  "echo -n \"Starting OGP Agent...\"\n".
							  "screen -d -m -t \"ogp_agent\" -c \"" . SCREENRC_FILE . "\" -S ogp_agent bash ogp_agent_run -pidfile ogp_agent_run.pid\n".
							  "while [ ! -e ogp_agent_run.pid -o ! -e ogp_agent.pid ];do echo -n .;sleep 1;done\n".
							  "echo \" [OK]\"\n".
							  "rm -f tmp_restart.sh\n".
							  "exit 0\n";
				print AGENT_RESTART_SCRIPT $restart;
				close (AGENT_RESTART_SCRIPT);
				if( -e 'tmp_restart.sh' )
				{
					system('screen -d -m -t "agent_restart" -c "' . SCREENRC_FILE . '" -S agent_restart bash tmp_restart.sh');
				}
			}
		}
	}
	return -1;
}

sub scheduler_add_task
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my $new_task = decrypt_param(@_);
	return 1;
}

sub scheduler_del_task
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my $name = decrypt_param(@_);
	return 1;
}

sub scheduler_edit_task
{
	return 1;
}

sub scheduler_list_tasks
{
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my %entries_array = ("Foo");
	return {%entries_array};
}

sub get_file_part
{
	logger "CALLED get file part";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($file, $offset) = decrypt_params(@_);
	if (!open(FILE, '<', $file))
	{
		logger "ERROR - Can't open file $file for reading.";
		return -1;
	}

	binmode(FILE);

	if($offset != 0)
	{
		return -1 unless seek FILE, $offset, 0;
	}

	my $data = "";
	my ($n, $buf);
	my $limit = $offset + 60 * 57 * 1000; #Max 3420Kb (1000 iterations) (top statistics ~ VIRT 116m, RES 47m)
	while (($n = read FILE, $buf, 60 * 57) != 0 && $offset <= $limit ) {
		$data .= $buf;
		$offset += $n;
	}
	close(FILE);

    if( $data ne "" )
	{
		my $b64zlib = encode_base64(compress($data,9));
		return "$offset;$b64zlib";
	}
	else
	{
		return -1;
	}
}

sub stop_update
{
	logger "CALLED stop update";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my $home_id = decrypt_param(@_);
	my $screen_id = create_screen_id(SCREEN_TYPE_UPDATE, $home_id);
	system('screen -S '.$screen_id.' -p 0 -X stuff $\'\003\'');
	if ($? == 0)
	{
		return 0;
	}
	return 1
}

sub shell_action
{
	logger "CALLED shell action";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($action, $arguments) = decrypt_params(@_);

	if($action eq 'remove_file')
	{
		chomp($arguments);
		unlink($arguments);
		return "1;";
	}
	elsif($action eq 'remove_recursive')
	{
		my @items = split(';', $arguments);
		foreach my $item ( @items ) {
			chomp($item);
			if(-d $item)
			{
				pathrmdir($item);
			}
			else
			{
				unlink($item);
			}
		}
		return "1;";
	}
	elsif($action eq 'create_dir')
	{
		chomp($arguments);
		mkpath($arguments);
		return "1;";
	}
	elsif($action eq 'move')
	{
		my($src, $dest) = split(';', $arguments);
		chomp($src);
		chomp($dest);
		if(-d $src)
		{
			$dest = Path::Class::Dir->new($dest, basename($src));
			dirmove($src, $dest);
		}
		else
		{
			fmove($src, $dest);
		}
		return "1;";
	}
	elsif($action eq 'copy')
	{
		my($src, $dest) = split(';', $arguments);
		chomp($src);
		chomp($dest);
		if(-d $src)
		{
			$dest = Path::Class::Dir->new($dest, basename($src));
			dircopy($src, $dest);
		}
		else
		{
			fcopy($src, $dest);
		}
		return "1;";
	}
	elsif($action eq 'touch')
	{
		chomp($arguments);
		open(FH, '>', $arguments);
		print FH "";
		close(FH);
		return "1;";
	}
	elsif($action eq 'size')
	{
		chomp($arguments);
		my $size = 0;
		if(-d $arguments)
		{
			find(sub { $size += -s }, $arguments ? $arguments : '.');
		}
		else
		{
			$size += (stat($arguments))[7];
		}
		return "1;" . encode_list($size);
	}
	elsif($action eq 'get_cpu_usage')
	{
		my %prev_idle;
		my %prev_total;
		open(STAT, '/proc/stat');
		while (<STAT>) {
			next unless /^cpu([0-9]+)/;
			my @stat = split /\s+/, $_;
			$prev_idle{$1} = $stat[4];
			$prev_total{$1} = $stat[1] + $stat[2] + $stat[3] + $stat[4];
		}
		close STAT;
		sleep 1;
		my %idle;
		my %total;
		open(STAT, '/proc/stat');
		while (<STAT>) {
			next unless /^cpu([0-9]+)/;
			my @stat = split /\s+/, $_;
			$idle{$1} = $stat[4];
			$total{$1} = $stat[1] + $stat[2] + $stat[3] + $stat[4];
		}
		close STAT;
		my %cpu_percent_usage;
		foreach my $key ( keys %idle )
		{
			my $diff_idle = $idle{$key} - $prev_idle{$key};
			my $diff_total = $total{$key} - $prev_total{$key};
			my $percent = (100 * ($diff_total - $diff_idle)) / $diff_total;
			$percent = sprintf "%.2f", $percent unless $percent == 0;
			$cpu_percent_usage{$key} = encode_base64($percent);
		}
		return {%cpu_percent_usage};
	}
	elsif($action eq 'get_ram_usage')
	{
		my($total, $buffers, $cached, $free) = qw(0 0 0 0);
		open(STAT, '/proc/meminfo');
		while (<STAT>) {
			$total   += $1 if /MemTotal\:\s+(\d+) kB/;
			$buffers += $1 if /Buffers\:\s+(\d+) kB/;
			$cached  += $1 if /Cached\:\s+(\d+) kB/;
			$free    += $1 if /MemFree\:\s+(\d+) kB/;
		}
		close STAT;
		my $used = $total - $free - $cached - $buffers;
		my $percent = 100 * $used / $total;
		my %mem_usage;
		$mem_usage{'used'}    = encode_base64($used * 1024);
		$mem_usage{'total'}   = encode_base64($total * 1024);
		$mem_usage{'percent'} = encode_base64($percent);
		return {%mem_usage};
	}
	elsif($action eq 'get_disk_usage')
	{
		my($total, $used, $free) = split(' ', `df -lP 2>/dev/null|grep "^/dev/.*"|awk '{total+=\$2}{used+=\$3}{free+=\$4} END {print total, used, free}'`);
		my $percent = 100 * $used / $total;
		my %disk_usage;
		$disk_usage{'free'}    = encode_base64($free * 1024);
		$disk_usage{'used'}    = encode_base64($used * 1024);
		$disk_usage{'total'}   = encode_base64($total * 1024);
		$disk_usage{'percent'} = encode_base64($percent);
		return {%disk_usage};
	}
	elsif($action eq 'get_uptime')
	{
		open(STAT, '/proc/uptime');
		my $uptime = 0;
		while (<STAT>) {
			$uptime += $1 if /^([0-9]+)/;
		}
		close STAT;
		my %upsince;
		$upsince{'0'} = encode_base64($uptime);
		$upsince{'1'} = encode_base64(time - $uptime);
		return {%upsince};
	}
	elsif($action eq 'get_tasklist')
	{
		my %taskList;
		$taskList{'task'} = encode_base64(`top -b -c -i -w512 -n2 | awk '/^top/{i++}i==2' | grep "COMMAND" -A 30`);
		return {%taskList};
	}
	elsif($action eq 'get_timestamp')
	{
		return "1;" . encode_list(time);
	}
	return 0;
}

sub remote_query
{
	logger "CALLED remote query";
	
	return "Bad Encryption Key" unless(decrypt_param(pop(@_)) eq "Encryption checking OK");
	my ($protocol, $game_type, $ip, $c_port, $q_port, $s_port) = decrypt_params(@_);
	my $command = "which php-cgi 2>&1;echo \$?";
	my @cmdret = qx($command);
	chomp(@cmdret);
	my $ret = pop(@cmdret);
	chomp($ret);
	if ("X$ret" ne "X0")
	{
		return -1;
	}
	my $PHP_CGI = "@cmdret";
	my $php_query_dir = Path::Class::Dir->new(AGENT_RUN_DIR, 'php-query');
	if($protocol eq 'lgsl')
	{
		chdir($php_query_dir->subdir('lgsl'));
		my $cmd = $PHP_CGI .
				" -f lgsl_feed.php" .
				" lgsl_type=" . $game_type .
				" ip=" . $ip .
				" c_port=" . $c_port .
				" q_port=" . $q_port .
				" s_port=" . $s_port .
				" request=sp";
		my $response = `$cmd`;
		chomp($response);
		chdir(AGENT_RUN_DIR);
		if($response eq "FAILURE")
		{
			return -1;
		}
		return encode_base64($response, "");
	}
	elsif($protocol eq 'gameq')
	{
		chdir($php_query_dir->subdir('gameq'));
		my $cmd = $PHP_CGI .
				" -f gameq_feed.php" .
				" game_type=" . $game_type .
				" ip=" . $ip .
				" c_port=" . $c_port .
				" q_port=" . $q_port .
				" s_port=" . $s_port;
		my $response = `$cmd`;
		chomp($response);
		chdir(AGENT_RUN_DIR);
		if($response eq "FAILURE")
		{
			return -1;
		}
		return encode_base64($response, "");
	}
	return -1;
}
