-- =====================================================================
-- Portfolio 3 - Crestfield University Student Result Portal
-- File   : 00_setup.sql
-- Purpose: Prepare a known starting state for the transaction and
--          concurrency demonstrations. Safe to run repeatedly; run.ps1
--          runs it before every demo so each demo starts identically.
-- Requires Portfolio 1 scripts 01-03 to have been run.
-- =====================================================================

-- 1. An elective with only ONE seat: used for the overbooking demos.
INSERT INTO course (department_id, course_code, title, credit_units, course_level, semester)
VALUES (1, 'CSC 205', 'Web Technologies (Elective)', 2, 200, 1)
ON CONFLICT (course_code) DO NOTHING;

INSERT INTO course_offering (course_id, session_id, lecturer_id, capacity)
SELECT c.course_id, s.session_id, 2, 1
FROM course c
CROSS JOIN academic_session s
WHERE c.course_code = 'CSC 205' AND s.is_current
ON CONFLICT ON CONSTRAINT uq_offering_course_session
DO UPDATE SET capacity = EXCLUDED.capacity;

DELETE FROM registration
WHERE offering_id IN (SELECT o.offering_id
                      FROM course_offering o
                      JOIN course c ON c.course_id = o.course_id
                      WHERE c.course_code = 'CSC 205');

-- 2. Reset the two CSC 203 results used in the score-update demos to 20 + 50.
UPDATE result
SET ca_score = 20, exam_score = 50
WHERE registration_id IN (
    SELECT reg.registration_id
    FROM registration reg
    JOIN student s         ON s.student_id = reg.student_id
    JOIN course_offering o ON o.offering_id = reg.offering_id
    JOIN course c          ON c.course_id = o.course_id
    WHERE c.course_code = 'CSC 203'
      AND s.matric_no IN ('CFU/2025/00001', 'CFU/2025/00002'));

-- 3. Concurrency-safe course registration.
--    The FOR UPDATE row lock on the course offering makes concurrent
--    registrations for the SAME course queue up, so the seat count can
--    never be read by two transactions at once (prevents overbooking).
--    The FOR NO KEY UPDATE lock on the student row serialises one student's
--    own concurrent registrations (prevents exceeding the 24-unit limit).
--    Locks are always taken in the same order (offering, then student),
--    so this function cannot deadlock with itself.
CREATE OR REPLACE FUNCTION register_course(p_student_id INTEGER, p_offering_id INTEGER)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    c_max_units CONSTANT INTEGER := 24;
    v_capacity  SMALLINT;
    v_session   SMALLINT;
    v_semester  SMALLINT;
    v_units     SMALLINT;
    v_taken     INTEGER;
    v_current   INTEGER;
    v_reg_id    BIGINT;
BEGIN
    SELECT o.capacity, o.session_id, c.semester, c.credit_units
      INTO v_capacity, v_session, v_semester, v_units
    FROM course_offering o
    JOIN course c ON c.course_id = o.course_id
    WHERE o.offering_id = p_offering_id
    FOR UPDATE OF o;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Course offering % does not exist', p_offering_id;
    END IF;

    PERFORM 1 FROM student WHERE student_id = p_student_id FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student % does not exist', p_student_id;
    END IF;

    SELECT count(*) INTO v_taken
    FROM registration
    WHERE offering_id = p_offering_id AND status = 'REGISTERED';

    IF v_taken >= v_capacity THEN
        RAISE EXCEPTION 'Course offering % is full (% of % seats taken)',
              p_offering_id, v_taken, v_capacity;
    END IF;

    SELECT COALESCE(sum(c.credit_units), 0) INTO v_current
    FROM registration r
    JOIN course_offering o ON o.offering_id = r.offering_id
    JOIN course c          ON c.course_id = o.course_id
    WHERE r.student_id = p_student_id
      AND r.status = 'REGISTERED'
      AND o.session_id = v_session
      AND c.semester = v_semester;

    IF v_current + v_units > c_max_units THEN
        RAISE EXCEPTION 'Credit limit exceeded: % + % > % units', v_current, v_units, c_max_units;
    END IF;

    INSERT INTO registration (student_id, offering_id)
    VALUES (p_student_id, p_offering_id)
    RETURNING registration_id INTO v_reg_id;

    RETURN v_reg_id;
END;
$$;
