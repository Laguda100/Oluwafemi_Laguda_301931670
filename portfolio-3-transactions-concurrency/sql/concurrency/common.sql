-- Shared lookups for the two-session demos (sets psql variables).
--   :reg1  registration of CFU/2025/00001 in CSC 203 (2026/2027, results OPEN)
--   :reg2  registration of CFU/2025/00002 in CSC 203
--   :off   the CSC 205 elective offering (capacity 1)
SELECT reg.registration_id AS reg1
FROM registration reg
JOIN student s         ON s.student_id = reg.student_id
JOIN course_offering o ON o.offering_id = reg.offering_id
JOIN course c          ON c.course_id = o.course_id
WHERE s.matric_no = 'CFU/2025/00001' AND c.course_code = 'CSC 203' \gset
SELECT reg.registration_id AS reg2
FROM registration reg
JOIN student s         ON s.student_id = reg.student_id
JOIN course_offering o ON o.offering_id = reg.offering_id
JOIN course c          ON c.course_id = o.course_id
WHERE s.matric_no = 'CFU/2025/00002' AND c.course_code = 'CSC 203' \gset
SELECT o.offering_id AS off
FROM course_offering o
JOIN course c ON c.course_id = o.course_id
WHERE c.course_code = 'CSC 205' \gset
