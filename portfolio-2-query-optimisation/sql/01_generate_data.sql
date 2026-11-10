-- =====================================================================
-- Portfolio 2 - Crestfield University Student Result Portal
-- File   : 01_generate_data.sql
-- Purpose: Scale the Portfolio 1 database up to a realistic size so
--          that execution plans and timings are meaningful:
--            8 academic sessions (2019/2020 - 2026/2027)
--            ~200 courses, ~1,550 course offerings, 120 extra lecturers
--            60,000 students, ~2.3 million registrations, ~2 million results
-- Run after Portfolio 1 scripts 01-03 (run.ps1 does this automatically).
-- Takes roughly 1-3 minutes depending on the machine.
-- =====================================================================

\timing on
SET synchronous_commit = off;   -- faster bulk load; safe for generated test data

BEGIN;

-- 1. Six historic sessions (2025/2026 and 2026/2027 already exist from Portfolio 1)
INSERT INTO academic_session (name, start_date, end_date, is_current)
SELECT y || '/' || (y + 1), make_date(y, 10, 1), make_date(y + 1, 9, 30), false
FROM generate_series(2019, 2024) AS y;

-- 2. 120 lecturers, 30 per department
INSERT INTO lecturer (lecturer_id, department_id, staff_no, title, first_name, last_name, email, academic_rank)
SELECT 7 + g,
       1 + g % 4,
       'STF/' || (2000 + g),
       (ARRAY['Dr.', 'Mr.', 'Mrs.', 'Prof.'])[1 + g % 4],
       (ARRAY['Bola','Kunle','Amaka','Sani','Uche','Hadiza','Segun','Nkechi','Femi','Halima'])[1 + g % 10],
       (ARRAY['Afolabi','Okeke','Danjuma','Oyelaran','Ibekwe','Suleiman'])[1 + (g / 10) % 6],
       'staff' || (2000 + g) || '@crestfield.edu.ng',
       (ARRAY['Assistant Lecturer','Lecturer II','Lecturer I','Senior Lecturer','Associate Professor','Professor'])[1 + g % 6]
FROM generate_series(0, 119) AS g;
SELECT setval(pg_get_serial_sequence('lecturer', 'lecturer_id'), (SELECT max(lecturer_id) FROM lecturer));

-- 3. 192 courses: 4 departments x 4 levels x 2 semesters x 6 courses.
--    Codes 110-115 (1st semester) and 120-125 (2nd semester) per level never
--    clash with the Portfolio 1 codes (101, 102, 201, 203).
INSERT INTO course (department_id, course_code, title, credit_units, course_level, semester)
SELECT d.department_id,
       d.code || ' ' || (lvl + 10 * sem + n),
       d.name || ' ' || (ARRAY['Foundations','Methods','Theory','Applications','Laboratory','Seminar'])[n + 1]
              || ' ' || (lvl / 100) || '.' || sem,
       CASE WHEN n = 5 THEN 2 ELSE 3 END,
       lvl,
       sem
FROM department d
CROSS JOIN generate_series(100, 400, 100) AS lvl
CROSS JOIN generate_series(1, 2)          AS sem
CROSS JOIN generate_series(0, 5)          AS n;

-- 4. Every generated course is offered in every session.
--    Lecturer chosen from the course's own department (lecturer_id 7..126).
INSERT INTO course_offering (course_id, session_id, lecturer_id, capacity)
SELECT c.course_id,
       s.session_id,
       7 + (c.department_id - 1) + 4 * ((c.course_id + s.session_id) % 30),
       5000
FROM course c
CROSS JOIN academic_session s
WHERE substr(c.course_code, 6, 1) IN ('1', '2');    -- generated courses only

-- 5. 60,000 students, 7,500 per entry year (2019-2026), spread over 4 programmes.
--    Matric serials start at 00100, so they never clash with Portfolio 1 (00001-00012).
INSERT INTO student (matric_no, programme_id, first_name, last_name, email,
                     date_of_birth, gender, entry_year, current_level, status)
