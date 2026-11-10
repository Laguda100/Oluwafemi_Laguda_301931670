# Portfolio 2: query processing and optimisation experiment.
# Usage (from the repository root):  .\portfolio-2-query-optimisation\run.ps1
#
# Steps:
#   1. Rebuild the Portfolio 1 schema (clean, repeatable starting point)
#   2. Generate the large dataset (60k students, ~2.3M registrations)
#   3. Run the queries once to capture their results
#   4. EXPLAIN ANALYZE every query WITHOUT the Portfolio 2 indexes
#   5. Create the indexes
#   6. EXPLAIN ANALYZE every query WITH the indexes
#   7. Write a before/after timing table to results\timing_summary.md
#
# All output is saved in portfolio-2-query-optimisation\results\.

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root 'results'
New-Item -ItemType Directory -Force $results | Out-Null

# Runs a SQL file in the container. cmd.exe does the redirection so the file
# gets psql's raw UTF-8 output (stdout + stderr, including \timing lines).
function Invoke-Psql([string]$file, [string]$outName) {
    $cmd = "docker exec crestfield-pg psql -X -U portal_admin -d result_portal -v ON_ERROR_STOP=1 -f $file"
    if ($outName) {
        $outPath = Join-Path $results $outName
        cmd /c "$cmd > `"$outPath`" 2>&1"
    } else {
        cmd /c "$cmd 2>&1"
    }
    if ($LASTEXITCODE -ne 0) { throw "$file failed (exit $LASTEXITCODE). Check the output file: $outName" }
}

$p1 = '/portfolio/portfolio-1-database-design/sql'
$p2 = '/portfolio/portfolio-2-query-optimisation/sql'

Write-Host '== 1. Rebuilding Portfolio 1 schema ==' -ForegroundColor Cyan
Invoke-Psql "$p1/01_schema.sql"
Invoke-Psql "$p1/02_seed.sql"
Invoke-Psql "$p1/03_views.sql"

Write-Host '== 2. Generating large dataset (1-3 minutes) ==' -ForegroundColor Cyan
Invoke-Psql "$p2/01_generate_data.sql" 'data_generation.txt'
Get-Content (Join-Path $results 'data_generation.txt') | Select-Object -Last 20

Write-Host '== 3. Query results ==' -ForegroundColor Cyan
Invoke-Psql "$p2/02_queries.sql" 'query_results.txt'

Write-Host '== 4. EXPLAIN ANALYZE before indexing (run twice; 2nd run = warm cache) ==' -ForegroundColor Cyan
Invoke-Psql "$p2/05_explain_all.sql" 'explain_before_cold.txt'
Invoke-Psql "$p2/05_explain_all.sql" 'explain_before.txt'

Write-Host '== 5. Creating indexes ==' -ForegroundColor Cyan
Invoke-Psql "$p2/03_indexes.sql" 'index_creation.txt'
Get-Content (Join-Path $results 'index_creation.txt')

Write-Host '== 6. EXPLAIN ANALYZE after indexing ==' -ForegroundColor Cyan
Invoke-Psql "$p2/05_explain_all.sql" 'explain_after_cold.txt'
Invoke-Psql "$p2/05_explain_all.sql" 'explain_after.txt'

# 7. Extract "Execution Time" per query label and build a comparison table
function Get-Timings([string]$path) {
    $map = [ordered]@{}
    $label = $null
    foreach ($line in Get-Content $path) {
        if ($line -match '^### (Q\d+) (.*)$') { $label = $Matches[1]; $map[$label] = @{ Name = $Matches[2]; Ms = $null } }
        elseif ($label -and $line -match 'Execution Time: ([\d.]+) ms') { $map[$label].Ms = [double]$Matches[1] }
    }
    return $map
}
$before = Get-Timings (Join-Path $results 'explain_before.txt')
$after  = Get-Timings (Join-Path $results 'explain_after.txt')

$culture = [System.Globalization.CultureInfo]::InvariantCulture
$lines = @(
    '# Timing summary (warm cache, EXPLAIN ANALYZE execution time)',
    '',
    "Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') by run.ps1",
    '',
    '| Query | Description | Before (ms) | After (ms) | Speed-up |',
    '|---|---|---:|---:|---:|'
)
foreach ($q in $before.Keys) {
    $b = $before[$q].Ms; $a = $after[$q].Ms
    if ($null -eq $b -or $null -eq $a) { $lines += "| $q | $($before[$q].Name) | n/a | n/a | n/a |"; continue }
    $speed = if ($a -gt 0) { ($b / $a).ToString('0.0', $culture) + 'x' } else { 'n/a' }
    $lines += "| $q | $($before[$q].Name) | $($b.ToString('0.00', $culture)) | $($a.ToString('0.00', $culture)) | $speed |"
}
$summary = Join-Path $results 'timing_summary.md'
$lines | Set-Content -Encoding UTF8 $summary
Get-Content $summary
Write-Host "`nPortfolio 2 completed. Results in $results" -ForegroundColor Green
