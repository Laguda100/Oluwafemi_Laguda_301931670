# Portfolio 5: distributed database exercise (replication, partitioning, CAP, failover).
# Usage (from the repository root):  .\portfolio-5-distributed-cloud\run.ps1
#
# WARNING: deletes and recreates the cluster volumes on every run, so each run
# starts from the same state. (The main development database on port 5432 is untouched.)
#
#  1. Start a fresh primary + replica, wait for streaming replication
#  2. Replication status on both nodes
#  3. Write on primary -> read on replica (and how fast it appears)
#  4. Writes on the replica are rejected (hot standby is read-only)
#  5. Range + hash partitioning on the primary, verified on the replica
#  6. CAP trade-off: synchronous vs asynchronous commit with the replica down
#  7. Failover: stop the primary, promote the replica, keep writing
# Results: portfolio-5-distributed-cloud\results\

$ErrorActionPreference = 'Stop'
$root        = Split-Path -Parent $MyInvocation.MyCommand.Path
$results     = Join-Path $root 'results'
$composeFile = Join-Path $root 'docker-compose.replication.yml'
$P = 'crestfield-pg-primary'
$R = 'crestfield-pg-replica'
New-Item -ItemType Directory -Force $results | Out-Null
$report = Join-Path $results 'replication_report.txt'
Set-Content -Encoding UTF8 $report "Portfolio 5 replication report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

function Write-Section([string]$title, $lines) {
    Write-Host "`n== $title ==" -ForegroundColor Cyan
    $lines | ForEach-Object { Write-Host "   $_" }
    Add-Content -Encoding UTF8 $report @('', "===== $title =====")
    Add-Content -Encoding UTF8 $report $lines
}

# Pipes SQL text into psql inside a container and returns every output line (stdout + stderr).
function Invoke-Sql([string]$container, [string]$sql, [switch]$Scalar) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $flags = @('-X', '-U', 'portal_admin', '-d', 'result_portal')
    if ($Scalar) { $flags += '-At' }
    $out = $sql | docker exec -i $container psql @flags 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = $prev
    return $out
}
function Invoke-SqlFile([string]$container, [string]$file) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = docker exec $container psql -X -U portal_admin -d result_portal -f $file 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = $prev
    return $out
}
function Wait-Ready([string]$container, [int]$timeoutSec = 180) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        cmd /c "docker exec $container pg_isready -h 127.0.0.1 -q > NUL 2>&1"
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 2
    }
    throw "$container was not ready after $timeoutSec s (check: docker logs $container)"
}

# ---------------------------------------------------------------------
Write-Host '== 1. Starting a fresh primary + replica cluster ==' -ForegroundColor Cyan
cmd /c "docker compose -f `"$composeFile`" down -v 2>&1"
cmd /c "docker compose -f `"$composeFile`" up -d 2>&1"
if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed' }
Wait-Ready $P
Wait-Ready $R
$streaming = '0'
for ($i = 0; $i -lt 30 -and $streaming -ne '1'; $i++) {
    Start-Sleep -Seconds 1
    $streaming = (Invoke-Sql $P "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming';" -Scalar | Select-Object -First 1).Trim()
}
if ($streaming -ne '1') { throw 'Replica is not streaming. Check: docker logs crestfield-pg-replica' }
Write-Section 'Replica base backup log' (cmd /c "docker logs $R 2>&1" | Select-Object -First 15)
Invoke-Sql $P "CREATE TABLE replication_heartbeat (id SERIAL PRIMARY KEY, note TEXT NOT NULL, written_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp());" | Out-Null

# ---------------------------------------------------------------------
Write-Section '2a. Primary: pg_stat_replication / slots' (Invoke-SqlFile $P '/portfolio/portfolio-5-distributed-cloud/sql/status_primary.sql')
Write-Section '2b. Replica: pg_stat_wal_receiver' (Invoke-SqlFile $R '/portfolio/portfolio-5-distributed-cloud/sql/status_replica.sql')

# ---------------------------------------------------------------------
$insert = @'
INSERT INTO student (matric_no, programme_id, first_name, last_name, email, date_of_birth, gender, entry_year)
VALUES ('CFU/2026/07001', 1, 'Replication', 'Test', 'replication.test@students.crestfield.edu.ng', '2007-01-01', 'F', 2026)
RETURNING matric_no, created_at;
'@
$w = Invoke-Sql $P $insert
$sw = [Diagnostics.Stopwatch]::StartNew()
$found = '0'
while ($found -ne '1' -and $sw.ElapsedMilliseconds -lt 10000) {
    $found = (Invoke-Sql $R "SELECT count(*) FROM student WHERE matric_no = 'CFU/2026/07001';" -Scalar | Select-Object -First 1).Trim()
}
$visibleMs = $sw.ElapsedMilliseconds
$lag = Invoke-Sql $P "SELECT application_name, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
Write-Section '3. Write on primary, read on replica' (
    @('Primary INSERT:') + $w +
    @('', "Row visible on replica after $visibleMs ms (includes ~100-200 ms docker exec overhead per poll)", '',
      'Replica read:') +
    (Invoke-Sql $R "SELECT matric_no, first_name, last_name, created_at FROM student WHERE matric_no = 'CFU/2026/07001';") +
    @('', 'Lag reported by the primary:') + $lag)

