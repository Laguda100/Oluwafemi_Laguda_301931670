-- Replication status as seen from the PRIMARY.
\pset footer off
\x on
SELECT application_name, client_addr, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       write_lag, flush_lag, replay_lag
FROM pg_stat_replication;
\x off
SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;
SELECT pg_is_in_recovery() AS is_standby, pg_current_wal_lsn() AS current_wal_lsn,
       current_setting('synchronous_standby_names') AS synchronous_standby_names;
