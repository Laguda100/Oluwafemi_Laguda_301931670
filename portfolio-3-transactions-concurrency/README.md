# Portfolio 3: Transactions and Concurrency

**Case study:** Crestfield University Student Result Portal
**Engine:** PostgreSQL 16.4 (Docker). Default isolation level is READ COMMITTED.

Results and course registration are where concurrency matters most in a university:
- **Registration week.** Thousands of students compete for limited seats in popular electives at the same moment.
- **Result moderation.** Several exams officers may adjust the same scores during the moderation period.

Every demo below is a real situation from that workload.

## Contents

| File | Purpose |
|---|---|
| [`sql/00_setup.sql`](sql/00_setup.sql) | Known starting state: a 1-seat elective (CSC 205), test scores reset to 50, and the `register_course()` function |
| [`sql/01_transactions.sql`](sql/01_transactions.sql) | Single-session demos: COMMIT, ROLLBACK, automatic abort, SAVEPOINT, isolation levels |
| [`sql/02_monitor_locks.sql`](sql/02_monitor_locks.sql) | Shows waiting and blocking sessions and the locks held (run in a 3rd terminal) |
| [`sql/concurrency/*_A.sql`, `*_B.sql`](sql/concurrency/) | The two sessions of each concurrency demo |
| [`run.ps1`](run.ps1) | Runs everything automatically and saves the output to `results/` |

## Part 1: Single-session transactions (`01_transactions.sql`)

| Demo | Scenario | Key statements | Expected output |
|---|---|---|---|
| **A. COMMIT** | Dr Ogunleye uploads CSC 201 scores for the whole class and marks the sheet SUBMITTED | `BEGIN; INSERT … ; UPDATE … ; COMMIT;` | `INSERT 0 4`, `UPDATE 1`, `COMMIT`. All 4 students have scores, and the status is `SUBMITTED`. |
| **B. ROLLBACK** | An officer adds +5 to the wrong course, checks, then undoes it | `BEGIN; UPDATE …; SELECT …; ROLLBACK;` | Inside the transaction the scores are +5. After ROLLBACK the original scores are back, and `audit_rows_after = audit_rows_before`, so even the trigger's audit rows were undone. |
| **C. Automatic abort** | Two score updates; the second is invalid (95 > 70) | `BEGIN; UPDATE(ok); UPDATE(bad); SELECT 1; COMMIT;` | `ERROR: … violates check constraint "result_exam_score_check"`, then `ERROR: current transaction is aborted…`. `COMMIT` prints **`ROLLBACK`**. The first, valid update is also gone (atomicity). |
| **D. SAVEPOINT** | Blessing Etim registers 3 electives; one is a duplicate | `SAVEPOINT after_csc201; … ROLLBACK TO SAVEPOINT after_csc201;` | The duplicate raises `unique_violation`. Only that statement is undone. The student ends with ACC 201, CSC 201, ECO 201 and MTH 201. |
| **E. Isolation level** | Show the default and per-transaction levels | `SHOW transaction_isolation;` | `read committed`, then `repeatable read`, then `serializable` |
| **F. register_course()** | 2 students, 1 seat | `SELECT register_course(…)` | The first succeeds. The second gets `ERROR: Course offering … is full (1 of 1 seats taken)`. |

## Part 2: Concurrency problems and their fixes (two sessions)

**How the overlap is produced:** session A starts, does its first step, then sleeps 3 s inside its open transaction. Session B starts 1.5 s later. Each line printed by a session is timestamped (`[A 14:02:11.348]`), so the result files prove the transactions overlapped.

### Demo 1 → 2: Lost update (moderation of the same score)

| Time | Session A (+5 moderation) | Session B (+2 correction) |
|---|---|---|
| t0 | `BEGIN; SELECT exam_score` → **50** | |
| t1.5 | (sleeping) | `BEGIN; SELECT exam_score` → **50**; `UPDATE … = 52; COMMIT` |
| t3 | `UPDATE … = 50+5 = 55; COMMIT` | |
| **Result** | **55**. B's +2 is **lost**; the correct value is 57. | |

