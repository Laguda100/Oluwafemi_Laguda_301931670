-- Session A (writer): changes a score to 69 but does NOT commit, then rolls back.
\ir common.sql
BEGIN;
UPDATE result SET exam_score = 69 WHERE registration_id = :reg1;
\ir now.sql
\echo [A :now] exam_score set to 69 (uncommitted)
SELECT pg_sleep(3) \gset
ROLLBACK;
\ir now.sql
\echo [A :now] rolled back
