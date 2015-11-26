# sparrow
Proxy internet traffic accounting

Last update: 22/04/2009


INSTALL
=======

Для работы понадобятся следующие перловые модули (в скобках указан путь относительно /usr/ports):
* DBI (databases/p5-DBI)
* DBD::Pg (databases/p5-DBD-Pg)
* Crypt::PasswdMD5 (security/p5-Crypt-PasswdMD5)
* CGI::Simple (www/p5-CGI-Simple)
* CGI::Session (www/p5-CGI-Session)
* HTML::Template (www/p5-HTML-Template)
* SQLayer (http://search.cpan.org/CPAN/authors/id/S/ST/STELLAR/SQLayer-1.1.tar.gz) 

Также должны быть установлены и запущены следующие приложения:
* squid (желательно не менять никаких переменных)
* postgresql
* apache (я всегда стараюсь использовать версию 1.x)

Если у Вас:
* freebsd 5.x или выше
* поставлены вышеперечисленные приложения из портов и с параметрами по умолчанию
то смело запускайте этот скрипт:
```
  $ ./init.sh
```

Если одно из условий у Вас не выполняются, то придется ставить все
вручную. Для этого просто откройте скрипт редактором и подправьте его так, как Вам это 
нужно. Буду рад всем, кто вознамерится поставить
sparrow на UNIX-систему не freebsd - обязательно пишите в гостевуху на airay.narod.ru 
или по почте airay at narod.ru, я с удовольствием помогу. Потроха системы я постарался
описать ниже в секции DETAILS.

Этот скрипт копирует все файлы туда, где им место. Конечно-же файлы конфигурации сервисов
apache и squid придется править вручную, о чем речь идет ниже. 

Также, скрипт не берется редактировать /etc/crontab, поэтому сделаем это вручную:
```
*   *   *   *   *   squid   /usr/local/sbin/squidAgent.pl >/usr/local/squid/logs/squidAgent.mesg 2>&1
21  3   *   *   *   squid   /usr/local/sbin/periodic.pl >/usr/local/squid/logs/periodic.mesg 2>&1
```

SQUID
-----

Здесь мы редактируем squid.conf.

Если раздаем доступ по логину и паролю:
```
  external_acl_type sprwLogin ttl=10 children=3 %LOGIN /usr/local/sbin/ext_acl.pl user_access
  auth_param basic program /usr/local/sbin/authenticator.pl
  acl via_password proxy_auth REQUIRED
  acl office src 192.168.0.0/255.255.0.0
  acl login_allowed_by_sparrow external sprwLogin
  http_access allow office via_password login_allowed_by_sparrow
```

Если раздаем доступ по IP:
```
  external_acl_type sprwIp ttl=10 children=3 %SRC /usr/local/sbin/ext_acl.pl ip_access
  acl office src 192.168.0.0/255.255.0.0
  acl ip_allowed_by_sparrow external sprwIp
  http_access allow office ip_allowed_by_sparrow
```

Итак, если у вас смешанный тип доступа, то весь этот компот может выглядеть так:
```
  external_acl_type sprwLogin ttl=10 children=3 %LOGIN /usr/local/sbin/ext_acl.pl user_access
  external_acl_type sprwIp ttl=10 children=3 %SRC /usr/local/sbin/ext_acl.pl ip_access
  auth_param basic program /usr/local/sbin/authenticator.pl
  acl via_password proxy_auth REQUIRED
  acl secured_computers src 192.168.1.0/255.255.255.0
  acl public_computers src 192.168.2.0/255.255.255.0
  acl login_allowed_by_sparrow external sprwLogin
  acl ip_allowed_by_sparrow external sprwIp
  http_access allow public_computers via_password login_allowed_by_sparrow
  http_access allow secured_computers ip_allowed_by_sparrow
```

Установите глубину ротации журналов, какая Вас устроит. Webgui не обращает на журналы никакого
внимания. Меня устраивает глубина хранения - 12 месяцев:
```
  logfile_rotate 12
```
Эта опция не соответсвует напрямую числу месяцев! Глубина во времени полностью зависит от периодичности
сброса счетчиков трафика, что конфигурируется через web-gui или config_cli.pl. Я обычно оставляю
сброс по умолчанию - раз в месяц, и поэтому ротация логов так ровно ложится. Но Вы можете захотеть
сбрасывать счетчики каждый день, и тогда logfile_rotate 12 сделает Вам глубину по времени в 12 дней.

Чтобы squid при выключении "умирал" быстрее (а не 30 секунд, как установлено по-умолчанию), пропишем:
```
  shutdown_lifetime 10 seconds
```

WEB-GUI
-------

Web-GUI состоит из нескольких cgi скриптов, некоторых украшений в виде GIF-картинок + css и 
основные шаблоны HTML. Скрипт init.sh уже все скопировал куда надо.

Процессы cgi должны запускаться с правами на запись в /var/db/sparrow, поэтому лучше
поменять владельца процесса apache: 
```
User squid
Group squid
```
Если этого в глобальной части httpd.conf делать нельзя, то следует пересобрать Apache с suexec,
и сделать это в соответствующем VirtualHost.

Также разрешите CGI-сценариям запускаться:
```
AddHandler cgi-script .cgi
```

Создадим виртуальный хост (сюда нужно добавить User & Group, если собрали с suexec):

```
<VirtualHost *.*>
    ServerAdmin mail@kreveding.ru
    ServerName proxy.kreveding.ru
    ErrorLog /var/log/sparrow-error.log
    CustomLog /var/log/sparrow-access.log common

    DocumentRoot /usr/local/www/sparrow-data
    <Directory /usr/local/www/sparrow-data>
        Order allow,deny
        Allow from all
    </Directory>

    ScriptAlias /cgi/ /usr/local/www/sparrow-cgi/
    <Directory /usr/local/www/sparrow-cgi>
        Options ExecCGI
    </Directory>
</VirtualHost>
```

FINAL
-----

Если Вы все сделали правильно, то остается всего лишь перезагрузить машину (или перезапустить squid и apache 
вручную). Для того, чтобы избежать проблемы "мертвого" squid во время загрузки сервера, необходимо определить 
порядок запуска относительно базы данных: поставьте приоритет запуска pgsql повыше.
```
  $ mv /usr/local/etc/rc.d/postgresql /usr/local/etc/rc.d/010.postgresql
```

Пароль на админа (логин admin) по умолчанию пустой, однако в любом случае можно обнулить
пароль такой командой:
```
  $ psql -c 'update clients set password = NULL where id = \'admin\'' sparrowdb sparrow
```

Также не забудьте прикрутить ротацию логов к сервисам. Например, в /etc/newsyslog.conf:
```
/usr/local/squid/logs/sparrow.log squid:squid 644 7 2000 * JN
/var/log/httpd-error.log 644 7 500 * J /var/run/httpd.pid
/var/log/httpd-access.log 644 7 500 * J /var/run/httpd.pid
```

DETAILS
-------

Здесь подробно описан принцип работы системы, а также некоторые часто встречающиеся трудности.
Также, здесь описаны подробности конфигурирования, которые пригодятся, если init.sh по каким-либо
причинам Вам не подошел (отработал с ошибками).

Внешний acl перестает работать (отвечает "ERR" на все), если squidAgent не запускался в 
течение 5ти минут. Все скрипты (кроме config_cli.pl) откажутся запускаться с правами root (uid = 0).

Конфигурация системы хранится в директории /var/db/sparrow в базе данных типа BerkleyDB. 
Управлять ею можно с помощью скрипта config_cli.pl. Например, чтобы включить отладку:
```
  $ config_cli.pl debug 1
```

На данный момент у меня нет прецедентов использования БД этой программы на другой машине, 
поэтому директивы db* содержат пустой пароль, а скрипты не содержат hostname в коде 
подключения к БД. В этом нет никакой опасности, даже если PostgreSQL разрешает подключения по 
tcp/ip, ибо pg_hba.conf различает доступ по сети и локально. Однако, если Ваши рядовые пользователи
имеют консольный (терминальный) доступ к серверу - придется запаролиться и подредактировать
pg_hba.conf.
```
  $ ./config_cli.pl dbpassword some_secret
```

Директива count_cached_requests указывает squid агенту учитывать (или не учитывать)
сэкономленные из кэша запросы. Установите 1, если хотите сэкономить конторские деньги на 
трафике :). Хотя конечно экономия там не ахти, поэтому лучше оставить как есть. Эту опцию
можно "крутить" через webgui.

