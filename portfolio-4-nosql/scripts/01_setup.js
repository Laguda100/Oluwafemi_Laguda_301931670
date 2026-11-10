// =====================================================================
// Portfolio 4 - Crestfield University Student Result Portal (MongoDB 7.0)
// File   : 01_setup.js
// Purpose: Create the database, collections, JSON-Schema validation and
//          indexes for five data models:
//            students          - DOCUMENT model (embedded transcript)
//            courses           - GRAPH model (prerequisite edges, $graphLookup)
//            activity_events   - EVENT / time-ordered log, flexible schema, TTL
//            course_feedback   - POLYMORPHIC documents (different questions per course)
//            portal_sessions   - KEY-VALUE model (token -> session, auto-expiring)
// Run: docker exec crestfield-mongo mongosh --quiet /portfolio/portfolio-4-nosql/scripts/01_setup.js
// =====================================================================

db = db.getSiblingDB('crestfield_nosql');
db.dropDatabase();
print('Database crestfield_nosql recreated');

// ---------------------------------------------------------------------
// 1. students: one document per student with the transcript embedded.
//    Schema validation keeps the "schema-flexible" store from accepting
//    invalid academic data (same rules as the relational CHECK constraints).
// ---------------------------------------------------------------------
const courseItem = {
  bsonType: 'object',
  required: ['code', 'units', 'ca', 'exam', 'total', 'grade', 'gradePoint'],
  properties: {
    code:       { bsonType: 'string', pattern: '^[A-Z]{3} [0-9]{3}$' },
    title:      { bsonType: 'string' },
    units:      { bsonType: 'number', minimum: 1, maximum: 6 },
    ca:         { bsonType: 'number', minimum: 0, maximum: 30 },
    exam:       { bsonType: 'number', minimum: 0, maximum: 70 },
    total:      { bsonType: 'number', minimum: 0, maximum: 100 },
    grade:      { enum: ['A', 'B', 'C', 'D', 'E', 'F'] },
    gradePoint: { bsonType: 'number', minimum: 0, maximum: 5 }
  }
};

db.createCollection('students', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['_id', 'name', 'email', 'programme', 'entryYear', 'status', 'transcript'],
      properties: {
        _id:          { bsonType: 'string', pattern: '^CFU/[0-9]{4}/[0-9]{5}$',
                        description: 'matric number, e.g. CFU/2025/00001' },
        name:         { bsonType: 'object', required: ['first', 'last'] },
        email:        { bsonType: 'string', pattern: '^[^@\\s]+@[^@\\s]+\\.[a-z]{2,}$' },
        gender:       { enum: ['M', 'F'] },
        dateOfBirth:  { bsonType: 'date' },
        entryYear:    { bsonType: 'number', minimum: 2000, maximum: 2100 },
        currentLevel: { enum: [100, 200, 300, 400, 500, 600, 700] },
        status:       { enum: ['ACTIVE', 'SUSPENDED', 'GRADUATED', 'WITHDRAWN'] },
        programme:    { bsonType: 'object', required: ['code', 'name', 'department', 'faculty'] },
        transcript: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            required: ['session', 'semester', 'courses'],
            properties: {
              session:  { bsonType: 'string', pattern: '^[0-9]{4}/[0-9]{4}$' },
              semester: { enum: [1, 2] },
              gpa:      { bsonType: 'number', minimum: 0, maximum: 5 },
              courses:  { bsonType: 'array', minItems: 1, items: courseItem }
            }
          }
        },
        cgpa: { bsonType: ['number', 'null'], minimum: 0, maximum: 5 }
      }
    }
  },
  validationLevel: 'strict',
  validationAction: 'error'
});

db.students.createIndex({ email: 1 }, { unique: true, name: 'ux_students_email' });
db.students.createIndex({ 'programme.code': 1, cgpa: -1 }, { name: 'ix_students_programme_cgpa' });
db.students.createIndex({ 'transcript.courses.code': 1 },
                        { name: 'ix_students_course_code' });           // multikey index (one entry per course)

// ---------------------------------------------------------------------
// 2. courses: catalogue with prerequisite edges (graph stored as arrays).
// ---------------------------------------------------------------------
db.createCollection('courses');
db.courses.createIndex({ prerequisites: 1 }, { name: 'ix_courses_prerequisites' });

// ---------------------------------------------------------------------
// 3. activity_events: high-volume LMS activity, shape varies by type.
//    Index follows the ESR rule (Equality, Sort, Range): studentId, type = equality, ts = sort.
//    TTL index automatically deletes events older than 180 days.
// ---------------------------------------------------------------------
db.createCollection('activity_events');
db.activity_events.createIndex({ studentId: 1, type: 1, ts: -1 }, { name: 'ix_events_student_type_ts' });
db.activity_events.createIndex({ ts: 1 }, { name: 'ttl_events_180d', expireAfterSeconds: 180 * 24 * 3600 });

// ---------------------------------------------------------------------
// 4. course_feedback: anonymous course evaluations; each course asks its
//    own questions, so the "ratings" sub-document has different keys.
// ---------------------------------------------------------------------
db.createCollection('course_feedback');
db.course_feedback.createIndex({ comment: 'text' }, { name: 'tx_feedback_comment' });
db.course_feedback.createIndex({ courseCode: 1, session: 1 }, { name: 'ix_feedback_course_session' });

// ---------------------------------------------------------------------
// 5. portal_sessions: key-value store, _id = login token. A TTL index on
//    expiresAt removes a session as soon as it expires (expireAfterSeconds: 0).
// ---------------------------------------------------------------------
db.createCollection('portal_sessions');
db.portal_sessions.createIndex({ expiresAt: 1 }, { name: 'ttl_sessions', expireAfterSeconds: 0 });

print('\nCollections and indexes:');
db.getCollectionNames().sort().forEach(c => {
  print(`  ${c}: ` + db.getCollection(c).getIndexes().map(i => i.name).join(', '));
});
