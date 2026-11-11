# ER Diagram: Crestfield University Student Result Portal

GitHub renders this diagram automatically. A PNG of it is in
[`evidence/p1-02-er-diagram.png`](evidence/p1-02-er-diagram.png), rendered from
the code block below with Mermaid 11.4. Pasting the block into https://mermaid.live
and exporting it produces the same diagram.

```mermaid
erDiagram
    FACULTY ||--|{ DEPARTMENT : "has"
    DEPARTMENT ||--|{ PROGRAMME : "runs"
    DEPARTMENT ||--o{ LECTURER : "employs"
    DEPARTMENT ||--o{ COURSE : "owns"
    PROGRAMME ||--o{ STUDENT : "enrols"
    COURSE ||--o{ COURSE_OFFERING : "is offered as"
    ACADEMIC_SESSION ||--o{ COURSE_OFFERING : "schedules"
    LECTURER ||--o{ COURSE_OFFERING : "teaches"
    STUDENT ||--o{ REGISTRATION : "makes"
    COURSE_OFFERING ||--o{ REGISTRATION : "receives"
    REGISTRATION ||--o| RESULT : "produces"
    LECTURER ||--o{ RESULT : "enters"
    RESULT ||..o{ RESULT_AUDIT : "is logged in"

    FACULTY {
        smallint faculty_id PK
        varchar code UK
        varchar name UK
    }
    DEPARTMENT {
        smallint department_id PK
        smallint faculty_id FK
        varchar code UK
        varchar name
    }
    PROGRAMME {
        smallint programme_id PK
        smallint department_id FK
        varchar code UK
        varchar name
        varchar degree_type
        smallint duration_years
    }
    LECTURER {
        int lecturer_id PK
        smallint department_id FK
        varchar staff_no UK
        varchar title
        varchar first_name
        varchar last_name
        varchar email UK
        varchar academic_rank
    }
    STUDENT {
        int student_id PK
        varchar matric_no UK
        smallint programme_id FK
        varchar first_name
        varchar last_name
        varchar other_names
        varchar email UK
        date date_of_birth
        char gender
        smallint entry_year
        smallint current_level
        varchar status
    }
    COURSE {
        int course_id PK
        smallint department_id FK
        varchar course_code UK
        varchar title
        smallint credit_units
        smallint course_level
        smallint semester
    }
    ACADEMIC_SESSION {
        smallint session_id PK
        char name UK
        date start_date
        date end_date
        boolean is_current "only one true"
    }
    COURSE_OFFERING {
        int offering_id PK
        int course_id FK "UK with session_id"
        smallint session_id FK
        int lecturer_id FK
        smallint capacity
        varchar result_status
    }
    REGISTRATION {
        bigint registration_id PK
        int student_id FK "UK with offering_id"
        int offering_id FK
        timestamptz registered_at
        varchar status
    }
    RESULT {
        bigint registration_id PK, FK
        numeric ca_score "0-30"
        numeric exam_score "0-70"
        numeric total_score "generated"
        int entered_by FK
        timestamptz entered_at
        timestamptz updated_at
    }
    GRADE_SCALE {
        char grade PK
        numeric min_score UK
        smallint grade_point UK
    }
    RESULT_AUDIT {
        bigint audit_id PK
        bigint registration_id
        char action
        numeric old_ca_score
        numeric old_exam_score
        numeric new_ca_score
        numeric new_exam_score
        text changed_by
        timestamptz changed_at
    }
```

## How to read the diagram

| Relationship | Cardinality | Meaning |
|---|---|---|
| Faculty to Department | 1 : 1..N | Every faculty has at least one department; every department belongs to exactly one faculty. |
| Department to Programme | 1 : 1..N | A department runs one or more degree programmes. |
| Department to Lecturer / Course | 1 : 0..N | Lecturers and courses belong to one home department. |
| Programme to Student | 1 : 0..N | A student is admitted into exactly one programme. |
| Course and Session to Course_Offering | 1 : 0..N each | **Course_Offering** turns the M:N between Course and Session into two 1:N relationships. It records that a course ran in a given session, taught by a given lecturer. |
| Student and Course_Offering to Registration | 1 : 0..N each | **Registration** resolves the M:N between Student and Course_Offering. |
| Registration to Result | 1 : 0..1 | A registration has at most one result, and it has none until scores are entered. `result` uses `registration_id` as both its PK and FK. |
| Result to Result_Audit | 1 : 0..N (dotted line) | Logical link only, with no FK, so audit history survives if a result is deleted. |
| Grade_Scale | (not linked) | A policy lookup table, matched by score range (`min_score <= total_score`) rather than by a foreign key. |
