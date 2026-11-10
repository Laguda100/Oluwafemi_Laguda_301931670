-- Session B: same check-then-insert for student 10, a moment later.
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
\echo [B :now] seats taken :taken of :cap , seat is free, registering student 10
INSERT INTO registration (student_id, offering_id) VALUES (10, :off);
COMMIT;
\ir now.sql
\echo [B :now] finished
