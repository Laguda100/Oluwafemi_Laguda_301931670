-- Session A: moderates student 00001 then student 00002 (+1 each).
-- fix=true: both rows are locked up front in a consistent order (ORDER BY id).
\ir common.sql
\if :{?fix}
\else
    \set fix false
\endif
BEGIN;
\if :fix
SELECT registration_id FROM result WHERE registration_id IN (:reg1, :reg2)
ORDER BY registration_id FOR UPDATE;
\endif
UPDATE result SET exam_score = exam_score + 1 WHERE registration_id = :reg1;
\ir now.sql
\echo [A :now] updated 00001, sleeping before updating 00002
SELECT pg_sleep(3) \gset
UPDATE result SET exam_score = exam_score + 1 WHERE registration_id = :reg2;
\ir now.sql
\echo [A :now] updated 00002, committing
COMMIT;
