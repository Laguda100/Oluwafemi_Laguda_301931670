-- =====================================================================
-- Portfolio 2 - Crestfield University Student Result Portal
-- File   : 03_indexes.sql
-- Purpose: Indexing strategy. Each index targets a specific query in
--          02_queries.sql (see the README for the reasoning).
-- =====================================================================

\timing on

-- I1  Foreign-key index + covering columns (Q1, Q4).
--     PostgreSQL does NOT index foreign keys automatically. INCLUDE stores
--     offering_id and status in the index leaf, intended to allow an
--     index-only scan.
--     MEASURED RESULT: redundant. uq_registration_student_offering
--     (student_id, offering_id) already serves Q1, and Q1 also needs
--     registration_id, which is not included. Kept so the before/after
--     comparison stays reproducible; see the README, section 4.
CREATE INDEX IF NOT EXISTS ix_registration_student
    ON registration (student_id) INCLUDE (offering_id, status);

-- I2  Foreign-key index (Q2, Q3, Q6): all students in one course offering.
CREATE INDEX IF NOT EXISTS ix_registration_offering
    ON registration (offering_id);

-- I3  Partial index (Q5): only failed results (~3% of rows) are indexed,
--     so the index is tiny and the query never scans passing results.
CREATE INDEX IF NOT EXISTS ix_result_failed
    ON result (registration_id) WHERE total_score < 40;

-- I4  Expression index (Q7): matches lower(last_name)/lower(first_name).
--     A plain index on last_name could not be used for lower(last_name).
CREATE INDEX IF NOT EXISTS ix_student_lower_name
    ON student (lower(last_name), lower(first_name));

-- I5  Cohort filter (Q4): students of one entry year (1/8 of the table).
CREATE INDEX IF NOT EXISTS ix_student_entry_year
    ON student (entry_year);

ANALYZE registration;
ANALYZE result;
ANALYZE student;

\echo '--- Index sizes (cost of the strategy) ---'
SELECT c.relname                                  AS index_name,
       t.relname                                  AS table_name,
       pg_size_pretty(pg_relation_size(c.oid))    AS index_size
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_class t ON t.oid = i.indrelid
WHERE c.relname LIKE 'ix_%'
ORDER BY pg_relation_size(c.oid) DESC;
