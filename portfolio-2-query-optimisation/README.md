# Portfolio 2: Query Processing and Optimisation

**Case study:** Crestfield University Student Result Portal, using the same schema as Portfolio 1
**Engine:** PostgreSQL 16.4 (Docker), default configuration (`work_mem` 4 MB, `shared_buffers` 128 MB)

## Contents

| File | Purpose |
|---|---|
| [`sql/01_generate_data.sql`](sql/01_generate_data.sql) | Scales the database up to about 2.3M registrations and about 2M results |
| [`sql/02_queries.sql`](sql/02_queries.sql) | Seven realistic workload queries (Q1–Q7) |
| [`sql/03_indexes.sql`](sql/03_indexes.sql) | Indexing strategy (I1–I5), plus index sizes |
| [`sql/04_drop_indexes.sql`](sql/04_drop_indexes.sql) | Removes the indexes, to repeat the "before" test |
| [`sql/05_explain_all.sql`](sql/05_explain_all.sql) | Runs Q1–Q7 under `EXPLAIN (ANALYZE, BUFFERS)` |
| [`run.ps1`](run.ps1) | Runs the whole experiment end to end |
| `results/` | Generated output: query results, plans before and after, timing table |
| `evidence/` | Screenshots |

## 1. Test dataset

A dozen rows can't show an optimiser at work: on tiny tables a sequential scan is always cheapest. `01_generate_data.sql` grows the Portfolio 1 database into a realistic university:

| Table | Rows (approx.) | How it's generated |
|---|---|---|
| academic_session | 8 | 2019/2020 to 2026/2027 |
| course | 203 | 4 departments × 4 levels × 2 semesters × 6 courses, plus the Portfolio 1 courses |
| course_offering | about 1,550 | every course in every session |
| student | 60,012 | 7,500 per entry year (2019–2026) |
| registration | about 2.3 million | each student takes 12 courses per year at their level |
| result | about 2.0 million | all completed sessions. Scores have a bell-shaped spread, with about 3% failures. |

Design notes:
- **Deterministic data.** `setseed(0.8103)` and formula-based values mean every run produces the same dataset, so timings are comparable between runs.
- **Triggers disabled during the bulk load.** The audit triggers are turned off for the 2M-row load and switched straight back on. This is standard bulk-load practice: firing a trigger per row would double the load time and fill `result_audit` with 2M meaningless rows.
- **`VACUUM ANALYZE` after loading.** This refreshes planner statistics, so the optimiser has correct row estimates, and sets the visibility map needed for index-only scans.

## 2. Workload queries

| # | Business question | SQL techniques |
|---|---|---|
| Q1 | A student views their transcript | 6-table join through view `v_student_result`, LATERAL lookup |
| Q2 | HOD prints the result sheet for CSC 310 (2024/2025) | Joins, LATERAL grade lookup, ORDER BY + LIMIT |
| Q3 | Pass rate per course in Computer Science | GROUP BY, `count(*) FILTER (WHERE …)`, AVG |
| Q4 | Top 3 graduates per programme (2022 cohort) | **CTE**, **window functions** `RANK()`, `AVG() OVER`, `NTILE()` |
| Q5 | Carry-over list for 2024/2025 | Selective filter (`total_score < 40`), `string_agg` |
| Q6 | Students above the class average in MTH 410 | **CTE + scalar subquery**, CROSS JOIN with an aggregate |
| Q7 | Help-desk name search ignoring capitalisation | Expression predicate `lower(col) = …` |

Query results are saved to `results/query_results.txt`.

## 3. Indexing strategy

Each index targets a specific query. Section 4 compares the plans before and after to check whether it actually helped. One index (I1) turned out to be redundant:

| Index | Definition | Target | Reasoning |
|---|---|---|---|
| I1 | `registration (student_id) INCLUDE (offering_id, status)` | Q1, Q4 | `student_id` is a foreign key, and PostgreSQL does not index FKs automatically, so I expected Q1 to need a sequential scan of 2.3M rows. **It didn't.** The unique constraint `uq_registration_student_offering (student_id, offering_id)` from Portfolio 1 already creates a B-tree index whose *leading column* is `student_id`, and the planner used it for Q1 before I1 existed. I1 was also meant to be a covering index allowing an Index Only Scan, but the view needs `registration_id` as well, which I1 doesn't store, so it still visits the heap. I1 adds 91 MB and extra work on every INSERT for no measurable gain, so it should be dropped. |
| I2 | `registration (offering_id)` | Q2, Q3, Q6 | Finds all students in one course offering. That's about 1,900 rows out of 2.3M (0.08%), which is highly selective. |
| I3 | `result (registration_id) WHERE total_score < 40` | Q5 | A **partial index**. Only failed results (about 3%) are stored, so it's about 30 times smaller than a full index and is used only when the query's WHERE clause implies `total_score < 40`. This is why `total_score` was stored as a generated column in Portfolio 1. |
| I4 | `student (lower(last_name), lower(first_name))` | Q7 | An **expression index**. A plain index on `last_name` can't be used for `lower(last_name) = 'okafor'`, because the index has to store the same expression the query uses. |
| I5 | `student (entry_year)` | Q4 | Filters one cohort (12.5% of students). The planner may still choose a sequential scan for this one. See the analysis below. |

