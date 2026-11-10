-- =====================================================================
-- Portfolio 3 - Crestfield University Student Result Portal
-- File   : 01_transactions.sql
-- Purpose: Single-session transaction behaviour:
--          A. COMMIT          - scores for a whole class saved as one unit
--          B. ROLLBACK        - an accidental mass update is undone
--          C. Automatic abort - one invalid statement aborts the whole transaction
--          D. SAVEPOINT       - partial rollback inside a registration batch
--          E. Isolation level - default and per-transaction settings
--          F. register_course - the concurrency-safe registration function
-- Run after 00_setup.sql. Errors in this file are INTENTIONAL, so
-- ON_ERROR_STOP is switched off here.
-- =====================================================================

\set ON_ERROR_STOP off
\pset footer off

-- Helper view: the CSC 201 class list with scores (temporary, this session only).
CREATE TEMP VIEW csc201_scores AS
SELECT s.matric_no, r.ca_score, r.exam_score, r.total_score
FROM registration reg
JOIN student s         ON s.student_id = reg.student_id
JOIN course_offering o ON o.offering_id = reg.offering_id
JOIN course c          ON c.course_id = o.course_id
LEFT JOIN result r     ON r.registration_id = reg.registration_id
WHERE c.course_code = 'CSC 201'
ORDER BY s.matric_no;

-- ---------------------------------------------------------------------
\echo '=== A. COMMIT: Dr Ogunleye uploads CSC 201 scores as ONE transaction ==='
-- Either every student's score is saved AND the sheet is marked SUBMITTED,
-- or nothing is saved. A half-uploaded result sheet is never visible.
-- ---------------------------------------------------------------------
SELECT * FROM csc201_scores;          -- expected: 4 rows, scores NULL

BEGIN;
INSERT INTO result (registration_id, ca_score, exam_score, entered_by)
SELECT reg.registration_id, 18 + reg.student_id % 10, 40 + reg.student_id % 25, 1
FROM registration reg
JOIN course_offering o ON o.offering_id = reg.offering_id
JOIN course c          ON c.course_id = o.course_id
WHERE c.course_code = 'CSC 201';      -- expected: INSERT 0 4

UPDATE course_offering SET result_status = 'SUBMITTED'
WHERE course_id = (SELECT course_id FROM course WHERE course_code = 'CSC 201');   -- expected: UPDATE 1
COMMIT;

SELECT * FROM csc201_scores;          -- expected: 4 rows with scores (e.g. 00001 -> 19 + 41 = 60)
SELECT o.result_status FROM course_offering o JOIN course c ON c.course_id = o.course_id
WHERE c.course_code = 'CSC 201';      -- expected: SUBMITTED

-- ---------------------------------------------------------------------
\echo '=== B. ROLLBACK: an officer adds +5 to the WRONG course, notices, and rolls back ==='
-- ---------------------------------------------------------------------
SELECT count(*) AS audit_rows_before FROM result_audit;
BEGIN;
UPDATE result SET exam_score = exam_score + 5
WHERE registration_id IN (SELECT reg.registration_id
                          FROM registration reg
                          JOIN course_offering o ON o.offering_id = reg.offering_id
                          JOIN course c          ON c.course_id = o.course_id
                          WHERE c.course_code = 'CSC 201');   -- expected: UPDATE 4
\echo '--- inside the transaction (only this session can see the change) ---'
SELECT * FROM csc201_scores;          -- expected: exam scores +5
ROLLBACK;
\echo '--- after ROLLBACK ---'
SELECT * FROM csc201_scores;          -- expected: same values as after A
SELECT count(*) AS audit_rows_after FROM result_audit;
-- expected: same number as audit_rows_before. The 4 audit rows written by the
-- trigger were rolled back together with the update (atomicity).

-- ---------------------------------------------------------------------
\echo '=== C. AUTOMATIC ABORT: one invalid score aborts the whole transaction ==='
-- ---------------------------------------------------------------------
BEGIN;
UPDATE result SET exam_score = 65
WHERE registration_id = (SELECT reg.registration_id FROM registration reg
                         JOIN student s ON s.student_id = reg.student_id
                         JOIN course_offering o ON o.offering_id = reg.offering_id
                         JOIN course c ON c.course_id = o.course_id
                         WHERE s.matric_no = 'CFU/2025/00001' AND c.course_code = 'CSC 201');  -- UPDATE 1
