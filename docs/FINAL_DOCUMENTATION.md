# MIT 8103 Advanced Database Systems: Portfolio Documentation

**Student:** Oluwafemi Laguda  **Matric:** 301931670  **Session:** 2026/2027, First Semester
**GitHub repository:** https://github.com/Laguda100/Oluwafemi_Laguda_301931670
**Technologies:** PostgreSQL 16.4, MongoDB 7.0.14, Docker Desktop (Compose), Windows 11 / PowerShell

## 1. Selected case study: Crestfield University Student Result Portal

Crestfield University is a (simulated) Nigerian university replacing spreadsheet result sheets with a central result portal.
- **Users:** students (registration, results, transcripts), lecturers (score entry), HODs/Senate (approval), Exams & Records officers (transcripts, degree classification), and ICT administrators.
- **Data:** faculties, departments, programmes, lecturers, students, courses, sessions, course offerings, registrations, results, the grading scale and a score audit log. Activity logs and course feedback were added in Portfolio 4.
- **Key operations:** register courses within capacity and credit limits, enter and approve scores, lock approved results, compute GPA/CGPA and class of degree, generate transcripts, and report pass rates.

The same case study is used in all five portfolios.

## 2. Summary of the portfolio activities

**Portfolio 1: Database design and modelling.**
- I modelled 12 entities in a Mermaid ER diagram and a relational schema, normalised from the paper result sheet (UNF) to 1NF, 2NF, 3NF and BCNF.
- The key modelling idea is the `course_offering` entity, which resolves the course–session many-to-many relationship and holds lecturer, capacity and approval status.
- Grades, GPA and CGPA are derived through views rather than stored. The one justified exception is `total_score`, a stored generated column.
- Integrity is enforced with surrogate and natural keys, CHECK constraints, a partial unique index (one current session), a trigger that locks approved results, and an audit trigger.
- Ten automated constraint tests prove invalid data is rejected.

**Portfolio 2: Query processing and optimisation.**
- I generated about 2.3 million registrations and about 2 million results (60,000 students over 8 sessions).
- I wrote seven workload queries using joins, CTEs, window functions (RANK, NTILE, windowed AVG), subqueries and FILTER aggregates.
- I captured `EXPLAIN (ANALYZE, BUFFERS)` plans before and after indexing.
- The five indexes demonstrate different techniques: foreign-key indexes, a covering index (INCLUDE, enabling index-only scans), a partial index for failed results, an expression index for case-insensitive search, and a cohort filter.
- The timing table is in `portfolio-2-query-optimisation/results/timing_summary.md`. The largest gain was Q1 (transcript lookup), where a parallel sequential scan of the registration table became an index-only scan. Q4 shows that the planner rightly keeps hash joins when a large share of the table is needed.

**Portfolio 3: Transactions and concurrency.**
- I showed COMMIT, ROLLBACK, automatic abort on error, and SAVEPOINT, using result-upload and registration scenarios.
- I reproduced ten two-session concurrency demos automatically, with timestamps:
  - a lost update, fixed with `SELECT … FOR UPDATE`
  - overbooking of the last seat (write skew), prevented by SERIALIZABLE (error 40001) and by a row-locking `register_course()` function
  - a deadlock (error 40P01), avoided by consistent lock ordering
  - a non-repeatable read under READ COMMITTED vs a stable snapshot under REPEATABLE READ
  - proof that PostgreSQL never allows dirty reads

**Portfolio 4: NoSQL and advanced data models.**
- I used MongoDB for the parts of the portal that suit it, keeping PostgreSQL as the system of record:
  - an embedded transcript **document** per student, migrated from PostgreSQL with `jsonb_agg`
  - a **graph** of course prerequisites (`$graphLookup`)
  - a high-volume **event** collection (50,000 events of 4 shapes, TTL expiry)
  - **polymorphic** feedback forms
  - **key-value** login sessions
- Students are protected by `$jsonSchema` validation (7 tests).
- Twelve queries cover CRUD, `$setWindowFields`, pipeline updates, text search and `explain()`. The explain output shows the ESR-ordered index examining about 10 documents instead of 50,000.

**Portfolio 5: Distributed and cloud databases.**
- I built a Docker Compose cluster: a primary and a hot-standby replica using WAL streaming with a replication slot.
- The verification script shows:
  - streaming status and replication lag
  - a read-only replica
  - range partitioning with pruning and instant archiving (DETACH)
  - hash partitioning as a sharding simulation
  - synchronous vs asynchronous commit with the replica down, which is CAP/PACELC in practice
  - failover by promoting the replica
