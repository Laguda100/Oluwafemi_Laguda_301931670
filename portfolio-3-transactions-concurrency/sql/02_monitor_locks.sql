-- =====================================================================
-- Portfolio 3 - lock monitoring (run in a THIRD terminal while a demo
-- is in progress, e.g. while session B is waiting).
-- Shows who is waiting, on which lock, and which session blocks them.
-- =====================================================================
\pset footer off

SELECT a.pid,
       a.state,
       a.wait_event_type,
       a.wait_event,
       pg_blocking_pids(a.pid)   AS blocked_by,
       now() - a.xact_start      AS in_transaction_for,
       left(a.query, 70)         AS current_query
FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND a.pid <> pg_backend_pid()
ORDER BY a.pid;

SELECT l.pid,
       l.locktype,
       l.relation::regclass AS relation,
       l.mode,
       l.granted
FROM pg_locks l
WHERE l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND l.pid <> pg_backend_pid()
  AND l.locktype IN ('relation', 'tuple', 'transactionid')
ORDER BY l.pid, l.granted DESC;
