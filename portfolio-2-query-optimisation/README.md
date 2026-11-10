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

Each index was chosen by reading the "before" plan, finding the expensive node, and targeting it:

| Index | Definition | Target | Reasoning |
|---|---|---|---|
| I1 | `registration (student_id) INCLUDE (offering_id, status)` | Q1, Q4 | `student_id` is a foreign key, and PostgreSQL does not index FKs automatically. Without this index, finding one student's registrations means a **sequential scan of 2.3M rows**. `INCLUDE` makes it a **covering index**: the join columns are stored in the index leaf, so the plan can use an **Index Only Scan** and skip the table heap. |
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

How each plan is expected to change, and why. Confirm each point against `results/explain_before.txt` and `results/explain_after.txt`:

| Query | Plan before indexing | Plan after indexing | Why |
|---|---|---|---|
| Q1 | `Parallel Seq Scan on registration` reads every row to find about 48 for one student | `Index Only Scan using ix_registration_student`, with nested loops into result, offering and course using primary keys | Selectivity 0.002%. The cost model switches from scanning pages to random index lookups. The biggest improvement is expected here (orders of magnitude). |
| Q2, Q6 | `Seq Scan on registration` filtered by `offering_id`, then a hash join | `Bitmap Index Scan on ix_registration_offering` → `Bitmap Heap Scan` | About 1,900 matching rows. The bitmap reads each heap page once, in physical order. |
| Q3 | Hash joins over a full registration scan | Bitmap/index scans for the 12 offerings, then HashAggregate | Fewer rows read, but the aggregation itself is the same work, so a smaller gain than Q1. |
| Q4 | Seq scan of student filtered by `entry_year`, hash join to registration | Index on registration via I1, possibly a bitmap scan on I5 | 7,500 students × 48 courses = about 360k rows is a large share of the data. The planner may correctly decide a hash join with sequential scans is still cheapest. **An index is not always used, and that's the right decision.** |
| Q5 | `Seq Scan on result`, `Filter: total_score < 40`, discarding about 97% of rows | `Bitmap Index Scan on ix_result_failed` | The partial index contains only the rows wanted. |
| Q7 | `Seq Scan on student`, `Filter: lower(last_name)…` over 60k rows | `Index Scan using ix_student_lower_name` | The expression index matches the predicate exactly. |

### What to look for in the plans (explained in my own words in the reflection)

- **Estimated vs actual rows** (`rows=` in the cost section vs `actual … rows=`). Close numbers mean the statistics are good. A big gap means the plan may have been chosen badly.
- **`Buffers: shared hit=… read=…`.** `hit` is pages found in memory, `read` is pages fetched from disk. Indexes reduce the total number of pages touched, which is the real cost driver.
- **Join algorithms.** **Nested Loop** suits a small outer input with an index on the inner side (Q1 after indexing). **Hash Join** suits large unsorted inputs (Q3, Q4). **Merge Join** suits inputs already sorted on the join key.
- **`Rows Removed by Filter`.** A large number here signals a missing index (Q5 and Q7 before indexing).
- **Parallel workers** (`Workers Launched: 2`). PostgreSQL splits big sequential scans across CPU cores. This makes the "before" timings faster than a single-threaded scan, but it uses more CPU.

### Trade-offs observed

- Index creation time and size are recorded in `results/index_creation.txt`. On write-heavy tables like `registration`, each index adds work to every INSERT.
- A covering index (I1) is bigger than a plain one, but it avoids heap access entirely when the visibility map is up to date, which is why `VACUUM` matters.

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
| `p2-02-q1-before.png` | Q1 plan **before**: `Seq Scan on registration` with its Execution Time |
| `p2-03-q1-after.png` | Q1 plan **after**: `Index Only Scan using ix_registration_student` with its Execution Time |
| `p2-04-q5-before-after.png` | Q5 before (`Rows Removed by Filter`) and after (`ix_result_failed`) |
| `p2-05-q4-window.png` | Q4 result rows (programme rank, CGPA, programme average) |
| `p2-06-index-sizes.png` | The index-size table from `index_creation.txt` |
| `p2-07-timing-summary.png` | `results/timing_summary.md` (before/after/speed-up table) |
