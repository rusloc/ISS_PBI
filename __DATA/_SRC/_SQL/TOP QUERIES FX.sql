

-- queries overview
	

	select
	     a.pid                                                     _pid
	    ,a.usename                                                 _user
	    ,a.datname                                                 _db
	    ,a.application_name                                        _app
	    ,a.client_addr                                             _client
	    ,a.state                                                   _state
	    ,now() - a.query_start                                     _running_for
	    ,now() - a.xact_start                                      _tx_open_for
	    ,a.wait_event_type || ':' || a.wait_event                  _wait
	    ,cardinality(pg_blocking_pids(a.pid))                      _blocked_by_n
	    ,(select count(*) from pg_stat_activity w
	      where a.pid = any(pg_blocking_pids(w.pid)))              _is_blocking_n
	    ,left(regexp_replace(a.query, '\s+', ' ', 'g'), 100)       _query_preview
	from pg_stat_activity a
	where 1=1
	--    and a.backend_type = 'client backend'
	    and a.pid <> pg_backend_pid()
	    and a.state <> 'idle'
	order by _is_blocking_n desc, _running_for desc
	
	
	
	
-- get full SQL query text
		
	
	select
	     a.pid              _pid
	    ,a.usename          _user
	    ,a.state            _state
	    ,now() - a.query_start _running_for
	    ,a.query            _sql
	from pg_stat_activity a
	where 1=1
	    and a.pid in (12345, 12346)      -- <-- paste pids from step 1
	order by a.query_start
	
	
	
	
	
	-- cancel the statement, keep the connection
	
select
     a.pid                    _pid
    ,pg_cancel_backend(a.pid) _cancelled
from pg_stat_activity a
where 1=1
    and a.pid in (12345, 12346);     -- pids

    
    
    
    
-- hard: drop the session (use for idle in transaction, or if cancel didn't work)
select
     a.pid                       _pid
    ,pg_terminate_backend(a.pid) _terminated
from pg_stat_activity a
where 1=1
    and a.pid in (12345, 12346)
    
    
    
    
    
    