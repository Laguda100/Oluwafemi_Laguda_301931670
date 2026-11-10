-- Portfolio 2 - removes the Portfolio 2 indexes so the "before" plans can be
-- reproduced without regenerating the data.
DROP INDEX IF EXISTS ix_registration_student;
DROP INDEX IF EXISTS ix_registration_offering;
DROP INDEX IF EXISTS ix_result_failed;
DROP INDEX IF EXISTS ix_student_lower_name;
DROP INDEX IF EXISTS ix_student_entry_year;
ANALYZE;
