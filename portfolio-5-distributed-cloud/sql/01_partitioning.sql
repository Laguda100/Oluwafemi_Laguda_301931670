-- =====================================================================
-- Portfolio 5 - Crestfield University Student Result Portal
-- File   : 01_partitioning.sql   (run on the PRIMARY)
-- Purpose: Two data-distribution strategies inside PostgreSQL:
--   A. RANGE partitioning of historic results by academic year
--      (partition pruning + instant archiving with DETACH)
--   B. HASH partitioning of activity data by student_id - the same
--      principle a sharded cluster (e.g. Citus) uses to spread rows
--      across nodes; here the "shards" are 4 local partitions.
-- Everything here is automatically replicated to the standby.
-- =====================================================================

\timing on
\pset footer off
DROP TABLE IF EXISTS result_history, activity_log CASCADE;

-- ---------------------------------------------------------------------
\echo '=== A. RANGE partitioning: result_history by session_year ==='
-- ---------------------------------------------------------------------
CREATE TABLE result_history (
    session_year SMALLINT     NOT NULL,
    matric_no    VARCHAR(20)  NOT NULL,
    course_code  VARCHAR(8)   NOT NULL,
    credit_units SMALLINT     NOT NULL,
    total_score  NUMERIC(4,1) NOT NULL CHECK (total_score BETWEEN 0 AND 100),
    grade        CHAR(1)      NOT NULL,
    PRIMARY KEY (session_year, matric_no, course_code)   -- must include the partition key
) PARTITION BY RANGE (session_year);

CREATE TABLE result_history_2019_2022 PARTITION OF result_history FOR VALUES FROM (2019) TO (2023);
CREATE TABLE result_history_2023      PARTITION OF result_history FOR VALUES FROM (2023) TO (2024);
CREATE TABLE result_history_2024      PARTITION OF result_history FOR VALUES FROM (2024) TO (2025);
CREATE TABLE result_history_2025      PARTITION OF result_history FOR VALUES FROM (2025) TO (2026);
CREATE TABLE result_history_2026      PARTITION OF result_history FOR VALUES FROM (2026) TO (2027);
CREATE TABLE result_history_default   PARTITION OF result_history DEFAULT;

-- 8 years x 10,000 students x 5 courses = 400,000 rows
SELECT setseed(0.5);
INSERT INTO result_history (session_year, matric_no, course_code, credit_units, total_score, grade)
SELECT y,
       format('CFU/%s/%s', 2019 + s % 8, lpad((s / 8 + 100)::text, 5, '0')),
       'CSC ' || (110 + c),
       3,
       sc,
       CASE WHEN sc >= 70 THEN 'A' WHEN sc >= 60 THEN 'B' WHEN sc >= 50 THEN 'C'
            WHEN sc >= 45 THEN 'D' WHEN sc >= 40 THEN 'E' ELSE 'F' END
FROM generate_series(2019, 2026) AS y
CROSS JOIN generate_series(0, 9999) AS s
CROSS JOIN generate_series(0, 4) AS c
-- "+ 0 * s" makes the subquery reference the outer row, so random() runs once per row
CROSS JOIN LATERAL (SELECT round((25 + random() * 75 + 0 * s)::numeric, 1) AS sc) AS r;
ANALYZE result_history;

\echo '--- Rows per partition ---'
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM result_history GROUP BY 1 ORDER BY 1;

\echo '--- Partition pruning: a query for ONE year touches ONE partition ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT grade, count(*) FROM result_history WHERE session_year = 2024 GROUP BY grade;

\echo '--- No partition key in WHERE: every partition is scanned ---'
EXPLAIN (COSTS OFF)
SELECT count(*) FROM result_history WHERE grade = 'F';

\echo '--- Archiving: DETACH the oldest partition (metadata-only, instant) ---'
ALTER TABLE result_history DETACH PARTITION result_history_2019_2022;
SELECT count(*) AS rows_still_in_main_table FROM result_history;
SELECT count(*) AS rows_in_archived_table   FROM result_history_2019_2022;
ALTER TABLE result_history ATTACH PARTITION result_history_2019_2022 FOR VALUES FROM (2019) TO (2023);
\echo '(re-attached for the rest of the demo)'

-- ---------------------------------------------------------------------
\echo '=== B. HASH partitioning: activity_log by student_id (shard simulation) ==='
-- ---------------------------------------------------------------------
CREATE TABLE activity_log (
    event_id    BIGSERIAL,
    student_id  INTEGER     NOT NULL,
    event_type  VARCHAR(20) NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (student_id, event_id)
) PARTITION BY HASH (student_id);

CREATE TABLE activity_log_shard0 PARTITION OF activity_log FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE activity_log_shard1 PARTITION OF activity_log FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE activity_log_shard2 PARTITION OF activity_log FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE activity_log_shard3 PARTITION OF activity_log FOR VALUES WITH (MODULUS 4, REMAINDER 3);

INSERT INTO activity_log (student_id, event_type, occurred_at)
SELECT 1 + (g * 7919) % 60000,
       (ARRAY['login', 'material_download', 'quiz_attempt', 'forum_post'])[1 + g % 4],
       now() - (g % 2000) * INTERVAL '1 hour'
FROM generate_series(1, 200000) AS g;
ANALYZE activity_log;

\echo '--- Even distribution across the 4 shards ---'
SELECT tableoid::regclass AS shard,
       count(*)                   AS events,
       count(DISTINCT student_id) AS students,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM activity_log GROUP BY 1 ORDER BY 1;

\echo '--- Single-student query is routed to ONE shard ---'
EXPLAIN (COSTS OFF)
SELECT * FROM activity_log WHERE student_id = 4242 ORDER BY occurred_at DESC LIMIT 20;

\echo '--- Cross-shard query (no shard key) must visit all shards ---'
EXPLAIN (COSTS OFF)
SELECT event_type, count(*) FROM activity_log GROUP BY event_type;
