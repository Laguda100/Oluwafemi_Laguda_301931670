-- Replication status as seen from the REPLICA (hot standby).
\pset footer off
SELECT pg_is_in_recovery() AS is_standby;
\x on
SELECT status, sender_host, sender_port, slot_name,
       written_lsn, flushed_lsn, latest_end_lsn, last_msg_receipt_time
FROM pg_stat_wal_receiver;
\x off
SELECT pg_last_wal_replay_lsn()                  AS replayed_lsn,
       now() - pg_last_xact_replay_timestamp()   AS time_since_last_replayed_commit;
