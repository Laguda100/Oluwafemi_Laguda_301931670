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
├── docker-compose.yml                    # PostgreSQL 16.4 + MongoDB 7.0 development stack
├── docs/FINAL_DOCUMENTATION.md           # 2-3 page summary submitted on the LMS
├── portfolio-1-database-design/          # ER diagram, schema, constraints, normalisation
├── portfolio-2-query-optimisation/       # workload queries, EXPLAIN ANALYZE, indexing strategy
├── portfolio-3-transactions-concurrency/ # COMMIT/ROLLBACK/SAVEPOINT, isolation, locking, deadlocks
├── portfolio-4-nosql/                    # MongoDB: document, graph, event, key-value models
├── portfolio-5-distributed-cloud/        # streaming replication, partitioning, CAP, failover
└── README.md
```

Each portfolio folder contains:
- `README.md`: design reasoning, how it was implemented and tested, expected results, and the screenshot list
- `run.ps1`: reproduces the whole activity with one command
- `sql/` or `scripts/`: the source code
- `results/`: raw output produced by `run.ps1`
- `evidence/`: screenshots

## Portfolios

| Portfolio | Topic | Highlights |
|---|---|---|
| [1](portfolio-1-database-design/README.md) | Database Design and Modelling | 12-table BCNF schema, ER diagram, triggers, partial unique index, 10 constraint tests |
| [2](portfolio-2-query-optimisation/README.md) | Query Processing and Optimisation | 2.3M-row dataset, 7 queries (CTE, window functions), 5 index types, before/after plans and timings |
| [3](portfolio-3-transactions-concurrency/README.md) | Transactions and Concurrency | 6 single-session demos, 10 automated two-session concurrency demos |
| [4](portfolio-4-nosql/README.md) | NoSQL and Advanced Data Models | Relational-to-document migration, `$jsonSchema`, `$graphLookup`, `$setWindowFields`, TTL, explain |
| [5](portfolio-5-distributed-cloud/README.md) | Distributed and Cloud Database | Primary + replica, range/hash partitioning, sync vs async (CAP/PACELC), failover, cloud design |

## Requirements and quick start

- Docker Desktop for Windows (WSL 2 backend), at least 4 GB RAM allocated
- PowerShell 5.1 or later

```powershell
docker compose up -d                                  # PostgreSQL :5432, MongoDB :27017
.\portfolio-1-database-design\run.ps1
.\portfolio-2-query-optimisation\run.ps1              # rebuilds the database and adds about 2.3M rows
.\portfolio-3-transactions-concurrency\run.ps1        # rebuilds the small Portfolio 1 dataset
.\portfolio-4-nosql\run.ps1
.\portfolio-5-distributed-cloud\run.ps1               # separate primary/replica cluster on :5433/:5434
```

## AI use

AI assistance was used in this portfolio and is declared in [docs/FINAL_DOCUMENTATION.md](docs/FINAL_DOCUMENTATION.md#6-ai-use-declaration), as section 11 of the assessment brief requires.