UPDATE result SET exam_score = 95
WHERE registration_id = (SELECT reg.registration_id FROM registration reg
                         JOIN student s ON s.student_id = reg.student_id
                         JOIN course_offering o ON o.offering_id = reg.offering_id
                         JOIN course c ON c.course_id = o.course_id
                         WHERE s.matric_no = 'CFU/2025/00002' AND c.course_code = 'CSC 201');
-- expected: ERROR: new row for relation "result" violates check constraint "result_exam_score_check"
SELECT 1;
-- expected: ERROR: current transaction is aborted, commands ignored until end of transaction block
COMMIT;
-- expected: ROLLBACK  (PostgreSQL turns COMMIT of a failed transaction into ROLLBACK)
SELECT * FROM csc201_scores;          -- expected: 00001 still has its original exam score, NOT 65

-- ---------------------------------------------------------------------
\echo '=== D. SAVEPOINT: Blessing Etim registers 3 electives; one is a duplicate ==='
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO registration (student_id, offering_id)
SELECT 8, o.offering_id FROM course_offering o JOIN course c ON c.course_id = o.course_id
JOIN academic_session s ON s.session_id = o.session_id
WHERE c.course_code = 'CSC 201' AND s.is_current;                 -- expected: INSERT 0 1
SAVEPOINT after_csc201;

INSERT INTO registration (student_id, offering_id)
SELECT 8, o.offering_id FROM course_offering o JOIN course c ON c.course_id = o.course_id
JOIN academic_session s ON s.session_id = o.session_id
WHERE c.course_code = 'ECO 201' AND s.is_current;
-- expected: ERROR: duplicate key value violates unique constraint "uq_registration_student_offering"
ROLLBACK TO SAVEPOINT after_csc201;   -- undo only the failed statement; CSC 201 is kept

INSERT INTO registration (student_id, offering_id)
SELECT 8, o.offering_id FROM course_offering o JOIN course c ON c.course_id = o.course_id
JOIN academic_session s ON s.session_id = o.session_id
WHERE c.course_code = 'MTH 201' AND s.is_current;                 -- expected: INSERT 0 1
RELEASE SAVEPOINT after_csc201;
COMMIT;

SELECT c.course_code, c.credit_units
FROM registration reg
JOIN course_offering o  ON o.offering_id = reg.offering_id
JOIN course c           ON c.course_id = o.course_id
JOIN academic_session s ON s.session_id = o.session_id
WHERE reg.student_id = 8 AND s.is_current
ORDER BY c.course_code;
-- expected: ACC 201, CSC 201, ECO 201, MTH 201 (four rows)

-- ---------------------------------------------------------------------
\echo '=== E. ISOLATION LEVELS ==='
-- ---------------------------------------------------------------------
SHOW default_transaction_isolation;   -- expected: read committed
BEGIN ISOLATION LEVEL REPEATABLE READ;
SHOW transaction_isolation;           -- expected: repeatable read
COMMIT;
BEGIN ISOLATION LEVEL SERIALIZABLE;
SHOW transaction_isolation;           -- expected: serializable
COMMIT;

-- ---------------------------------------------------------------------
\echo '=== F. register_course(): business rules enforced inside a transaction ==='
-- ---------------------------------------------------------------------
SELECT o.offering_id AS csc205 FROM course_offering o JOIN course c ON c.course_id = o.course_id
WHERE c.course_code = 'CSC 205' \gset
SELECT register_course(9, :csc205) AS new_registration_id;   -- expected: a new id (seat taken)
SELECT register_course(10, :csc205);
-- expected: ERROR: Course offering ... is full (1 of 1 seats taken)
SELECT count(*) AS registered, max(o.capacity) AS capacity
FROM registration reg JOIN course_offering o ON o.offering_id = reg.offering_id
WHERE reg.offering_id = :csc205;      -- expected: 1 | 1