- The README gives a Citus sharding design (shard key `student_id`) and the equivalent managed-cloud deployment on Azure and AWS.

## 3. Evidence

Each portfolio folder has a README explaining how it was implemented and tested, a `run.ps1` that reproduces it, a `results/` folder with raw output, and an `evidence/` folder with screenshots:

| Portfolio | Key screenshots |
|---|---|
| 1 | Healthy container, ER diagram, `\d+ result`, constraint tests all PASS, transcript and GPA output |
| 2 | Data volume, Q1 and Q5 plans before/after, Q4 window output, index sizes, timing summary |
| 3 | COMMIT/ROLLBACK, auto-abort and SAVEPOINT, lost update vs fix, overbooking (3 variants), deadlock, isolation levels, lock monitor |
| 4 | Export/load, collections and indexes, transcript update, aggregations, `$graphLookup`, IXSCAN vs COLLSCAN, validation tests |
| 5 | Healthy cluster, replication status, write/read test, partition pruning, sync vs async, failover |

## 4. Individual technical reflection

**Design choices.**
- The decision I thought about most was what *not* to store. In Portfolio 1 I computed grades and GPA through views so a corrected score can never leave a stale grade behind. In Portfolio 4 I did the opposite and stored them in the transcript document, because approved results never change and the document is a read model. Seeing the same data modelled both ways showed me that normalisation is a tool for a write workload, not a goal in itself.
- I also chose a row lock inside `register_course()` over relying on SERIALIZABLE. Both prevented overbooking, but the lock never needs a retry loop and only blocks students registering for the same course.

**Challenges.**
- **Unindexed foreign keys.** At first I assumed PostgreSQL indexes them automatically. The Portfolio 2 "before" plans showed a sequential scan over millions of registration rows for a single student's transcript, which taught me to read plans rather than guess.
- **Showing concurrency problems reliably.** Running two sessions by hand gave different timings every time. Scripting the sessions with `pg_sleep` and timestamped output made each anomaly reproducible.
- **Windows line endings.** The Linux containers rejected shell scripts saved with Windows line endings. I fixed this with a `.gitattributes` rule.
- **PowerShell and stderr.** PowerShell 5.1 treats a native program's stderr as an error, so I redirected psql output through `cmd`.

**Lessons learned.**
- An index is not always used, and that's correct. Selectivity and statistics drive the planner.
- Isolation levels are about which anomalies you accept, not just "stronger is better".
- In a distributed system every guarantee has a cost. The 5-second blocked commit with synchronous replication made the CAP theorem concrete for me in a way the definition never did.

## 5. References

- Abadi, D. (2012) 'Consistency trade-offs in modern distributed database system design', *Computer*, 45(2), pp. 37–42.
- Brewer, E. (2012) 'CAP twelve years later: how the "rules" have changed', *Computer*, 45(2), pp. 23–29.
- Elmasri, R. and Navathe, S.B. (2016) *Fundamentals of Database Systems*. 7th edn. Pearson.
- Kleppmann, M. (2017) *Designing Data-Intensive Applications*. O'Reilly Media.
- MongoDB Inc. (2024) *MongoDB 7.0 Manual*. Available at: https://www.mongodb.com/docs/v7.0/
- Ports, D.R.K. and Grittner, K. (2012) 'Serializable snapshot isolation in PostgreSQL', *Proceedings of the VLDB Endowment*, 5(12), pp. 1850–1861.
- PostgreSQL Global Development Group (2024) *PostgreSQL 16 Documentation*. Available at: https://www.postgresql.org/docs/16/ (chapters on Indexes, Performance Tips, Concurrency Control, High Availability, Table Partitioning).
- Silberschatz, A., Korth, H.F. and Sudarshan, S. (2019) *Database System Concepts*. 7th edn. McGraw-Hill.
- Citus Data (2024) *Citus Documentation: Choosing the distribution column*. Available at: https://docs.citusdata.com/

## 6. AI use declaration

| | |
|---|---|
| **AI tool used** | Claude (Anthropic), through the Claude Code command-line assistant |
| **What it was used for** | Drafting the SQL, MongoDB and PowerShell scripts, the README files, and the structure of this document from my instructions and chosen case study. It also explained concepts (execution plans, SSI, replication slots, PACELC) that I then used in my analysis. |
| **How I reviewed and verified the output** | I ran every script in my own Docker environment and checked the outputs in each `results/` folder against the expected results in each README (constraint tests all PASS; plans and timings before and after indexing; concurrency final states such as 55 vs 57 and 2 vs 1 registrations; replication status). I fixed the errors I found, rewrote the explanations and this reflection in my own words, and made sure I can explain every design decision. |
