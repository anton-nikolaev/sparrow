#!/bin/sh
# Last modified: 04/05/2009

WWW_ROOT="/usr/local/www/sparrow-data"
TMPL_DIR="/usr/local/www/sparrow-tmpl"
CGI_DIR="/usr/local/www/sparrow-cgi"
SPRW_ARC_DIR="/usr/local/www/sparrow-archive"
SPARROW_CONF="/var/db/sparrow"
SQUID_LOGS_DIR="/usr/local/squid/logs"
LOCAL_SBIN="/usr/local/sbin"
SQUID_SUDO="/usr/local/bin/sudo -u squid"
SQUID_OWNER="squid:squid"
CP="/bin/cp -i"
DIFF="/usr/bin/diff -q"

case "$1" in 
	'diffcheck')
		
		for i in *.pl ; do 
			$DIFF $i $LOCAL_SBIN/$i
		done
		
		# ./www 
		cd www
		$DIFF index.html $WWW_ROOT/index.html
		$DIFF doc.html $WWW_ROOT/doc.html
	
		# ./www/cgi 
		cd cgi 
		for i in *.cgi ; do
			$DIFF $i $CGI_DIR/$i
		done
		
		# ./www/tmpl
		cd ../tmpl
		for i in *.html ; do 
			$DIFF $i $TMPL_DIR/$i
		done
		
		# ./www/src
		cd ../src
		for i in * ; do
			$DIFF $i $WWW_ROOT/src/$i
		done

		exit
		;;

#	'deinstall')
#		echo "Sparrow files are about to be REMOVED from your system!"
#		echo "Consider running init.sh diffcheck, if you didnt do that."
#		for i in *.pl ; do 
			
	'') ;;
	*)
		echo Unknown flag $1
		exit
		;;
esac
		
# Проверяем очень старые версии
#if [ -e /usr/local/sbin/logAgent.pl ]; then
#	/usr/local/sbin/logAgent.pl -V
#	echo Very old sparrow. You have to upgrade manually.
#	exit
#fi

# Создаем и заполняем БД
if /usr/local/bin/createuser -A -D -e -U pgsql sparrow ; then
	if /usr/local/bin/createdb -e -E KOI8 -O sparrow -U pgsql sparrowdb ; then
		if /usr/local/bin/createlang -e -U pgsql plpgsql sparrowdb ; then
			/usr/local/bin/psql -f ./sparrowdb.sql sparrowdb sparrow
		fi
	fi
else
	echo Sparrow database seems to be already configured. Please, follow this instruction, if sparrow doesnt work after upgrade:
	echo 1. Run \"pg_dump -a -d -t clients -t users -t statis_summary -U sparrow sparrowdb \> ./cur_dump.sql\" to export data 
	echo 2. Remove database \"dropdb -U pgsql sparrowdb\"
	echo 3. Run init.sh again, complete sparrow installation
	echo 4. Import users back with psql -f
fi

if [ -x /usr/bin/perl ]; then
	PERL_LIB_DIR=`/usr/bin/perl -e 'print $INC[-2];'`
	if [ -r $PERL_LIB_DIR/DaemonLib.pm ] ; then
		# библиотека уже установлена
		if $DIFF ./DaemonLib.pm $PERL_LIB_DIR/DaemonLib.pm > /dev/null ; then
			echo $PERL_LIB_DIR/DaemonLib.pm is up to date - skipped
		else
			/bin/cat ./DaemonLib.pm > $PERL_LIB_DIR/DaemonLib.pm
		fi
	else
		if $CP ./DaemonLib.pm $PERL_LIB_DIR/; then
			/bin/chmod 0444 $PERL_LIB_DIR/DaemonLib.pm
		else
			echo ERROR! Cant copy DaemonLib.pm to $PERL_LIB_DIR 
			exit
		fi
	fi
else
	echo ERROR! Perl not found by /usr/bin/perl
	exit
fi


