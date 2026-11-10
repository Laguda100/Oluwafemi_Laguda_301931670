# Portfolio 4: NoSQL (MongoDB 7.0) model of the result portal.
# Usage (from the repository root):  .\portfolio-4-nosql\run.ps1
#
# 1. Makes sure the Portfolio 1 relational data exists in PostgreSQL
# 2. Exports one JSON document per student from PostgreSQL (data\students.ndjson)
# 3. Runs the MongoDB scripts 01-05 and saves each output in results\

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root 'results'
$data    = Join-Path $root 'data'
New-Item -ItemType Directory -Force $results, $data | Out-Null
$pg = 'docker exec crestfield-pg psql -X -U portal_admin -d result_portal -v ON_ERROR_STOP=1'

# 1. Portfolio 1 schema present? (If not, build it.)
$exists = (cmd /c "$pg -At -c `"SELECT to_regclass('v_cgpa') IS NOT NULL`"").Trim()
if ($exists -ne 't') {
    Write-Host '== Building Portfolio 1 database ==' -ForegroundColor Cyan
    foreach ($f in '01_schema.sql', '02_seed.sql', '03_views.sql') {
        cmd /c "$pg -q -f /portfolio/portfolio-1-database-design/sql/$f > NUL"
        if ($LASTEXITCODE -ne 0) { throw "$f failed" }
    }
}

# 2. Relational -> document export
Write-Host '== Exporting student documents from PostgreSQL ==' -ForegroundColor Cyan
cmd /c "$pg -At -f /portfolio/portfolio-4-nosql/sql/export_students.sql -o /tmp/students.ndjson"
if ($LASTEXITCODE -ne 0) { throw 'export failed' }
docker cp crestfield-pg:/tmp/students.ndjson (Join-Path $data 'students.ndjson') | Out-Null
Write-Host "   $((Get-Content (Join-Path $data 'students.ndjson')).Count) documents written to data\students.ndjson"

# 3. MongoDB scripts
$scripts = '01_setup.js', '02_load_students.js', '03_seed_other.js', '04_queries.js', '05_validation_tests.js'
foreach ($s in $scripts) {
    Write-Host "== mongosh $s ==" -ForegroundColor Cyan
    $out = Join-Path $results ($s -replace '\.js$', '.txt')
    cmd /c "docker exec crestfield-mongo mongosh --quiet /portfolio/portfolio-4-nosql/scripts/$s > `"$out`" 2>&1"
    if ($LASTEXITCODE -ne 0) { Get-Content $out | Select-Object -Last 20; throw "$s failed" }
    Get-Content $out | Select-Object -First 25
}
Write-Host "`nPortfolio 4 completed. Output in $results" -ForegroundColor Green
