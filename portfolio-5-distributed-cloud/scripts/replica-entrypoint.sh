#!/bin/bash
# Entrypoint for the hot-standby replica.
# First start: clone the primary with pg_basebackup.
#   --write-recovery-conf  creates standby.signal and stores primary_conninfo,
#                          so the server starts in recovery (read-only) mode
#   --slot=replica1_slot   streams through the slot created on the primary
# Every start: run postgres as a hot standby (it accepts read-only queries).
set -euo pipefail
PGDATA="${PGDATA:-/var/lib/postgresql/data}"

# Password file for the replication connection (used by pg_basebackup and the WAL receiver).
PGPASSFILE_PATH=/var/lib/postgresql/.pgpass
echo "pg-primary:5432:*:replicator:${REPLICATION_PASSWORD}" > "$PGPASSFILE_PATH"
chown postgres:postgres "$PGPASSFILE_PATH"
chmod 600 "$PGPASSFILE_PATH"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "[replica] waiting for the primary to accept TCP connections..."
    until pg_isready -h pg-primary -p 5432 -q; do sleep 1; done

    echo "[replica] taking base backup from pg-primary"
    mkdir -p "$PGDATA"
    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
    gosu postgres pg_basebackup -h pg-primary -p 5432 -U replicator -D "$PGDATA" \
            --wal-method=stream --write-recovery-conf --slot=replica1_slot \
            --checkpoint=fast --progress --verbose
    echo "[replica] base backup complete"
fi

exec gosu postgres postgres -D "$PGDATA" \
    -c hot_standby=on \
    -c cluster_name=replica1 \
    -c hba_file=/etc/postgresql/pg_hba.conf