Директива squid_bin должна содержать путь к исполнимому файлу прокси сервера. Она нужна
чтобы periodic скрипт мог делать squid -k rotate. Узнать путь можно командой whereis squid. 
Если squid был установлен из портов freebsd, то ничего там редактировать скорее всего не надо. 

Если приходится срочно грохнуть Базу-Данных (например, пришли судебные приставы :), то сделать это
можно так:
```
  $ dropdb -U pgsql sparrowdb
  $ dropuser -U pgsql sparrow
```

UPGRADE
-------

Если вы обновляетесь с версии 20060822, то сносите все и ставьте заново, забэкапив 
предварительно таблицу с пользователями. Это связано с тем, что формат значительно поменялся.
```
  $ pg_dump -a -d -t users -U sparrow sparrowdb
```

Полученный на стандартном выводе дамп сохраните куда нибудь в текстовый файлик, чтобы потом
не маеться с добавлением пользователей.
```
  $ dropdb -U pgsql sparrowdb
  $ dropuser -U pgsql sparrow
  $ /usr/local/etc/rc.d/020.sprw-logAgent.sh stop
  $ rm /usr/local/etc/rc.d/020.sprw-logAgent.sh
```

А дальше порядок такой же, как и в установке с нуля.

Если обновление происходит с версии повыше, то можно пробовать обновляться скриптом init.sh.

