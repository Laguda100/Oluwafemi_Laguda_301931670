# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** Crestfield University Student Result Portal
**Engine:** MongoDB 7.0.14 (Docker container `crestfield-mongo`), with data migrated from PostgreSQL 16

## 1. Which parts of the portal suit NoSQL, and which don't

I did **not** move the whole system to MongoDB. The relational database stays the **system of record** for registration and score entry, because those need multi-row ACID transactions, foreign keys, and the locking shown in Portfolio 3. MongoDB is used where the data's *shape* or *access pattern* fits a document store better. This is **polyglot persistence**:

| Part of the portal | Data model | Why NoSQL fits better than relational |
|---|---|---|
| **Student transcript** (read model) | **Document**: one document per student with the transcript embedded | The transcript is read thousands of times (students checking results, transcript requests, employers verifying), but written rarely, and approved results never change. In SQL every read costs a 6-table join plus grade lookups (Portfolio 2, Q1). In MongoDB it's **one indexed read** of one document. |
| **LMS activity events** | **Event log** with flexible schema and a TTL index | About 50k events with 4 different shapes (login, download, quiz, forum post). In SQL that means either one wide table full of NULLs or 4 tables plus a UNION. A high insert rate and automatic expiry suit MongoDB. |
| **Course feedback forms** | **Polymorphic documents** | Each course asks different questions (lab courses rate equipment). A relational design needs an EAV table (question/answer rows), which is hard to query. In MongoDB the `ratings` sub-document has whatever keys that course used. |
| **Course prerequisites** | **Graph** (edges as arrays) traversed with `$graphLookup` | "All prerequisites of CSC 410 at any depth" is a recursive query. MongoDB traverses it natively. In SQL it needs a recursive CTE. |
| **Login sessions** | **Key-value** (`_id` = token) with a TTL index | Pure key lookups that expire after 30 minutes. This is the classic Redis use case. A MongoDB TTL collection gives the same behaviour without another server. |

**What stays relational:**
- Course registration (capacity and credit-limit rules across rows)
- Score entry and approval (constraints, audit triggers, locking)
- Anything needing joins across many entities with strict integrity

## 2. Schema design decisions

### `students`: embed or reference?

Document shape (values are illustrative; the real documents are in `data/students.ndjson`):

```js
{
  "_id": "CFU/2025/00001",                       // natural key: the matric number
  "name": { "first": "Oluwaseun", "last": "Adeleke", "other": "Tobi" },
  "email": "...", "gender": "M", "dateOfBirth": ISODate("2006-03-14"),
  "entryYear": 2025, "currentLevel": 200, "status": "ACTIVE",
  "programme": { "code": "BSC-CSC", "name": "B.Sc. Computer Science",
                 "department": "Computer Science", "faculty": "Faculty of Computing and Applied Sciences" },
  "transcript": [
    { "session": "2025/2026", "semester": 1, "gpa": 3.67,
      "courses": [ { "code": "CSC 101", "title": "...", "units": 3,
                     "ca": 24, "exam": 47, "total": 71, "grade": "A", "gradePoint": 5 }, ... ] },
    ...
  ],
  "cgpa": 3.42, "classOfDegree": "Second Class Lower"
}
```

| Decision | Reason |
|---|---|
| **Embed** the transcript | Always read together with the student (the "data that is accessed together is stored together" rule). The array is **bounded**: at most about 10 semesters × about 12 courses. That's well under the 16 MB document limit; a full 4-year transcript is roughly 10–15 KB. |
| **Embed** (denormalise) programme, department and faculty names | They are needed on every transcript and change very rarely. This deliberately **breaks 3NF**: if a department is renamed, every student document must be updated. That's acceptable because renames are rare and can be done with one `updateMany`. |
| **Store** grade, gradePoint, GPA and CGPA | In Portfolio 1 these were computed by views to avoid anomalies. Here they're stored because approved results are **immutable** and the document is a **read-optimised snapshot**. |
| **Do NOT embed** activity events | Events grow **without bound** (unbounded arrays are an anti-pattern: documents grow, indexes bloat, and they hit the 16 MB limit). They live in their own collection and reference `studentId`. |
| `_id` = matric number | A natural, immutable, unique key. Lookups by matric number use the built-in `_id` index. |

### Schema validation

MongoDB is "schema-flexible", not "schema-less". `01_setup.js` attaches a **`$jsonSchema` validator** to `students` that enforces the same rules as the relational CHECK constraints: matric format, exam 0–70, CA 0–30, grade A–F, required fields. `05_validation_tests.js` proves it: invalid inserts and updates are rejected with **code 121 (DocumentValidationFailure)**, and a duplicate email with **11000 (DuplicateKey)**.

### Indexes

| Collection | Index | Purpose |
|---|---|---|
| students | `_id` (built in) | Transcript lookup by matric number (Q1) |
| students | `{email: 1}` unique | Login and uniqueness |
| students | `{'programme.code': 1, cgpa: -1}` | Ranking within a programme (Q4) |
| students | `{'transcript.courses.code': 1}` (**multikey**) | One index entry per course taken, so "who took MTH 101" doesn't scan every student (Q2) |
| activity_events | `{studentId: 1, type: 1, ts: -1}` | Follows the **ESR rule** (Equality, Sort, Range): the equality fields come first, then the sort field, so results come back already sorted with no in-memory SORT (Q11) |
| activity_events | `{ts: 1}`, **TTL** 180 days | Old events are deleted automatically by a background task |
| course_feedback | `{comment: 'text'}` | Full-text search with relevance scoring (Q9) |
| portal_sessions | `{expiresAt: 1}`, TTL 0 | Each session is deleted at its own `expiresAt` time |

