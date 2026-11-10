-- =====================================================================
-- Portfolio 4 - relational -> document migration
-- File   : export_students.sql   (run on PostgreSQL with psql -At)
-- Purpose: Build ONE JSON document per student, containing the profile,
--          denormalised programme details and the full APPROVED transcript
--          (sessions -> semesters -> courses). Output is NDJSON (one
--          document per line), which 02_load_students.js imports into MongoDB.
-- The 6-table join in v_student_result is done ONCE here, at export
-- time, instead of on every transcript read.
-- =====================================================================

SELECT jsonb_build_object(
    '_id',           s.matric_no,
    'name',          jsonb_build_object('first', s.first_name, 'last', s.last_name, 'other', s.other_names),
    'email',         s.email,
    'gender',        s.gender,
    'dateOfBirth',   s.date_of_birth,
    'entryYear',     s.entry_year,
    'currentLevel',  s.current_level,
    'status',        s.status,
    'programme',     jsonb_build_object('code', p.code, 'name', p.name,
                                        'department', d.name, 'faculty', f.name),
    'transcript',    COALESCE(t.transcript, '[]'::jsonb),
    'cgpa',          cg.cgpa,
    'classOfDegree', cg.class_of_degree
)
FROM student s
JOIN programme p  ON p.programme_id = s.programme_id
JOIN department d ON d.department_id = p.department_id
JOIN faculty f    ON f.faculty_id = d.faculty_id
LEFT JOIN v_cgpa cg ON cg.student_id = s.student_id
LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object('session',  sem.session_name,
                                        'semester', sem.semester,
                                        'gpa',      sem.gpa,
                                        'courses',  sem.courses)
                     ORDER BY sem.session_name, sem.semester) AS transcript
    FROM (
        SELECT vr.session_name,
               vr.semester,
               round(sum(vr.quality_points)::numeric / sum(vr.credit_units), 2) AS gpa,
               jsonb_agg(jsonb_build_object('code',       vr.course_code,
                                            'title',      vr.course_title,
                                            'units',      vr.credit_units,
                                            'ca',         vr.ca_score,
                                            'exam',       vr.exam_score,
                                            'total',      vr.total_score,
                                            'grade',      vr.grade,
                                            'gradePoint', vr.grade_point)
                         ORDER BY vr.course_code) AS courses
        FROM v_student_result vr
        WHERE vr.student_id = s.student_id
          AND vr.result_status = 'APPROVED'
        GROUP BY vr.session_name, vr.semester
    ) sem
) t ON true
WHERE s.student_id <= 12          -- the Portfolio 1 students
ORDER BY s.matric_no;
