-- =====================================================================
-- Portfolio 2 - Crestfield University Student Result Portal
-- File   : 02_queries.sql
-- Purpose: Seven realistic workload queries for the result portal.
--
-- The same file is used three ways (psql variable EXPLAIN):
--   psql -f 02_queries.sql                                   -> shows results
--   psql -v EXPLAIN='EXPLAIN (ANALYZE, BUFFERS)' -f ...       -> shows plans + timings
-- run.ps1 runs it before and after indexing.
-- =====================================================================

\if :{?EXPLAIN}
\else
    \set EXPLAIN ''
\endif
\pset footer off

-- ---------------------------------------------------------------------
\echo '### Q1 Student transcript (multi-table JOIN through a view)'
-- Most frequent query in the portal: a student opens "My Results".
-- ---------------------------------------------------------------------
:EXPLAIN
SELECT session_name, semester, course_code, course_title, credit_units,
       ca_score, exam_score, total_score, grade, grade_point
FROM v_student_result
WHERE matric_no = 'CFU/2023/00450'
ORDER BY session_name, semester, course_code;

-- ---------------------------------------------------------------------
\echo '### Q2 Course result sheet (JOIN + LATERAL grade lookup)'
-- A lecturer / HOD prints the full result sheet for one course offering.
-- ---------------------------------------------------------------------
:EXPLAIN
SELECT s.matric_no,
       s.last_name || ', ' || s.first_name AS student,
       r.ca_score, r.exam_score, r.total_score, g.grade
FROM course c
JOIN course_offering o     ON o.course_id = c.course_id
JOIN academic_session sess ON sess.session_id = o.session_id
JOIN registration reg      ON reg.offering_id = o.offering_id
JOIN student s             ON s.student_id = reg.student_id
JOIN result r              ON r.registration_id = reg.registration_id
CROSS JOIN LATERAL (
    SELECT gs.grade FROM grade_scale gs
    WHERE gs.min_score <= r.total_score
    ORDER BY gs.min_score DESC LIMIT 1
) g
WHERE c.course_code = 'CSC 310'
  AND sess.name = '2024/2025'
ORDER BY s.matric_no
LIMIT 25;

-- ---------------------------------------------------------------------
\echo '### Q3 Departmental pass-rate report (GROUP BY + FILTER aggregates)'
-- Senate report: pass rate and average score per course for one department.
-- ---------------------------------------------------------------------
:EXPLAIN
SELECT c.course_code,
       count(*)                                          AS candidates,
       count(*) FILTER (WHERE r.total_score >= 40)       AS passed,
       round(100.0 * count(*) FILTER (WHERE r.total_score >= 40) / count(*), 1) AS pass_rate_pct,
       round(avg(r.total_score), 1)                      AS avg_score
FROM department d
JOIN course c              ON c.department_id = d.department_id
JOIN course_offering o     ON o.course_id = c.course_id
JOIN academic_session sess ON sess.session_id = o.session_id
JOIN registration reg      ON reg.offering_id = o.offering_id
JOIN result r              ON r.registration_id = reg.registration_id
WHERE d.code = 'CSC'
  AND sess.name = '2024/2025'
GROUP BY c.course_code
ORDER BY pass_rate_pct, c.course_code;