**Why it happens:** the application read the value, computed the new value outside the database, and wrote it back. Under READ COMMITTED a plain `SELECT` takes no lock, so both sessions computed from the same stale 50.

**Fix (Demo 2, `fix=true`): `SELECT … FOR UPDATE`.** A's read takes a row lock, so B's `SELECT … FOR UPDATE` **blocks** until A commits. B then reads 55 and writes **57** ✔. B's timestamps show it waited about 1.5 s. (An atomic `UPDATE … SET exam_score = exam_score + 2` also fixes it, because UPDATE re-reads the latest committed row after waiting for the lock.)

### Demo 3 → 4 → 5: Overbooking the last seat (write skew)

| Time | Session A (student 9) | Session B (student 10) |
|---|---|---|
| t0 | `count(*)` → 0 of 1 → "seat free" | |
| t1.5 | (sleeping) | `count(*)` → 0 of 1 → `INSERT; COMMIT` ✔ |
| t3 | `INSERT; COMMIT` ✔ | |
| **Result (Demo 3, READ COMMITTED)** | **2 registered for capacity 1**: overbooked | |

Neither transaction changed a row the other one changed. Each inserted a *different* row, so row locks never conflict. This is a **write skew / phantom** anomaly.

- **Demo 4, SERIALIZABLE.** PostgreSQL's Serializable Snapshot Isolation (SSI) tracks what each transaction *read* (predicate/SIREAD locks). It detects that the two transactions can't be put in any serial order, so A fails with `ERROR: could not serialize access due to read/write dependencies among transactions` (**SQLSTATE 40001**). Final count: **1 of 1** ✔. The application must **retry** the failed transaction.
- **Demo 5, pessimistic locking in `register_course()`.** The function first runs `SELECT … FROM course_offering … FOR UPDATE`, locking the offering row. B's call waits on that lock. When A commits, B's next statement sees A's registration (READ COMMITTED takes a new snapshot per statement) and raises `Course offering … is full`. Final count: **1 of 1** ✔.

**Which fix I chose for production:** the row lock (Demo 5). It never needs a retry loop, and it only blocks registrations for *the same course*, so different courses still register in parallel. SERIALIZABLE is the more general safety net, but under registration-week load it would produce many 40001 errors and retries.

### Demo 6 → 7: Deadlock

| Time | Session A | Session B |
|---|---|---|
| t0 | `UPDATE` 00001 → locks row 1 | |
| t1.5 | (sleeping) | `UPDATE` 00002 → locks row 2; `UPDATE` 00001 → **waits for A** |
| t3 | `UPDATE` 00002 → **waits for B** | |
| t4 | `ERROR: deadlock detected` (**SQLSTATE 40P01**). A is rolled back. | B gets the lock, continues and commits |

