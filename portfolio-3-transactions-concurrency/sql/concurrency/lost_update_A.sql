-- Session A: Exams officer applies a +5 moderation to exam_score.
-- fix=false: application reads, computes, writes (read-modify-write)  -> lost update
-- fix=true : SELECT ... FOR UPDATE locks the row before reading       -> safe
\ir common.sql
\if :{?fix}
\else
    \set fix false
\endif
BEGIN;
\if :fix
SELECT exam_score AS score FROM result WHERE registration_id = :reg1 FOR UPDATE \gset
\else
SELECT exam_score AS score FROM result WHERE registration_id = :reg1 \gset
\endif
\ir now.sql
\echo [A :now] read exam_score = :score , will write :score + 5
SELECT pg_sleep(3) \gset
UPDATE result SET exam_score = :score + 5 WHERE registration_id = :reg1;
COMMIT;
\ir now.sql
\echo [A :now] committed