**Indexes deliberately NOT created:**
- `course_offering(session_id)`, `course(department_id)`. These tables have about 1,500 and about 200 rows and fit in a handful of 8 kB pages. A sequential scan is already as fast as an index lookup.
- `result(total_score)` as a full index. Passing results (97%) are never searched by score. The partial index I3 covers the only selective use.
- Every extra index **slows down INSERT/UPDATE** (registration week and result upload) and uses disk. `03_indexes.sql` prints each index's size so that cost is visible.

## 4. Performance analysis

The measured timings are in **[`results/timing_summary.md`](results/timing_summary.md)**, which `run.ps1` generates. Times are from the second (warm-cache) run of `EXPLAIN (ANALYZE, BUFFERS)`, so cache effects don't distort the comparison. The cold-cache runs are kept in `explain_*_cold.txt`.

What the plans actually showed, from `results/explain_before.txt` and `results/explain_after.txt`. Times are warm-cache execution times from the run on 11 November 2026. The data is deterministic, so the plans repeat on every run, but the milliseconds vary a little.

| Query | Before → after (ms) | Plan before indexing | Plan after indexing | Why |
|---|---:|---|---|---|
| Q1 | 1.12 → 0.99 | `Index Scan using uq_registration_student_offering`: 48 rows, then primary-key nested loops into result, offering and course | Same shape, using `ix_registration_student` instead | The unique constraint's index already starts with `student_id`, so the lookup was indexed from the start. I1 only duplicated it. |
| Q2 | 979 → 67 (**15x**) | No index on `offering_id`, so the planner walks 22,597 students in `matric_no` order and probes the unique index once per student | `Index Scan using ix_registration_offering`: the 1,875 registrations of the one offering, read directly | A composite index can't be used to search on its *second* column, so I2 was genuinely missing. |
| Q3 | 348 → 477 (**slower**) | `Parallel Seq Scan on registration` hash-joined to the 48 CSC offerings (90,000 rows), then 90,000 primary-key probes into result | 48 index scans on `ix_registration_offering`, then a hash join against a full `Parallel Seq Scan on result` (2M rows) | The planner estimated the new plan as cheaper (cost 35,766 vs 49,571) but it ran slower. Registrations are stored grouped by student, not by course, so each offering's rows are scattered across the table. The index scans touched about 270,000 buffers, against about 19,500 pages for a whole sequential scan, and the hash build was repeated in each of the 3 parallel processes. |
| Q4 | 1,931 → 1,188 | Parallel sequential scans of student, registration and result with hash joins | Same, except student is now read with a `Bitmap Index Scan on ix_student_entry_year` (I5) | The cohort is about 360,000 registrations, a large share of the table, so the planner correctly keeps sequential scans and hash joins. **I1 is not used, and that's the right decision.** I5 only saves about 20 ms, so most of the difference is run-to-run variation rather than the index. |
| Q5 | 429 → 574 (**slower**) | `Parallel Seq Scan on result` with `Filter: total_score < 40`: 648,093 rows removed per worker | `Index Only Scan using ix_result_failed` (35,768 rows, 0 heap fetches, 5 ms), **but** registration is now read with 192 index scans on `ix_registration_offering` | The partial index worked: finding the failed results fell from about 140 ms to 5 ms. The slowdown comes from the other side of the join. The planner replaced a parallel sequential scan of registration (about 85 ms) with 192 single-process index scans over 360,000 scattered rows (about 420 ms). The cost estimate fell from 61,480 to 24,752 while the real time rose. |
| Q6 | 255 → 75 (**3.4x**) | Two `Parallel Seq Scan on registration` (one for the average, one for the list) | Two `Bitmap Index Scan on ix_registration_offering` → `Bitmap Heap Scan` | Only 1,875 rows needed. The bitmap reads each heap page once, in physical order, which avoids the scattered-read problem of Q3 and Q5. |
| Q7 | 20.2 → 0.40 (**51x**) | `Seq Scan on student` with a `lower(last_name)` filter over 60,000 rows | `Bitmap Index Scan on ix_student_lower_name` → `Bitmap Heap Scan` (161 rows) | The expression index stores exactly the expression the query uses. |

