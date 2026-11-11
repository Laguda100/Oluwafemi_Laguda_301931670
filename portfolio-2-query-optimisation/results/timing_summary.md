# Timing summary (warm cache, EXPLAIN ANALYZE execution time)

Generated 2026-11-11 18:12 by run.ps1

| Query | Description | Before (ms) | After (ms) | Speed-up |
|---|---|---:|---:|---:|
| Q1 | Student transcript (multi-table JOIN through a view) | 1.12 | 0.99 | 1.1x |
| Q2 | Course result sheet (JOIN + LATERAL grade lookup) | 978.91 | 66.91 | 14.6x |
| Q3 | Departmental pass-rate report (GROUP BY + FILTER aggregates) | 347.71 | 477.10 | 0.7x |
| Q4 | Top 3 graduates per programme, 2022 cohort (CTE + window functions) | 1931.48 | 1188.06 | 1.6x |
| Q5 | Carry-over list: students who failed courses in 2024/2025 (selective filter) | 428.80 | 574.28 | 0.7x |
| Q6 | Students above the course average (CTE + scalar subquery) | 254.92 | 74.73 | 3.4x |
| Q7 | Case-insensitive student search by name (expression predicate) | 20.18 | 0.40 | 50.8x |