-- ---------------------------------------------------------------------
\echo '### Q4 Top 3 graduates per programme, 2022 cohort (CTE + window functions)'
-- Used to pick prize winners and to check the class-of-degree distribution.
-- ---------------------------------------------------------------------
:EXPLAIN
WITH cohort_cgpa AS (
    SELECT s.student_id,
           s.matric_no,
           p.code AS programme,
           round(sum(c.credit_units * gs.grade_point)::numeric / sum(c.credit_units), 2) AS cgpa
    FROM student s
    JOIN programme p       ON p.programme_id = s.programme_id
    JOIN registration reg  ON reg.student_id = s.student_id
    JOIN result r          ON r.registration_id = reg.registration_id
    JOIN course_offering o ON o.offering_id = reg.offering_id
    JOIN course c          ON c.course_id = o.course_id
    CROSS JOIN LATERAL (
        SELECT g.grade_point FROM grade_scale g
        WHERE g.min_score <= r.total_score
        ORDER BY g.min_score DESC LIMIT 1
    ) gs
    WHERE s.entry_year = 2022
    GROUP BY s.student_id, s.matric_no, p.code
),
ranked AS (
    SELECT *,
           rank()             OVER (PARTITION BY programme ORDER BY cgpa DESC) AS programme_rank,
           round(avg(cgpa)    OVER (PARTITION BY programme), 2)                AS programme_avg_cgpa,
           ntile(4)           OVER (PARTITION BY programme ORDER BY cgpa DESC) AS quartile
    FROM cohort_cgpa
)
SELECT programme, programme_rank, matric_no, cgpa, programme_avg_cgpa
FROM ranked
WHERE programme_rank <= 3
ORDER BY programme, programme_rank, matric_no;

-- ---------------------------------------------------------------------
\echo '### Q5 Carry-over list: students who failed courses in 2024/2025 (selective filter)'
-- Exams & Records sends carry-over notices; failures are only ~3% of results.
-- ---------------------------------------------------------------------
:EXPLAIN
SELECT s.matric_no,
       s.first_name || ' ' || s.last_name               AS student_name,
       count(*)                                         AS failed_courses,
       string_agg(c.course_code, ', ' ORDER BY c.course_code) AS carry_over_courses
FROM result r
JOIN registration reg      ON reg.registration_id = r.registration_id
JOIN student s             ON s.student_id = reg.student_id
JOIN course_offering o     ON o.offering_id = reg.offering_id
JOIN course c              ON c.course_id = o.course_id
JOIN academic_session sess ON sess.session_id = o.session_id
WHERE r.total_score < 40
  AND sess.name = '2024/2025'
GROUP BY s.student_id, s.matric_no, s.first_name, s.last_name
ORDER BY failed_courses DESC, s.matric_no
LIMIT 20;

-- ---------------------------------------------------------------------
\echo '### Q6 Students above the course average (CTE + scalar subquery)'
-- Lecturer wants the top performers in MTH 410 relative to the class mean.
-- ---------------------------------------------------------------------
:EXPLAIN
WITH target AS (
    SELECT o.offering_id
    FROM course_offering o
    JOIN course c              ON c.course_id = o.course_id
    JOIN academic_session sess ON sess.session_id = o.session_id
    WHERE c.course_code = 'MTH 410' AND sess.name = '2024/2025'
),
class_avg AS (
    SELECT avg(r.total_score) AS avg_score
    FROM registration reg
    JOIN result r ON r.registration_id = reg.registration_id
    WHERE reg.offering_id = (SELECT offering_id FROM target)
)
SELECT s.matric_no,
       r.total_score,
       round(ca.avg_score, 1)                 AS class_average,
       round(r.total_score - ca.avg_score, 1) AS above_average_by
FROM registration reg
JOIN result r     ON r.registration_id = reg.registration_id
JOIN student s    ON s.student_id = reg.student_id
CROSS JOIN class_avg ca
WHERE reg.offering_id = (SELECT offering_id FROM target)
  AND r.total_score > ca.avg_score
ORDER BY r.total_score DESC, s.matric_no
LIMIT 10;

-- ---------------------------------------------------------------------
\echo '### Q7 Case-insensitive student search by name (expression predicate)'
-- Help-desk staff search "ngozi okafor" without knowing the exact capitalisation.
-- ---------------------------------------------------------------------
:EXPLAIN
SELECT student_id, matric_no, first_name, last_name, entry_year, status
FROM student
WHERE lower(last_name) = 'okafor'
  AND lower(first_name) = 'ngozi'
ORDER BY matric_no
LIMIT 20;
