-- Session B: a lecturer updates the same score (+10) and commits (autocommit).
\ir common.sql
UPDATE result SET exam_score = exam_score + 10 WHERE registration_id = :reg1;
\ir now.sql
\echo [B :now] exam_score +10 committed
