# Runs every Portfolio 1 script in order inside the PostgreSQL container.
# Usage (from the repository root):  .\portfolio-1-database-design\run.ps1
# Requires: docker compose up -d  (container "crestfield-pg" running)
# Output is shown on screen and saved to portfolio-1-database-design\results\run_output.txt

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root 'results'
New-Item -ItemType Directory -Force $results | Out-Null
$outFile = Join-Path $results 'run_output.txt'
Set-Content -Encoding UTF8 $outFile "Portfolio 1 run - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

$scripts = @(
    '01_schema.sql',
    '02_seed.sql',
    '03_views.sql',
    '04_constraint_tests.sql',
    '05_verify.sql'
)

foreach ($s in $scripts) {
    $header = "`n==================== $s ===================="
    Write-Host $header -ForegroundColor Cyan
    Add-Content -Encoding UTF8 $outFile $header
    # psql writes NOTICE lines (including the PASS lines) to stderr. PowerShell 5.1
    # treats redirected native stderr as an error, so cmd does the redirection.
    $tmp = Join-Path $results "$s.tmp"
    cmd /c "docker exec -i crestfield-pg psql -U portal_admin -d result_portal -v ON_ERROR_STOP=1 -f /portfolio/portfolio-1-database-design/sql/$s > `"$tmp`" 2>&1"
    $code = $LASTEXITCODE
    $lines = Get-Content $tmp
    Remove-Item $tmp
    $lines | ForEach-Object { Write-Host $_ }
    Add-Content -Encoding UTF8 $outFile $lines
    if ($code -ne 0) { throw "$s failed (exit code $code)" }
}
Write-Host "`nPortfolio 1 completed successfully. Output saved to $outFile" -ForegroundColor Green
