-- =====================================================================
-- Portfolio 1 - Crestfield University Student Result Portal
-- File   : 02_seed.sql
-- Purpose: Small, realistic sample data (2 sessions, 12 students).
--          Large-volume data for performance testing is generated in
--          Portfolio 2.
-- Run after 01_schema.sql.
-- =====================================================================

BEGIN;

INSERT INTO grade_scale (grade, min_score, grade_point) VALUES
    ('A', 70, 5),
    ('B', 60, 4),
    ('C', 50, 3),
    ('D', 45, 2),
    ('E', 40, 1),
    ('F',  0, 0);

INSERT INTO faculty (faculty_id, code, name) VALUES
    (1, 'SCI', 'Faculty of Computing and Applied Sciences'),
    (2, 'MSS', 'Faculty of Management and Social Sciences');

INSERT INTO department (department_id, faculty_id, code, name) VALUES
    (1, 1, 'CSC', 'Computer Science'),
    (2, 1, 'MTH', 'Mathematics'),
    (3, 2, 'ACC', 'Accounting'),
    (4, 2, 'ECO', 'Economics');

INSERT INTO programme (programme_id, department_id, code, name, degree_type, duration_years) VALUES
    (1, 1, 'BSC-CSC', 'B.Sc. Computer Science', 'BSc', 4),
    (2, 2, 'BSC-MTH', 'B.Sc. Mathematics',      'BSc', 4),
    (3, 3, 'BSC-ACC', 'B.Sc. Accounting',       'BSc', 4),
    (4, 4, 'BSC-ECO', 'B.Sc. Economics',        'BSc', 4);

INSERT INTO lecturer (lecturer_id, department_id, staff_no, title, first_name, last_name, email, academic_rank) VALUES
    (1, 1, 'STF/1001', 'Dr.',   'Adebayo',   'Ogunleye', 'a.ogunleye@crestfield.edu.ng', 'Senior Lecturer'),
    (2, 1, 'STF/1002', 'Dr.',   'Chiamaka',  'Eze',      'c.eze@crestfield.edu.ng',      'Lecturer I'),
    (3, 2, 'STF/1003', 'Prof.', 'Ibrahim',   'Musa',     'i.musa@crestfield.edu.ng',     'Professor'),
    (4, 3, 'STF/1004', 'Mrs.',  'Funmilayo', 'Adeyemi',  'f.adeyemi@crestfield.edu.ng',  'Lecturer II'),
    (5, 4, 'STF/1005', 'Dr.',   'Emeka',     'Nwosu',    'e.nwosu@crestfield.edu.ng',    'Associate Professor'),
    (6, 2, 'STF/1006', 'Mr.',   'Tunde',     'Bakare',   't.bakare@crestfield.edu.ng',   'Assistant Lecturer');

INSERT INTO student (student_id, matric_no, programme_id, first_name, last_name, other_names,
                     email, date_of_birth, gender, entry_year, current_level) VALUES
    ( 1, 'CFU/2025/00001', 1, 'Oluwaseun', 'Adeleke',  'Tobi',    'oluwaseun.adeleke@students.crestfield.edu.ng', '2006-03-14', 'M', 2025, 200),
    ( 2, 'CFU/2025/00002', 1, 'Ngozi',     'Okafor',   NULL,      'ngozi.okafor@students.crestfield.edu.ng',      '2005-11-02', 'F', 2025, 200),
    ( 3, 'CFU/2025/00003', 1, 'Musa',      'Abdullahi',NULL,      'musa.abdullahi@students.crestfield.edu.ng',    '2006-07-21', 'M', 2025, 200),
    ( 4, 'CFU/2025/00004', 1, 'Aisha',     'Bello',    'Hauwa',   'aisha.bello@students.crestfield.edu.ng',       '2006-01-30', 'F', 2025, 200),
    ( 5, 'CFU/2025/00005', 2, 'Chukwuemeka','Obi',     NULL,      'chukwuemeka.obi@students.crestfield.edu.ng',   '2005-09-09', 'M', 2025, 200),
    ( 6, 'CFU/2025/00006', 2, 'Temitope',  'Ajayi',    NULL,      'temitope.ajayi@students.crestfield.edu.ng',    '2006-05-17', 'F', 2025, 200),
    ( 7, 'CFU/2025/00007', 2, 'Ifeanyi',   'Nnamdi',   'Chidi',   'ifeanyi.nnamdi@students.crestfield.edu.ng',    '2005-12-25', 'M', 2025, 200),
    ( 8, 'CFU/2025/00008', 3, 'Blessing',  'Etim',     NULL,      'blessing.etim@students.crestfield.edu.ng',     '2006-02-11', 'F', 2025, 200),
    ( 9, 'CFU/2025/00009', 3, 'Yusuf',     'Garba',    NULL,      'yusuf.garba@students.crestfield.edu.ng',       '2005-08-04', 'M', 2025, 200),
    (10, 'CFU/2025/00010', 3, 'Folake',    'Ogundipe', 'Bisola',  'folake.ogundipe@students.crestfield.edu.ng',   '2006-04-28', 'F', 2025, 200),
    (11, 'CFU/2025/00011', 4, 'Kelechi',   'Uche',     NULL,      'kelechi.uche@students.crestfield.edu.ng',      '2006-10-19', 'M', 2025, 200),
    (12, 'CFU/2025/00012', 4, 'Zainab',    'Lawal',    NULL,      'zainab.lawal@students.crestfield.edu.ng',      '2005-06-06', 'F', 2025, 200);

