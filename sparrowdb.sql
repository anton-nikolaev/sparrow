-- Sparrow database structure
-- Last updated 04.05.2009

-- id: workstation IP address or user login
-- descr: workstation description or user fullname
-- is_workstation: true/false - id = IP or id = login
-- is_admin: true/false - cgi-scripts trust it
-- password: encrypted hash
-- bytelimit: cache_access switches to false, when bytecounter reached this value.
-- bytecounter: every positive request increases this value with actual bytes received.
-- cache_access: true/false - external_acl uses this field to pass or deny access.
-- ignorelimit: true/false - cache_access always on

create table clients
(
        id		text PRIMARY KEY,
        descr		text,
	is_workstation	boolean DEFAULT false,
	is_admin	boolean DEFAULT false,
        password        text,
	bytelimit       bigint NOT NULL,
	bytecounter     bigint DEFAULT 0,
        cache_access    boolean DEFAULT false,
	ignorelimit	boolean DEFAULT false
);

insert into clients (id, descr, is_admin, password, bytelimit, ignorelimit)
	values ('admin', 'Local administrator', true, NULL, 
	1, true);

-- only to display current stats
create table statis_summary
(
	id		text REFERENCES clients (id) ON DELETE CASCADE,
	site		text NOT NULL,
	bytecounter	bigint NOT NULL DEFAULT 0,
	stat_day	date NOT NULL DEFAULT 'today'
);

-- limits client's access by src-ip
create table client_ip_acl
(
	id			serial PRIMARY KEY,
	client_id	text	REFERENCES clients (id) ON DELETE CASCADE,
	ip_addr		cidr 	NOT NULL
);

-----------------------------
-- file extension blocker ---
create table file_categories
(
	id 			serial	PRIMARY KEY,
	descr		text	UNIQUE NOT NULL
);

create table file_extensions
(
	file_ext	text	PRIMARY KEY,
	category	int		REFERENCES file_categories (id)
);

create table file_ext_acl
(
	client_id	text	REFERENCES clients (id),
	file_cat	int		REFERENCES file_categories (id)
);
-- file extension blocker ---
-----------------------------

-- After update bytecounters:
-- switch cache_access to false, if bytecounter is greater than bytelimit.
-- switch cache_access to true, if bytecounter is smaller than bytelimit.
-- In case of ignorelimit is true - do not switch access to false.

create function control_access() RETURNS TRIGGER AS '
DECLARE
	usr	RECORD;		
BEGIN
	SELECT bytecounter, bytelimit, cache_access, ignorelimit
		INTO usr 
		FROM clients
		WHERE id = NEW.id;
	IF usr.cache_access = true AND usr.bytecounter > usr.bytelimit AND usr.ignorelimit = false THEN
		UPDATE clients
			SET cache_access = false
			WHERE id = NEW.id;
	ELSIF ( usr.cache_access = false AND usr.bytecounter < usr.bytelimit ) 
			OR ( usr.ignorelimit = true AND usr.cache_access = false ) THEN
		UPDATE clients
			SET cache_access = true
			WHERE id = NEW.id;
	END IF;		
	RETURN NEW;
END;
' LANGUAGE plpgsql;

create trigger control_client_access after insert or update on clients
	for each row execute procedure control_access(); 
