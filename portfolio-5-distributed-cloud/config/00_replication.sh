#!/bin/bash
# Runs once, when the primary's data directory is first initialised.
# Creates the replication role and a physical replication slot. The slot
# makes the primary keep WAL until the replica has received it, so a
# replica that is briefly offline can always catch up.
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';
    SELECT pg_create_physical_replication_slot('replica1_slot');
EOSQL
echo "[primary] replication role and slot created"
