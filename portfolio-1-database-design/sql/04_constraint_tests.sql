-- =====================================================================
-- Portfolio 1 - Crestfield University Student Result Portal
-- File   : 04_constraint_tests.sql
-- Purpose: Prove that the constraints and triggers reject invalid data.
--          Each test runs in its own sub-block, so a failed statement is
--          rolled back and the next test still runs.
--          Expected output: every line starts with "PASS".
-- =====================================================================

DO $$
DECLARE
    v_open_reg     BIGINT;   -- a registration with no result yet (offering OPEN)
    v_approved_reg BIGINT;   -- a registration whose result is APPROVED
BEGIN
    SELECT reg.registration_id INTO v_open_reg
    FROM registration reg
    LEFT JOIN result r ON r.registration_id = reg.registration_id
    WHERE r.registration_id IS NULL
    ORDER BY reg.registration_id
    LIMIT 1;

    SELECT r.registration_id INTO v_approved_reg
    FROM result r
    JOIN registration reg  ON reg.registration_id = r.registration_id
    JOIN course_offering o ON o.offering_id = reg.offering_id
    WHERE o.result_status = 'APPROVED'
    ORDER BY r.registration_id
    LIMIT 1;

    -- T1: CHECK constraint - exam score is out of 70
    BEGIN
        INSERT INTO result (registration_id, ca_score, exam_score, entered_by)
        VALUES (v_open_reg, 20, 85, 1);
        RAISE NOTICE 'T1 FAIL: exam score 85 was accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'T1 PASS: exam score > 70 rejected  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T2: UNIQUE - a student cannot register for the same offering twice
    BEGIN
        INSERT INTO registration (student_id, offering_id)
        SELECT student_id, offering_id FROM registration WHERE registration_id = v_open_reg;
        RAISE NOTICE 'T2 FAIL: duplicate registration accepted';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'T2 PASS: duplicate registration rejected  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T3: CHECK - matric number must follow CFU/YYYY/NNNNN
    BEGIN
        INSERT INTO student (matric_no, programme_id, first_name, last_name, email,
                             date_of_birth, gender, entry_year)
        VALUES ('CFU-2025-1', 1, 'Test', 'Student', 'test.student@students.crestfield.edu.ng',
                '2006-01-01', 'M', 2025);
        RAISE NOTICE 'T3 FAIL: invalid matric number accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'T3 PASS: invalid matric number rejected  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T4: FOREIGN KEY - cannot register a student who does not exist
    BEGIN
        INSERT INTO registration (student_id, offering_id) VALUES (999999, 7);
        RAISE NOTICE 'T4 FAIL: registration for unknown student accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'T4 PASS: unknown student rejected  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T5: PARTIAL UNIQUE INDEX - only one current academic session
    BEGIN
        UPDATE academic_session SET is_current = true WHERE name = '2025/2026';
        RAISE NOTICE 'T5 FAIL: two current sessions allowed';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'T5 PASS: second current session rejected  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T6: TRIGGER - approved results are locked
    BEGIN
        UPDATE result SET exam_score = 70 WHERE registration_id = v_approved_reg;
        RAISE NOTICE 'T6 FAIL: approved result was modified';
    EXCEPTION WHEN raise_exception THEN
        RAISE NOTICE 'T6 PASS: approved result is locked  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T7: FOREIGN KEY (RESTRICT) - cannot delete a department that still has programmes
    BEGIN
        DELETE FROM department WHERE code = 'CSC';
        RAISE NOTICE 'T7 FAIL: department with programmes was deleted';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'T7 PASS: department delete blocked  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T8: GENERATED COLUMN - total_score cannot be written directly
    BEGIN
        INSERT INTO result (registration_id, ca_score, exam_score, total_score, entered_by)
        VALUES (v_open_reg, 20, 50, 99, 1);
        RAISE NOTICE 'T8 FAIL: total_score was written directly';
    EXCEPTION WHEN generated_always THEN
        RAISE NOTICE 'T8 PASS: total_score is system-computed  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T9: NOT NULL - a lecturer must belong to a department
    BEGIN
        INSERT INTO lecturer (staff_no, first_name, last_name, email, academic_rank)
        VALUES ('STF/9999', 'No', 'Department', 'no.dept@crestfield.edu.ng', 'Lecturer II');
        RAISE NOTICE 'T9 FAIL: lecturer without department accepted';
    EXCEPTION WHEN not_null_violation THEN
        RAISE NOTICE 'T9 PASS: lecturer without department rejected  [%] %', SQLSTATE, SQLERRM;
    END;

    -- T10: VALID insert still works (constraints are not over-restrictive)
    BEGIN
        INSERT INTO result (registration_id, ca_score, exam_score, entered_by)
        VALUES (v_open_reg, 25, 55, 1);
        RAISE NOTICE 'T10 PASS: valid result accepted (rolled back afterwards)';
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'undo T10';  -- roll back the test row
    EXCEPTION WHEN no_data_found THEN
        NULL;
    END;
END;
$$;
