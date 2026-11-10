-- Final state after a demo.
\ir common.sql
\pset footer off
SELECT s.matric_no, r.exam_score
FROM result r
JOIN registration reg ON reg.registration_id = r.registration_id
JOIN student s        ON s.student_id = reg.student_id
WHERE r.registration_id IN (:reg1, :reg2)
ORDER BY s.matric_no;
SELECT count(reg.registration_id) AS csc205_registered, max(o.capacity) AS csc205_capacity
FROM course_offering o
LEFT JOIN registration reg ON reg.offering_id = o.offering_id AND reg.status = 'REGISTERED'
WHERE o.offering_id = :off;