**Conclusions from the measurements**
- **Three indexes clearly paid off:** I2 (Q2 and Q6), I3 (the Q5 lookup itself) and I4 (Q7).
- **I1 was redundant.** Before adding an index, check whether an existing composite index already has the column in its *leading* position.
- **A cheaper estimate is not a faster plan.** In Q3 and Q5 the planner rated the index plans cheaper, but they ran slower. Its cost model undervalued hundreds of thousands of index-driven buffer accesses against a sequential scan of about 19,500 pages. `offering_id` doesn't follow the order rows are stored in (they are grouped by student), so each index lookup lands on a different page. In Q5 the switch also cost the parallel scan. Possible fixes are clustering `registration` on `offering_id` (which would slow Q1 instead), raising `random_page_cost`, or simply not creating I2 for the reporting queries. That decision depends on which workload matters more. Here it's the per-course result sheets (Q2, Q6), so I2 stays.

### What to look for in the plans (explained in my own words in the reflection)

- **Estimated vs actual rows** (`rows=` in the cost section vs `actual … rows=`). Close numbers mean the statistics are good. A big gap means the plan may have been chosen badly.
- **`Buffers: shared hit=… read=…`.** `hit` is pages found in memory, `read` is pages fetched from disk. Indexes reduce the total number of pages touched, which is the real cost driver.
- **Join algorithms.** **Nested Loop** suits a small outer input with an index on the inner side (Q1). **Hash Join** suits large unsorted inputs (Q3, Q4). **Merge Join** suits inputs already sorted on the join key.
- **`Rows Removed by Filter`.** A large number here signals a missing index (Q5 and Q7 before indexing).
- **Parallel workers** (`Workers Launched: 2`). PostgreSQL splits big sequential scans across CPU cores. This makes the "before" timings faster than a single-threaded scan, but it uses more CPU.

### Trade-offs observed

- Index creation time and size are recorded in `results/index_creation.txt`. On write-heavy tables like `registration`, each index adds work to every INSERT.
- A covering index avoids heap access only if it stores *every* column the query needs from that table. I1 missed `registration_id`, so Q1 still visits the heap. The partial index I3 does cover its query: Q5 shows `Index Only Scan … Heap Fetches: 0`, which relies on the visibility map that `VACUUM` keeps up to date.
- The index sizes show the cost of a mistake: the redundant I1 is the largest index (91 MB), bigger than the four useful ones combined.

## 5. How to run

```powershell
docker compose up -d
.\portfolio-2-query-optimisation\run.ps1       # about 3-6 minutes in total
```

The script rebuilds the Portfolio 1 schema, so it always starts from the same state. To experiment manually:

```powershell
docker exec -it crestfield-pg psql -U portal_admin -d result_portal
```
```sql
\i /portfolio/portfolio-2-query-optimisation/sql/04_drop_indexes.sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM v_student_result WHERE matric_no = 'CFU/2023/00450';
\i /portfolio/portfolio-2-query-optimisation/sql/03_indexes.sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM v_student_result WHERE matric_no = 'CFU/2023/00450';
```

## 6. How it was tested

- `ON_ERROR_STOP=1` on every script, so the run stops on any SQL error.
- The data-volume table at the end of `results/data_generation.txt` confirms the row counts.
- Query results were spot-checked. For example, Q3 pass rates fall between 90% and 100%, consistent with the roughly 3% failure rate, and Q6 only lists scores above the printed class average.
- Plans were compared before and after for each query (`results/explain_*.txt`).

## 7. Evidence (`evidence/` folder)

| File | What it shows |
|---|---|
| `p2-01-data-volume.png` | End of `data_generation.txt`: row counts and table sizes |
| `p2-02-q1-before.png` | Q1 plan **before**: `Index Scan using uq_registration_student_offering` with its Execution Time (already indexed) |
| `p2-03-q2-before-after.png` | Q2 before (per-student probes, about 979 ms) and after (`Index Scan using ix_registration_offering`, about 67 ms) |
| `p2-04-q5-before-after.png` | Q5 before (`Rows Removed by Filter`) and after (`Index Only Scan using ix_result_failed`, plus the index scans that made it slower overall) |
| `p2-05-q4-window.png` | Q4 result rows (programme rank, CGPA, programme average) |
| `p2-06-index-sizes.png` | The index-size table from `index_creation.txt` |
| `p2-07-timing-summary.png` | `results/timing_summary.md` (before/after/speed-up table) |