SELECT format('CFU/%s/%s', ey, lpad((g / 8 + 100)::text, 5, '0')),
       1 + (g / 8) % 4,
       fn.first_name,
       ln.last_name,
       lower(fn.first_name || '.' || ln.last_name || '.' || g) || '@students.crestfield.edu.ng',
       make_date(ey - 18, 1 + g % 12, 1 + g % 28),
       fn.gender,
       ey,
       LEAST(2026 - ey + 1, 4) * 100,
       CASE WHEN ey <= 2022 THEN 'GRADUATED' ELSE 'ACTIVE' END
FROM generate_series(0, 59999) AS g
CROSS JOIN LATERAL (SELECT 2019 + g % 8 AS ey) AS e
CROSS JOIN LATERAL (
    SELECT (ARRAY['Ngozi','Tunde','Aisha','Emeka','Fatima','Seun','Chioma','Ibrahim','Funke','Obinna',
                  'Zainab','Femi','Adaeze','Musa','Bisi','Chinedu','Halima','Kayode','Amaka','Yusuf'])[1 + (g / 32) % 20] AS first_name,
           (ARRAY['F','M','F','M','F','M','F','M','F','M',
                  'F','M','F','M','F','M','F','M','F','M'])[1 + (g / 32) % 20] AS gender
) AS fn
CROSS JOIN LATERAL (
    SELECT (ARRAY['Okafor','Adeyemi','Bello','Eze','Ogunleye','Abubakar','Nwosu','Balogun','Ibrahim','Okonkwo',
                  'Adebayo','Usman','Chukwu','Olawale','Garba','Obi','Ajayi','Mohammed','Onyeka','Salami'])[1 + (g / 640) % 20] AS last_name
) AS ln;

-- 6. Registrations: each student takes all 12 courses of their department's level
--    in every session from entry year until 400 level (or the current session).
--    Portfolio 1 students (student_id 1-12) are left unchanged.
INSERT INTO registration (student_id, offering_id, registered_at)
SELECT s.student_id, o.offering_id, sess.start_date + 14
FROM student s
JOIN programme p           ON p.programme_id = s.programme_id
JOIN academic_session sess ON left(sess.name, 4)::int BETWEEN s.entry_year AND s.entry_year + 3
JOIN course c              ON c.department_id = p.department_id
                          AND c.course_level  = (left(sess.name, 4)::int - s.entry_year + 1) * 100
                          AND substr(c.course_code, 6, 1) IN ('1', '2')
JOIN course_offering o     ON o.course_id = c.course_id AND o.session_id = sess.session_id
WHERE s.student_id > 12;

-- 7. Results for every completed session. Scores use averaged random numbers so
--    they cluster around the middle (realistic bell shape, ~3% failures).
--    Row triggers are disabled for the bulk load (standard practice) and
--    re-enabled straight after, so the audit log is not flooded with 2M rows.
ALTER TABLE result DISABLE TRIGGER USER;
SELECT setseed(0.8103);
INSERT INTO result (registration_id, ca_score, exam_score, entered_by, entered_at)
SELECT reg.registration_id,
       8  + floor((random() + random()) / 2 * 22),             --  8..29
       15 + floor((random() + random() + random()) / 3 * 55),  -- 15..69
       o.lecturer_id,
       sess.start_date + 120
FROM registration reg
JOIN course_offering o     ON o.offering_id = reg.offering_id
JOIN academic_session sess ON sess.session_id = o.session_id
WHERE reg.student_id > 12
  AND NOT sess.is_current;
ALTER TABLE result ENABLE TRIGGER USER;

UPDATE course_offering o
SET result_status = 'APPROVED'
FROM academic_session s
WHERE s.session_id = o.session_id
  AND NOT s.is_current;

COMMIT;

-- Refresh planner statistics and the visibility map (needed for index-only scans).
VACUUM ANALYZE;

\echo '--- Data volume after generation ---'
SELECT relname AS table_name,
       n_live_tup AS approx_rows,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
