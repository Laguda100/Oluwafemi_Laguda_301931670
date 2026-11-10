-- Session B: A second officer corrects an addition error: +2 to exam_score.
\ir common.sql
\if :{?fix}
\else
    \set fix false
\endif
\ir now.sql
\echo [B :now] reading exam_score
BEGIN;
\if :fix
SELECT exam_score AS score FROM result WHERE registration_id = :reg1 FOR UPDATE \gset
\else
SELECT exam_score AS score FROM result WHERE registration_id = :reg1 \gset
\endif
\ir now.sql
\echo [B :now] read exam_score = :score , will write :score + 2
UPDATE result SET exam_score = :score + 2 WHERE registration_id = :reg1;
COMMIT;
\ir now.sql
\echo [B :now] committed
