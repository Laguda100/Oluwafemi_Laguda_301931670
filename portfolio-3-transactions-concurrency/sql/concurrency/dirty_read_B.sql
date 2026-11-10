-- Session B (reader): asks for READ UNCOMMITTED while A's change is still pending.
\ir common.sql
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
SHOW transaction_isolation;
SELECT exam_score AS seen FROM result WHERE registration_id = :reg1 \gset
\ir now.sql
\echo [B :now] reader sees exam_score = :seen   (50 means no dirty read, 69 would be a dirty read)
COMMIT;
