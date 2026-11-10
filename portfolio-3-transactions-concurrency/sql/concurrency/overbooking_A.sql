-- Session A: application checks for a free seat in CSC 205, then registers student 9.
-- serializable=false: READ COMMITTED -> both sessions see a free seat (overbooking)
-- serializable=true : SERIALIZABLE   -> PostgreSQL aborts one transaction (SQLSTATE 40001)
\ir common.sql
\if :{?serializable}
\else
    \set serializable false
\endif
\if :serializable
BEGIN ISOLATION LEVEL SERIALIZABLE;
\else
BEGIN ISOLATION LEVEL READ COMMITTED;
\endif
SELECT count(*) AS taken FROM registration WHERE offering_id = :off AND status = 'REGISTERED' \gset
SELECT capacity AS cap FROM course_offering WHERE offering_id = :off \gset
\ir now.sql
\echo [A :now] seats taken :taken of :cap , seat is free, registering student 9
SELECT pg_sleep(3) \gset
INSERT INTO registration (student_id, offering_id) VALUES (9, :off);
COMMIT;
\ir now.sql
\echo [A :now] finished
