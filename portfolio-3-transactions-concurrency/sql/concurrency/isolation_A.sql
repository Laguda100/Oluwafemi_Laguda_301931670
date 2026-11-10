-- Session A: a transcript report reads the same score twice in one transaction.
-- rr=false: READ COMMITTED  -> second read sees B's committed change (non-repeatable read)
-- rr=true : REPEATABLE READ -> both reads come from the same snapshot
\ir common.sql
\if :{?rr}
\else
    \set rr false
\endif
\if :rr
BEGIN ISOLATION LEVEL REPEATABLE READ;
\else
BEGIN ISOLATION LEVEL READ COMMITTED;
\endif
SHOW transaction_isolation;
SELECT exam_score AS first_read FROM result WHERE registration_id = :reg1 \gset
\ir now.sql
\echo [A :now] first read  = :first_read
SELECT pg_sleep(3) \gset
SELECT exam_score AS second_read FROM result WHERE registration_id = :reg1 \gset
\ir now.sql
\echo [A :now] second read = :second_read
COMMIT;
