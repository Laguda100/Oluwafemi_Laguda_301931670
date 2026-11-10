-- =====================================================================
-- Portfolio 1 - Crestfield University Student Result Portal
-- File   : 05_verify.sql
-- Purpose: Show the schema works: table/row counts, a transcript,
--          semester GPA, CGPA ranking and the audit trail.
-- =====================================================================

\echo '--- 1. Row count per table ---'
SELECT 'faculty' AS table_name, count(*) FROM faculty
UNION ALL SELECT 'department',       count(*) FROM department
UNION ALL SELECT 'programme',        count(*) FROM programme
UNION ALL SELECT 'lecturer',         count(*) FROM lecturer
UNION ALL SELECT 'student',          count(*) FROM student
UNION ALL SELECT 'course',           count(*) FROM course
UNION ALL SELECT 'academic_session', count(*) FROM academic_session
UNION ALL SELECT 'course_offering',  count(*) FROM course_offering
UNION ALL SELECT 'registration',     count(*) FROM registration
UNION ALL SELECT 'result',           count(*) FROM result
UNION ALL SELECT 'grade_scale',      count(*) FROM grade_scale
UNION ALL SELECT 'result_audit',     count(*) FROM result_audit;

\echo '--- 2. Transcript for CFU/2025/00001 ---'
SELECT session_name, semester, course_code, course_title, credit_units,
       ca_score, exam_score, total_score, grade, grade_point, result_status
FROM v_student_result
WHERE matric_no = 'CFU/2025/00001'
ORDER BY session_name, semester, course_code;

\echo '--- 3. Semester GPA (approved results only) ---'
SELECT matric_no, student_name, session_name, semester,
       total_credit_units, total_quality_points, gpa
FROM v_semester_gpa
ORDER BY matric_no, session_name, semester;

\echo '--- 4. CGPA ranking and class of degree ---'
SELECT matric_no, student_name, total_credit_units, cgpa, class_of_degree
FROM v_cgpa
ORDER BY cgpa DESC, matric_no;

\echo '--- 5. Latest audit entries ---'
SELECT audit_id, registration_id, action, new_ca_score, new_exam_score, changed_by, changed_at
FROM result_audit
ORDER BY audit_id DESC
LIMIT 5;
