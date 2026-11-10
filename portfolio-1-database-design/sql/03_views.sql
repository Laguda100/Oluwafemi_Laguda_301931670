-- =====================================================================
-- Portfolio 1 - Crestfield University Student Result Portal
-- File   : 03_views.sql
-- Purpose: Derived information (grade, grade point, GPA, CGPA, class of
--          degree) is computed by views instead of being stored, so it can
--          never disagree with the underlying scores (no update anomalies).
-- =====================================================================

DROP VIEW IF EXISTS v_cgpa, v_semester_gpa, v_student_result CASCADE;

-- One row per student per course, with the grade looked up from grade_scale.
CREATE VIEW v_student_result AS
SELECT s.student_id,
       s.matric_no,
       s.first_name || ' ' || s.last_name AS student_name,
       sess.name                           AS session_name,
       c.semester,
       c.course_code,
       c.title                             AS course_title,
       c.credit_units,
       r.ca_score,
       r.exam_score,
       r.total_score,
       g.grade,
       g.grade_point,
       c.credit_units * g.grade_point      AS quality_points,
       o.result_status
FROM result r
JOIN registration reg      ON reg.registration_id = r.registration_id
JOIN student s             ON s.student_id = reg.student_id
JOIN course_offering o     ON o.offering_id = reg.offering_id
JOIN course c              ON c.course_id = o.course_id
JOIN academic_session sess ON sess.session_id = o.session_id
CROSS JOIN LATERAL (
    SELECT gs.grade, gs.grade_point
    FROM grade_scale gs
    WHERE gs.min_score <= r.total_score
    ORDER BY gs.min_score DESC
    LIMIT 1
) g
WHERE reg.status = 'REGISTERED';

-- GPA per student per semester (only Senate-approved results count).
CREATE VIEW v_semester_gpa AS
SELECT student_id,
       matric_no,
       student_name,
       session_name,
       semester,
       SUM(credit_units)   AS total_credit_units,
       SUM(quality_points) AS total_quality_points,
       ROUND(SUM(quality_points)::numeric / SUM(credit_units), 2) AS gpa
FROM v_student_result
WHERE result_status = 'APPROVED'
GROUP BY student_id, matric_no, student_name, session_name, semester;

-- Cumulative GPA and class of degree (5-point scale).
CREATE VIEW v_cgpa AS
SELECT student_id,
       matric_no,
       student_name,
       total_credit_units,
       cgpa,
       CASE
           WHEN cgpa >= 4.50 THEN 'First Class'
           WHEN cgpa >= 3.50 THEN 'Second Class Upper'
           WHEN cgpa >= 2.40 THEN 'Second Class Lower'
           WHEN cgpa >= 1.50 THEN 'Third Class'
           WHEN cgpa >= 1.00 THEN 'Pass'
           ELSE 'Fail'
       END AS class_of_degree
FROM (
    SELECT student_id,
           matric_no,
           student_name,
           SUM(credit_units) AS total_credit_units,
           ROUND(SUM(quality_points)::numeric / SUM(credit_units), 2) AS cgpa
    FROM v_student_result
    WHERE result_status = 'APPROVED'
    GROUP BY student_id, matric_no, student_name
) t;
