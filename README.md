# MIT 8103 Advanced Database Systems: Practical Portfolio

**Student:** Oluwafemi Laguda (301931670)
**Programme:** Master of Information Technology, MIVA Open University, 2026/2027 First Semester

## Case study: Crestfield University Student Result Portal

| | |
|---|---|
| **Organisation / scenario** | Crestfield University, a fictional mid-sized Nigerian university. It is replacing spreadsheet result sheets with a central Student Result Portal. |
| **Nature of the system** | An academic records system that manages course registration, score entry, result approval, and GPA/CGPA calculation on the Nigerian 5-point grading scale. |
| **Users of the database** | **Students** register courses and view results and transcripts. **Lecturers** enter CA and exam scores. **HODs / Senate** approve and lock results. **Exams & Records officers** produce transcripts and degree classifications. **ICT administrators** run backups, replication and performance. |
| **Major data stored** | Faculties, departments, programmes, lecturers, students, courses, academic sessions, course offerings, registrations, results (CA, exam, total), the grade scale, and a result-change audit log. Unstructured items include course materials, comments and student activity, which are covered in Portfolio 4 (NoSQL). |
| **Key operations** | Register courses (respecting capacity), enter and update scores, approve and lock results, compute semester GPA and CGPA, generate transcripts, rank students, and audit any change to a score. |

Why this case suits the course:
- **Results data is high-stakes.** That justifies strict constraints (Portfolio 1) and ACID transactions with concurrency control, for example two students competing for the last seat or two officers editing the same score (Portfolio 3).
- **Data volume** (students × courses × sessions) supports realistic query optimisation (Portfolio 2).
- **Registration week** is a natural peak-load case for replication and partitioning (Portfolio 5).

## Repository structure

```
.
├── docker-compose.yml                    # PostgreSQL 16 (MongoDB + replica added later)
├── portfolio-1-database-design/          # ER diagram, schema, constraints, normalisation
├── portfolio-2-query-optimisation/       # queries, EXPLAIN ANALYZE, indexing
├── portfolio-3-transactions-concurrency/ # COMMIT/ROLLBACK, isolation, locking
├── portfolio-4-nosql/                    # MongoDB model of the same case study
├── portfolio-5-distributed-cloud/        # replication, partitioning, CAP
└── README.md
```

## Progress

| Portfolio | Topic | Status |
|---|---|---|
| 1 | Database Design and Modelling | Complete: [README](portfolio-1-database-design/README.md) |
| 2 | Query Processing and Optimisation | Not started |
| 3 | Transactions and Concurrency | Not started |
| 4 | NoSQL and Advanced Data Models | Not started |
| 5 | Distributed and Cloud Database | Not started |

## Requirements and quick start

- Docker Desktop for Windows (WSL 2 backend)
- PowerShell

```powershell
docker compose up -d
.\portfolio-1-database-design\run.ps1
```
