# Runs every Portfolio 1 script in order inside the PostgreSQL container.
# Usage (from the repository root):  .\portfolio-1-database-design\run.ps1
# Requires: docker compose up -d  (container "crestfield-pg" running)

$ErrorActionPreference = 'Stop'
$scripts = @(
    '01_schema.sql',
    '02_seed.sql',
    '03_views.sql',
    '04_constraint_tests.sql',
    '05_verify.sql'
)

foreach ($s in $scripts) {
    Write-Host "`n==================== $s ====================" -ForegroundColor Cyan
    docker exec -i crestfield-pg psql -U portal_admin -d result_portal `
        -v ON_ERROR_STOP=1 -f "/portfolio/portfolio-1-database-design/sql/$s"
    if ($LASTEXITCODE -ne 0) { throw "$s failed (exit code $LASTEXITCODE)" }
}
Write-Host "`nPortfolio 1 completed successfully." -ForegroundColor Green