INSERT INTO course (course_id, department_id, course_code, title, credit_units, course_level, semester) VALUES
    ( 1, 1, 'CSC 101', 'Introduction to Computing Sciences', 3, 100, 1),
    ( 2, 1, 'CSC 102', 'Introduction to Programming',        3, 100, 2),
    ( 3, 2, 'MTH 101', 'Elementary Mathematics I',           3, 100, 1),
    ( 4, 2, 'MTH 102', 'Elementary Mathematics II',          3, 100, 2),
    ( 5, 3, 'ACC 101', 'Principles of Accounting I',         3, 100, 1),
    ( 6, 4, 'ECO 101', 'Principles of Economics I',          2, 100, 1),
    ( 7, 1, 'CSC 201', 'Data Structures and Algorithms',     3, 200, 1),
    ( 8, 1, 'CSC 203', 'Database Systems I',                 3, 200, 1),
    ( 9, 2, 'MTH 201', 'Linear Algebra I',                   3, 200, 1),
    (10, 3, 'ACC 201', 'Financial Accounting I',             3, 200, 1),
    (11, 4, 'ECO 201', 'Microeconomic Theory I',             3, 200, 1);

INSERT INTO academic_session (session_id, name, start_date, end_date, is_current) VALUES
    (1, '2025/2026', '2025-10-06', '2026-09-30', false),
    (2, '2026/2027', '2026-10-05', '2027-09-30', true);

INSERT INTO course_offering (offering_id, course_id, session_id, lecturer_id, capacity) VALUES
    -- 2025/2026 (100 level)
    ( 1,  1, 1, 1, 150),
    ( 2,  2, 1, 2, 150),
    ( 3,  3, 1, 3, 300),
    ( 4,  4, 1, 6, 300),
    ( 5,  5, 1, 4, 150),
    ( 6,  6, 1, 5, 150),
    -- 2026/2027 (200 level, first semester)
    ( 7,  7, 2, 1, 120),
    ( 8,  8, 2, 2, 120),
    ( 9,  9, 2, 3, 200),
    (10, 10, 2, 4, 120),
    (11, 11, 2, 5, 120);

-- Keep identity sequences in step with the explicit IDs above.
SELECT setval(pg_get_serial_sequence('faculty',          'faculty_id'),    (SELECT max(faculty_id)    FROM faculty));
SELECT setval(pg_get_serial_sequence('department',       'department_id'), (SELECT max(department_id) FROM department));
SELECT setval(pg_get_serial_sequence('programme',        'programme_id'),  (SELECT max(programme_id)  FROM programme));
SELECT setval(pg_get_serial_sequence('lecturer',         'lecturer_id'),   (SELECT max(lecturer_id)   FROM lecturer));
SELECT setval(pg_get_serial_sequence('student',          'student_id'),    (SELECT max(student_id)    FROM student));
SELECT setval(pg_get_serial_sequence('course',           'course_id'),     (SELECT max(course_id)     FROM course));
SELECT setval(pg_get_serial_sequence('academic_session', 'session_id'),    (SELECT max(session_id)    FROM academic_session));
SELECT setval(pg_get_serial_sequence('course_offering',  'offering_id'),   (SELECT max(offering_id)   FROM course_offering));

-- Registrations: each programme's curriculum, mapped by course code.
INSERT INTO registration (student_id, offering_id, registered_at)
SELECT s.student_id, o.offering_id, sess.start_date + INTERVAL '14 days'
FROM student s
JOIN programme p ON p.programme_id = s.programme_id
JOIN (VALUES
        ('BSC-CSC', 'CSC 101'), ('BSC-CSC', 'CSC 102'), ('BSC-CSC', 'MTH 101'), ('BSC-CSC', 'MTH 102'),
        ('BSC-CSC', 'CSC 201'), ('BSC-CSC', 'CSC 203'), ('BSC-CSC', 'MTH 201'),
        ('BSC-MTH', 'MTH 101'), ('BSC-MTH', 'MTH 102'), ('BSC-MTH', 'CSC 101'),
        ('BSC-MTH', 'MTH 201'), ('BSC-MTH', 'CSC 203'),
        ('BSC-ACC', 'ACC 101'), ('BSC-ACC', 'ECO 101'), ('BSC-ACC', 'MTH 101'),
        ('BSC-ACC', 'ACC 201'), ('BSC-ACC', 'ECO 201'),
        ('BSC-ECO', 'ECO 101'), ('BSC-ECO', 'ACC 101'), ('BSC-ECO', 'MTH 101'),
        ('BSC-ECO', 'ECO 201'), ('BSC-ECO', 'ACC 201')
     ) AS curriculum (programme_code, course_code) ON curriculum.programme_code = p.code
JOIN course c            ON c.course_code = curriculum.course_code
JOIN course_offering o   ON o.course_id = c.course_id
JOIN academic_session sess ON sess.session_id = o.session_id;

-- Results: all 2025/2026 courses, plus CSC 203 in 2026/2027 (still OPEN).
-- Scores are deterministic so every run produces the same data.
INSERT INTO result (registration_id, ca_score, exam_score, entered_by, entered_at)
SELECT reg.registration_id,
       14 + (reg.student_id * 7  + c.course_id * 3) % 16,   -- CA   14..29
       22 + (reg.student_id * 11 + c.course_id * 5) % 46,   -- Exam 22..67
       o.lecturer_id,
       sess.start_date + INTERVAL '120 days'
FROM registration reg
JOIN course_offering o     ON o.offering_id = reg.offering_id
JOIN course c              ON c.course_id = o.course_id
JOIN academic_session sess ON sess.session_id = o.session_id
WHERE sess.name = '2025/2026'
   OR c.course_code = 'CSC 203';

-- 2025/2026 results have been approved by Senate, so they are now locked.
UPDATE course_offering
SET result_status = 'APPROVED'
WHERE session_id = (SELECT session_id FROM academic_session WHERE name = '2025/2026');

COMMIT;
