-- Session B: tries to register student 10 for the same last seat at the same time.
\ir common.sql
\ir now.sql
\echo [B :now] calling register_course(10), waits for the lock held by A
BEGIN;
SELECT register_course(10, :off);
\ir now.sql
\echo [B :now] register_course returned (the error above shows the course was full)
COMMIT;
