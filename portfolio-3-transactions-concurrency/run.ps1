# Portfolio 3: transactions and concurrency demonstrations.
# Usage (from the repository root):  .\portfolio-3-transactions-concurrency\run.ps1
#
# 1. Rebuilds the Portfolio 1 database (small, predictable dataset)
# 2. Runs the single-session transaction script (COMMIT / ROLLBACK / SAVEPOINT)
# 3. Runs each two-session concurrency demo. Session A starts first;
#    session B starts 1.5 s later while A is still inside its transaction
#    (A sleeps 3 s), so the two transactions genuinely overlap.
# All output goes to portfolio-3-transactions-concurrency\results\.

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = Join-Path $root 'results'
New-Item -ItemType Directory -Force $results | Out-Null

$p1 = '/portfolio/portfolio-1-database-design/sql'
$p3 = '/portfolio/portfolio-3-transactions-concurrency/sql'
$psqlBase = 'docker exec crestfield-pg psql -X -U portal_admin -d result_portal'

function Invoke-Psql([string]$file, [string]$outName, [switch]$Strict) {
    $stop = if ($Strict) { '-v ON_ERROR_STOP=1' } else { '' }
    $cmd = "$psqlBase $stop -f $file"
    if ($outName) {
        cmd /c "$cmd > `"$(Join-Path $results $outName)`" 2>&1"
    } else {
        cmd /c "$cmd > NUL 2>&1"
    }
    if ($Strict -and $LASTEXITCODE -ne 0) { throw "$file failed" }
}

function Start-Session([string]$file, [string[]]$vars, [string]$outBase) {
    $argList = @('exec', 'crestfield-pg', 'psql', '-X', '-U', 'portal_admin', '-d', 'result_portal')
    foreach ($v in $vars) { $argList += @('-v', $v) }
    $argList += @('-f', "$p3/concurrency/$file")
    Start-Process -FilePath 'docker' -ArgumentList $argList -NoNewWindow -PassThru `
        -RedirectStandardOutput "$outBase.out" -RedirectStandardError "$outBase.err"
}

function Invoke-Demo([string]$title, [string]$name, [string]$a, [string]$b, [string[]]$vars) {
    Write-Host "== $title ==" -ForegroundColor Cyan
    Invoke-Psql "$p3/00_setup.sql" -Strict                     # identical starting state
    $tmpA = Join-Path $env:TEMP "p3_${name}_A"
    $tmpB = Join-Path $env:TEMP "p3_${name}_B"
    $procA = Start-Session $a $vars $tmpA
    Start-Sleep -Milliseconds 1500
    $procB = Start-Session $b $vars $tmpB
    $procA.WaitForExit(); $procB.WaitForExit()

    $verify = cmd /c "$psqlBase -f $p3/concurrency/verify.sql 2>&1"
    $report = @("===== $title =====", "Variables: $($vars -join ' ')", '',
                '----- Session A (stdout) -----') + (Get-Content "$tmpA.out") +
              @('----- Session A (errors) -----') + (Get-Content "$tmpA.err") +
              @('', '----- Session B (stdout) -----') + (Get-Content "$tmpB.out") +
              @('----- Session B (errors) -----') + (Get-Content "$tmpB.err") +
              @('', '----- Final state -----') + $verify
    $outFile = Join-Path $results "$name.txt"
    $report | Set-Content -Encoding UTF8 $outFile
    $report | Where-Object { $_ -match '^\[(A|B) |ERROR|exam_score|CFU/|csc205|^\s+\d' } | ForEach-Object { "   $_" }
}

Write-Host '== Rebuilding Portfolio 1 database ==' -ForegroundColor Cyan
Invoke-Psql "$p1/01_schema.sql" -Strict
Invoke-Psql "$p1/02_seed.sql"   -Strict
Invoke-Psql "$p1/03_views.sql"  -Strict
Invoke-Psql "$p3/00_setup.sql"  -Strict

Write-Host '== Single-session transactions (A-F) ==' -ForegroundColor Cyan
Invoke-Psql "$p3/01_transactions.sql" '01_transactions.txt'
Get-Content (Join-Path $results '01_transactions.txt') | Select-Object -First 40

Invoke-Demo 'Demo 1: Lost update (READ COMMITTED, read-modify-write)' 'demo1_lost_update' 'lost_update_A.sql' 'lost_update_B.sql' @('fix=false')
Invoke-Demo 'Demo 2: Lost update FIXED with SELECT ... FOR UPDATE'     'demo2_lost_update_fixed' 'lost_update_A.sql' 'lost_update_B.sql' @('fix=true')
Invoke-Demo 'Demo 3: Overbooking under READ COMMITTED'                 'demo3_overbooking' 'overbooking_A.sql' 'overbooking_B.sql' @('serializable=false')
Invoke-Demo 'Demo 4: Overbooking prevented by SERIALIZABLE'            'demo4_overbooking_serializable' 'overbooking_A.sql' 'overbooking_B.sql' @('serializable=true')
Invoke-Demo 'Demo 5: Overbooking prevented by row lock in register_course()' 'demo5_overbooking_locked' 'overbooking_fixed_A.sql' 'overbooking_fixed_B.sql' @()
Invoke-Demo 'Demo 6: Deadlock (opposite lock order)'                   'demo6_deadlock' 'deadlock_A.sql' 'deadlock_B.sql' @('fix=false')
Invoke-Demo 'Demo 7: Deadlock avoided by consistent lock ordering'     'demo7_deadlock_fixed' 'deadlock_A.sql' 'deadlock_B.sql' @('fix=true')
Invoke-Demo 'Demo 8: Non-repeatable read under READ COMMITTED'         'demo8_nonrepeatable_read' 'isolation_A.sql' 'isolation_B.sql' @('rr=false')
Invoke-Demo 'Demo 9: REPEATABLE READ gives a stable snapshot'          'demo9_repeatable_read' 'isolation_A.sql' 'isolation_B.sql' @('rr=true')
Invoke-Demo 'Demo 10: No dirty reads, even with READ UNCOMMITTED'      'demo10_no_dirty_read' 'dirty_read_A.sql' 'dirty_read_B.sql' @()

Write-Host "`nPortfolio 3 completed. Full output in $results" -ForegroundColor Green