# ---------------------------------------------------------------------
Write-Section '4. Replica is read-only' (Invoke-Sql $R @'
SELECT pg_is_in_recovery() AS is_standby;
INSERT INTO student (matric_no, programme_id, first_name, last_name, email, date_of_birth, gender, entry_year)
VALUES ('CFU/2026/07002', 1, 'Should', 'Fail', 'should.fail@students.crestfield.edu.ng', '2007-01-01', 'M', 2026);
'@)

# ---------------------------------------------------------------------
Write-Host "`n== 5. Partitioning on the primary (output: results\partitioning.txt) ==" -ForegroundColor Cyan
$part = Invoke-SqlFile $P '/portfolio/portfolio-5-distributed-cloud/sql/01_partitioning.sql'
$part | Set-Content -Encoding UTF8 (Join-Path $results 'partitioning.txt')
Start-Sleep -Seconds 2
Write-Section '5. Partitioned tables replicated to the replica' (Invoke-Sql $R @'
SELECT tableoid::regclass AS partition, count(*) AS rows FROM result_history GROUP BY 1 ORDER BY 1;
SELECT tableoid::regclass AS shard, count(*) AS rows FROM activity_log GROUP BY 1 ORDER BY 1;
'@)

# ---------------------------------------------------------------------
Invoke-Sql $P "ALTER SYSTEM SET synchronous_standby_names = '*';" | Out-Null
Invoke-Sql $P 'SELECT pg_reload_conf();' | Out-Null
Start-Sleep -Seconds 2
$t1 = Measure-Command { Invoke-Sql $P "INSERT INTO replication_heartbeat (note) VALUES ('sync write, replica UP');" | Out-Null }
Write-Section '6a. Synchronous replication ON (replica up)' (
    (Invoke-Sql $P 'SELECT application_name, state, sync_state FROM pg_stat_replication;') +
    @("Commit time with synchronous replica: $([int]$t1.TotalMilliseconds) ms (includes docker exec overhead)"))

docker stop $R | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
$syncDown = Invoke-Sql $P @'
SET statement_timeout = '5s';
INSERT INTO replication_heartbeat (note) VALUES ('sync write, replica DOWN');
'@
$t2 = $sw.Elapsed
Write-Section '6b. Synchronous ON, replica DOWN: commit blocks (consistency over availability)' (
    $syncDown + @("Client waited $([int]$t2.TotalSeconds) s before statement_timeout cancelled the wait"))

Invoke-Sql $P 'ALTER SYSTEM RESET synchronous_standby_names;' | Out-Null
Invoke-Sql $P 'SELECT pg_reload_conf();' | Out-Null
Start-Sleep -Seconds 1
$sw = [Diagnostics.Stopwatch]::StartNew()
$asyncDown = Invoke-Sql $P "INSERT INTO replication_heartbeat (note) VALUES ('async write, replica DOWN');"
$t3 = $sw.Elapsed
Write-Section '6c. Asynchronous, replica DOWN: commit succeeds immediately (availability over consistency)' (
    $asyncDown + @("Commit time: $([int]$t3.TotalMilliseconds) ms"))

docker start $R | Out-Null
Wait-Ready $R
Start-Sleep -Seconds 3
Write-Section '6d. Replica restarted: it catches up from the slot (eventual consistency)' (
    @('Primary:') + (Invoke-Sql $P 'SELECT id, note FROM replication_heartbeat ORDER BY id;') +
    @('Replica:') + (Invoke-Sql $R 'SELECT id, note FROM replication_heartbeat ORDER BY id;'))

# ---------------------------------------------------------------------
docker stop $P | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
$promote = Invoke-Sql $R 'SELECT pg_promote(wait => true) AS promoted;'
$promoteMs = $sw.ElapsedMilliseconds
$after = Invoke-Sql $R @'
SELECT pg_is_in_recovery() AS is_standby;
INSERT INTO replication_heartbeat (note) VALUES ('first write on the PROMOTED replica');
SELECT id, note FROM replication_heartbeat ORDER BY id;
'@
Write-Section '7. Failover: primary stopped, replica promoted' (
    @('docker stop crestfield-pg-primary') + $promote + @("Promotion took $promoteMs ms", '') + $after)

Write-Host "`nPortfolio 5 completed. Report: $report" -ForegroundColor Green
Write-Host "The old primary is stopped. Reset the cluster with:" -ForegroundColor Yellow
Write-Host "  docker compose -f portfolio-5-distributed-cloud\docker-compose.replication.yml down -v"