# Устанавливаем исполнимые файлы
for i in authenticator.pl squidAgent.pl periodic.pl ext_acl.pl config_cli.pl ; 
do
	if [ -r $LOCAL_SBIN/$i ] ; then
		# файл уже есть в системе, проверяем версию
		if [ `./$i -V 2>&1` -eq `$LOCAL_SBIN/$i -V 2>&1` ] ; then
			# версии совпадают
			echo $LOCAL_SBIN/$i is up to date - skipped
		else
			if [ `./$i -V 2>&1` -lt `$LOCAL_SBIN/$i -V 2>&1` ] ; then
				# файл в системе более новый, чем собираемся ставить
				echo $LOCAL_SBIN/$i is newer, than one we installing now!
				echo Installation stopped.
				exit
			else
				/bin/cat ./$i > $LOCAL_SBIN/$i
			fi
		fi
	else
		if $CP ./$i $LOCAL_SBIN/$i ; then
			/bin/chmod 0555 $LOCAL_SBIN/$i ;
		fi
	fi
done

# Готовим директорию под конфигурацию
if [ -d $SPARROW_CONF ]; then
	echo Configuration exists at $SPARROW_CONF - will be updated
else
	/bin/mkdir $SPARROW_CONF
	/usr/sbin/chown $SQUID_OWNER $SPARROW_CONF
	/bin/chmod 0770 $SPARROW_CONF
	echo Configuration installed to $SPARROW_CONF
fi

# заполняем конфигурацию начальными значениями в режиме обновления
$SQUID_SUDO ./config_cli.pl debug 0 upgrade
$SQUID_SUDO ./config_cli.pl logfile $SQUID_LOGS_DIR/sparrow.log upgrade
$SQUID_SUDO ./config_cli.pl dbname sparrowdb upgrade
$SQUID_SUDO ./config_cli.pl dbhost localhost upgrade
$SQUID_SUDO ./config_cli.pl dbuser sparrow upgrade
$SQUID_SUDO ./config_cli.pl dbpassword secret upgrade
$SQUID_SUDO ./config_cli.pl squid_access_log $SQUID_LOGS_DIR/access.log upgrade
$SQUID_SUDO ./config_cli.pl squid_bin $LOCAL_SBIN/squid upgrade
$SQUID_SUDO ./config_cli.pl squid_log_agent_pidfile $SQUID_LOGS_DIR/log_agent.pid upgrade
$SQUID_SUDO ./config_cli.pl squid_log_agent_lastrun 1 upgrade
$SQUID_SUDO ./config_cli.pl periodic_pidfile $SQUID_LOGS_DIR/periodic.pid upgrade
$SQUID_SUDO ./config_cli.pl count_cached_requests 0 upgrade
$SQUID_SUDO ./config_cli.pl statis_timepoint 1 upgrade
$SQUID_SUDO ./config_cli.pl tmpl_dir $TMPL_DIR upgrade
$SQUID_SUDO ./config_cli.pl cur_period_start_timepoint 1 upgrade
$SQUID_SUDO ./config_cli.pl null_passwords_allowed 1 upgrade
$SQUID_SUDO ./config_cli.pl max_period_size 0 upgrade
$SQUID_SUDO ./config_cli.pl def_user_access 0 upgrade
$SQUID_SUDO ./config_cli.pl def_ip_access 0 upgrade
$SQUID_SUDO ./config_cli.pl archive_basedir $SPRW_ARC_DIR upgrade
$SQUID_SUDO ./config_cli.pl client_ip_acl 0 upgrade
$SQUID_SUDO ./config_cli.pl database_version 20090504 upgrade

# создаем директорию для архивов статистики
if /bin/mkdir $SPRW_ARC_DIR ; then
	/usr/sbin/chown $SQUID_OWNER $SPRW_ARC_DIR
	/bin/chmod 0770 $SPRW_ARC_DIR
fi

# копируем html-шаблоны
/bin/mkdir $TMPL_DIR 
$CP ./www/tmpl/* $TMPL_DIR

# копируем статические web-файлы
/bin/mkdir $WWW_ROOT
$CP ./www/index.html $WWW_ROOT/
$CP ./www/doc.html $WWW_ROOT/
/bin/mkdir $WWW_ROOT/src
$CP ./www/src/* $WWW_ROOT/src/

# картинки
/bin/mkdir $WWW_ROOT/img
$CP ./www/img/* $WWW_ROOT/img/

# cgi-скрипты
/bin/mkdir $CGI_DIR
$CP ./www/cgi/* $CGI_DIR/
