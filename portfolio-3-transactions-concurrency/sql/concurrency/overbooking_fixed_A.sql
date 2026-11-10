-- Session A: registers student 9 through register_course(), which locks the offering row.
\ir common.sql
BEGIN;
SELECT register_course(9, :off) AS reg_id \gset
\ir now.sql
\echo [A :now] register_course(9) OK, registration_id = :reg_id , offering row is now locked
SELECT pg_sleep(3) \gset
COMMIT;
\ir now.sql
\echo [A :now] committed, lock released