PostgreSQL checks for cycles after `deadlock_timeout` (1 s). The detail message names both processes and the tuple each was waiting for. Final state: both scores 51 (only B's changes survive).

**Fix (Demo 7, `fix=true`): consistent lock ordering.** Both sessions first lock *both* rows with `SELECT … WHERE registration_id IN (…) ORDER BY registration_id FOR UPDATE`. Locks are always taken in the same order, so a cycle is impossible: B simply waits for A. Final state: both scores **52** (A +1 and B +1) ✔. `register_course()` follows the same rule (offering row first, then student row).

### Demo 8 → 9: Non-repeatable read vs REPEATABLE READ

| | First read (t0) | B commits +10 (t1.5) | Second read (t3) |
|---|---|---|---|
| **Demo 8, READ COMMITTED** | 50 | ✔ | **60**. The same query in the same transaction returned a different value. |
| **Demo 9, REPEATABLE READ** | 50 | ✔ | **50**. The transaction keeps the snapshot taken at its first query. |

Why it matters: a transcript or GPA report that reads results several times must use REPEATABLE READ. Otherwise the per-course lines and the GPA total could come from different moments in time and disagree.

### Demo 10: No dirty reads

Session A sets a score to 69 without committing, then rolls back. Session B asks for `READ UNCOMMITTED` and still sees **50**. PostgreSQL accepts the READ UNCOMMITTED syntax but treats it as READ COMMITTED, because MVCC readers always read the latest *committed* version of a row. **Dirty reads are impossible in PostgreSQL.**

## Summary: anomalies by isolation level (PostgreSQL)

| Anomaly | Read Committed | Repeatable Read | Serializable | Shown in |
|---|---|---|---|---|
| Dirty read | not possible | not possible | not possible | Demo 10 |
| Non-repeatable read | **possible** | prevented | prevented | Demos 8, 9 |
| Lost update (read-modify-write) | **possible** | prevented (error 40001) | prevented | Demos 1, 2 |
| Write skew / phantom (overbooking) | **possible** | **possible** | prevented (error 40001) | Demos 3, 4 |

The concurrency-control mechanisms demonstrated:
- **MVCC snapshots** (Demos 8–10)
- **Pessimistic row locks**: `FOR UPDATE` and `FOR NO KEY UPDATE` (Demos 2, 5)
- **Optimistic SSI** with retry (Demo 4)
- **Deadlock detection and prevention** (Demos 6, 7)

## How to run

### Automatic (all demos, about 1 minute)

```powershell
docker compose up -d
.\portfolio-3-transactions-concurrency\run.ps1
```

The output files are `results/01_transactions.txt` and `results/demoN_*.txt`. Each contains session A's output, session B's output, any errors, and the final state.

### Manual, with two terminals (for screenshots)

Open **three** PowerShell windows and run this in each:

```powershell
docker exec -it crestfield-pg psql -U portal_admin -d result_portal
```

Then, for the lost-update demo:

```sql
-- Terminal 1 and 2, once:
\i /portfolio/portfolio-3-transactions-concurrency/sql/00_setup.sql
\i /portfolio/portfolio-3-transactions-concurrency/sql/concurrency/common.sql
-- Terminal 1 (A)                              -- Terminal 2 (B)
BEGIN;
SELECT exam_score FROM result
 WHERE registration_id = :reg1 FOR UPDATE;
                                               BEGIN;
                                               SELECT exam_score FROM result
                                                WHERE registration_id = :reg1 FOR UPDATE;
                                               -- B hangs here: it is waiting for A
-- Terminal 3: \i /portfolio/portfolio-3-transactions-concurrency/sql/02_monitor_locks.sql
--   shows B with wait_event = 'transactionid' and blocked_by = {A's pid}
UPDATE result SET exam_score = 55 WHERE registration_id = :reg1;
COMMIT;
                                               -- B returns 55 immediately
                                               UPDATE result SET exam_score = 57 WHERE registration_id = :reg1;
                                               COMMIT;
```

## Evidence (`evidence/` folder)

| File | What it shows |
|---|---|
| `p3-01-commit-rollback.png` | `01_transactions.txt` sections A and B: scores after COMMIT, during and after ROLLBACK, audit counts equal |
| `p3-02-auto-abort-savepoint.png` | Sections C and D: the check violation, "current transaction is aborted", COMMIT → `ROLLBACK`, SAVEPOINT result list |
| `p3-03-lost-update.png` | `demo1_lost_update.txt` (final 55) next to `demo2_lost_update_fixed.txt` (final 57, B's timestamp shows the wait) |
| `p3-04-overbooking.png` | Demo 3 (`2 registered / capacity 1`) next to Demo 4 (`40001` error) and Demo 5 (`is full` error) |
| `p3-05-deadlock.png` | `demo6_deadlock.txt` with `ERROR: deadlock detected` and its DETAIL lines |
| `p3-06-isolation.png` | Demo 8 (50 → 60) next to Demo 9 (50 → 50) |
| `p3-07-lock-monitor.png` | Session A holds a row lock on a result, session B's UPDATE of the same row waits, and `02_monitor_locks.sql` shows B `blocked_by` A and B's ungranted `transactionid` ShareLock (`granted = f`) |