## 3. Implementation

| File | What it does |
|---|---|
| [`sql/export_students.sql`](sql/export_students.sql) | **Relational → document migration.** Builds each student document in PostgreSQL with `jsonb_build_object`/`jsonb_agg` (nested aggregation by semester) and outputs NDJSON |
| [`scripts/01_setup.js`](scripts/01_setup.js) | Creates the 5 collections, the validator and all indexes |
| [`scripts/02_load_students.js`](scripts/02_load_students.js) | Imports the NDJSON (`insertMany`), converts dates, prints a sample document |
| [`scripts/03_seed_other.js`](scripts/03_seed_other.js) | Prerequisite graph, 50,000 activity events, about 120 feedback forms, 5 sessions |
| [`scripts/04_queries.js`](scripts/04_queries.js) | Q1–Q12: read, update, aggregate, graph, text, key-value, explain, delete |
| [`scripts/05_validation_tests.js`](scripts/05_validation_tests.js) | N1–N7 validation tests |
| [`run.ps1`](run.ps1) | Export, load and run everything, saving output to `results/` |

### Query catalogue (`04_queries.js`)

| # | Operation | MongoDB features | SQL equivalent (Portfolios 1–2) |
|---|---|---|---|
| Q1 | Read transcript | `findOne` + projection | 6-table join + LATERAL (P2 Q1) |
| Q2 | Students below 50 in MTH 101 | `$elemMatch` on a nested array, multikey index | JOIN + WHERE |
| Q3 | Approve a new semester | `$push`, **update with an aggregation pipeline** to recompute CGPA (`$reduce`, `$map`, `$sum`) | INSERT into result; view recomputes |
| Q4 | Programme ranking | **`$setWindowFields`** with `$rank`, windowed `$avg` | `RANK() OVER (PARTITION BY …)` (P2 Q4) |
| Q5 | Pass rate per course | `$unwind` twice, `$group`, `$cond` | GROUP BY + FILTER (P2 Q3) |
| Q6 | Prerequisite chain | **`$graphLookup`** (recursive) | `WITH RECURSIVE` CTE |
| Q7 | Activity analytics | `$dateTrunc`, `$addToSet`, `$size` | `date_trunc` + `COUNT(DISTINCT)` |
| Q8 | Quiz performance | Aggregating fields that only some documents have | Sparse columns or a separate table |
| Q9 | Feedback | `$text` search, `$objectToArray` over varying keys | Full-text search + EAV pivot |
| Q10 | Session lookup | `_id` lookup (IDHACK plan), sliding TTL | Key-value store |
| Q11 | Index analysis | `explain('executionStats')`, `hint({$natural: 1})` | `EXPLAIN ANALYZE` |
| Q12 | Purge old events | `deleteMany` | DELETE |

### Index evidence (Q11)

`results/04_queries.txt` prints two plans for "latest 10 quiz attempts of one student":
- **Expected with the index:** `LIMIT <- FETCH <- IXSCAN`, keys examined about equal to documents examined, about 10. No SORT stage, because the index already orders by `ts`.
- **Expected with the forced collection scan:** `SORT <- COLLSCAN`, about 50,000 documents examined to return 10.

## 4. Trade-offs and consistency

| Aspect | PostgreSQL (Portfolios 1–3) | MongoDB (this portfolio) |
|---|---|---|
| Integrity | FKs, CHECKs, triggers across tables | Validator per document. **No foreign keys**: `studentId` in events is not checked. |
| Transactions | Multi-statement ACID by default | Single-document writes are atomic. Multi-document transactions exist (replica set required) but aren't the normal style. |
| Reads | Joins at query time | Pre-joined documents: fast, but duplicated data |
| Schema change | `ALTER TABLE` | New fields can appear in new documents only |
| Scaling | Vertical, plus read replicas (Portfolio 5) | Built-in sharding by key (for example `studentId`) |

**Keeping the two stores consistent.** The transcript document is a *copy* of relational data. When Senate approves a course's results in PostgreSQL, the application (or a change-data-capture tool such as Debezium) re-exports the affected students' documents. That makes the document store **eventually consistent** with the system of record, which is acceptable because:
- The portal shows a result only after approval.
- The authoritative copy is always in PostgreSQL.

## 5. How to run

```powershell
docker compose up -d                       # starts postgres AND mongo
.\portfolio-4-nosql\run.ps1
```

To explore interactively:

```powershell
docker exec -it crestfield-mongo mongosh crestfield_nosql
```
```js
db.students.findOne({ _id: 'CFU/2025/00001' })
db.activity_events.find({ type: 'quiz_attempt' }).limit(3)
```

A GUI is optional: MongoDB Compass can connect to `mongodb://localhost:27017`.

## 6. Evidence (`evidence/` folder)

| File | What it shows |
|---|---|
| `p4-01-export-load.png` | `results/02_load_students.txt`: "Inserted 12 student documents" and the sample document with its embedded transcript |
| `p4-02-collections-indexes.png` | `results/01_setup.txt`: the 5 collections and their indexes |
| `p4-03-transcript-update.png` | Q1 document, plus Q3 CGPA before and after |
| `p4-04-aggregations.png` | Q4 (ranking with `programmeRank`) and Q5 (pass rate) |
| `p4-05-graphlookup.png` | Q6 prerequisite chain with depth values |
| `p4-06-explain.png` | Q11: IXSCAN (about 10 docs examined) vs COLLSCAN (about 50,000 docs examined) |
| `p4-07-validation.png` | `results/05_validation_tests.txt`: all PASS with codes 121 and 11000 |
| `p4-08-compass.png` (optional) | A student document in MongoDB Compass |
