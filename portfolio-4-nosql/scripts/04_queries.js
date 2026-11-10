// =====================================================================
// Portfolio 4 - File: 04_queries.js
// Purpose: CRUD, aggregation, graph traversal, text search, key-value
//          access and index analysis on the MongoDB model.
// =====================================================================

db = db.getSiblingDB('crestfield_nosql');
const DAY = 24 * 3600 * 1000;
const section = t => print(`\n=== ${t} ===`);

// ---------------------------------------------------------------------
section('Q1 READ: full transcript in ONE document read (SQL needs a 6-table join)');
printjson(db.students.findOne(
  { _id: 'CFU/2025/00001' },
  { name: 1, 'programme.name': 1, transcript: 1, cgpa: 1, classOfDegree: 1 }
));

// ---------------------------------------------------------------------
section('Q2 READ: students who scored below 50 in MTH 101 ($elemMatch on embedded array)');
printjson(db.students.find(
  { 'transcript.courses': { $elemMatch: { code: 'MTH 101', total: { $lt: 50 } } } },
  { 'name.first': 1, 'name.last': 1, 'programme.code': 1 }
).toArray());

// ---------------------------------------------------------------------
section('Q3 UPDATE: Senate approves CSC 203 (2026/2027) -> $push semester, recompute CGPA');
print('Before: ' + JSON.stringify(db.students.findOne({ _id: 'CFU/2025/00001' }, { cgpa: 1, _id: 0 })));

// Same scores as the Portfolio 1 seed data for this registration (CA 29 + exam 27 = 56 -> C).
const pushRes = db.students.updateOne(
  { _id: 'CFU/2025/00001', 'transcript.session': { $ne: '2026/2027' } },   // idempotent
  { $push: { transcript: {
      session: '2026/2027', semester: 1, gpa: 3,
      courses: [{ code: 'CSC 203', title: 'Database Systems I', units: 3,
                  ca: 29, exam: 27, total: 56, grade: 'C', gradePoint: 3 }] } } }
);
print(`matched=${pushRes.matchedCount} modified=${pushRes.modifiedCount}`);

// Update with an aggregation pipeline: CGPA = sum(units * gradePoint) / sum(units)
// over every course in every semester (flatten nested arrays with $reduce).
const allCourses = { $reduce: { input: '$transcript.courses', initialValue: [],
                                in: { $concatArrays: ['$$value', '$$this'] } } };
db.students.updateOne({ _id: 'CFU/2025/00001' }, [
  { $set: {
      cgpa: { $round: [{ $divide: [
        { $sum: { $map: { input: allCourses, as: 'c', in: { $multiply: ['$$c.units', '$$c.gradePoint'] } } } },
        { $sum: { $map: { input: allCourses, as: 'c', in: '$$c.units' } } }
      ] }, 2] },
      lastUpdated: '$$NOW'
  } }
]);
print('After:  ' + JSON.stringify(db.students.findOne({ _id: 'CFU/2025/00001' }, { cgpa: 1, _id: 0 })));

// ---------------------------------------------------------------------
section('Q4 AGGREGATE: CGPA ranking per programme ($setWindowFields = SQL window functions)');
db.students.aggregate([
  { $match: { cgpa: { $ne: null } } },
  { $setWindowFields: {
      partitionBy: '$programme.code',
      sortBy: { cgpa: -1 },
      output: {
        programmeRank: { $rank: {} },
        programmeAvg:  { $avg: '$cgpa', window: { documents: ['unbounded', 'unbounded'] } }
      } } },
  { $project: { _id: 1, name: { $concat: ['$name.first', ' ', '$name.last'] },
                programme: '$programme.code', cgpa: 1, programmeRank: 1,
                programmeAvg: { $round: ['$programmeAvg', 2] }, classOfDegree: 1 } },
  { $sort: { programme: 1, programmeRank: 1 } }
]).forEach(d => printjson(d));

// ---------------------------------------------------------------------
section('Q5 AGGREGATE: pass rate per course per session ($unwind nested arrays + $group)');
db.students.aggregate([
  { $unwind: '$transcript' },
  { $unwind: '$transcript.courses' },
  { $group: {
      _id: { session: '$transcript.session', code: '$transcript.courses.code' },
      candidates: { $sum: 1 },
      passed:     { $sum: { $cond: [{ $gte: ['$transcript.courses.total', 40] }, 1, 0] } },
      avgScore:   { $avg: '$transcript.courses.total' } } },
  { $project: { _id: 0, session: '$_id.session', course: '$_id.code', candidates: 1, passed: 1,
                passRatePct: { $round: [{ $multiply: [{ $divide: ['$passed', '$candidates'] }, 100] }, 1] },
                avgScore: { $round: ['$avgScore', 1] } } },
  { $sort: { session: 1, course: 1 } }
]).forEach(d => printjson(d));

// ---------------------------------------------------------------------
section('Q6 GRAPH: full prerequisite chain of CSC 410 ($graphLookup, recursive)');
db.courses.aggregate([
  { $match: { _id: 'CSC 410' } },
  { $graphLookup: { from: 'courses', startWith: '$prerequisites',
                    connectFromField: 'prerequisites', connectToField: '_id',
                    as: 'chain', depthField: 'depth' } },
  { $project: { title: 1, chain: { $sortArray: {
      input: { $map: { input: '$chain', as: 'c', in: { course: '$$c._id', depth: '$$c.depth' } } },
      sortBy: { depth: 1, course: 1 } } } } }
]).forEach(d => printjson(d));
print('Courses that CSC 102 unlocks directly: ' +
      db.courses.find({ prerequisites: 'CSC 102' }, { _id: 1 }).toArray().map(c => c._id).join(', '));

// ---------------------------------------------------------------------
section('Q7 EVENTS: activity by type (last 30 days) and daily active students (last 7 days)');
db.activity_events.aggregate([
  { $match: { ts: { $gte: new Date(Date.now() - 30 * DAY) } } },
  { $group: { _id: '$type', events: { $sum: 1 }, students: { $addToSet: '$studentId' } } },
  { $project: { events: 1, distinctStudents: { $size: '$students' } } },
  { $sort: { events: -1 } }
]).forEach(d => printjson(d));
db.activity_events.aggregate([
  { $match: { ts: { $gte: new Date(Date.now() - 7 * DAY) } } },
  { $group: { _id: { $dateTrunc: { date: '$ts', unit: 'day' } },
              students: { $addToSet: '$studentId' }, events: { $sum: 1 } } },
  { $project: { _id: 0, day: { $dateToString: { date: '$_id', format: '%Y-%m-%d' } },
                activeStudents: { $size: '$students' }, events: 1 } },
  { $sort: { day: 1 } }
]).forEach(d => printjson(d));

// ---------------------------------------------------------------------
section('Q8 POLYMORPHIC: quiz performance per course (only quiz_attempt docs have score fields)');
db.activity_events.aggregate([
  { $match: { type: 'quiz_attempt' } },
  { $group: { _id: '$courseCode', attempts: { $sum: 1 },
              avgPct: { $avg: { $multiply: [{ $divide: ['$score', '$maxScore'] }, 100] } },
              avgMinutes: { $avg: { $divide: ['$durationSec', 60] } } } },
  { $project: { attempts: 1, avgPct: { $round: ['$avgPct', 1] }, avgMinutes: { $round: ['$avgMinutes', 1] } } },
  { $sort: { _id: 1 } }
]).forEach(d => printjson(d));

// ---------------------------------------------------------------------
section('Q9 FEEDBACK: text search + average of whatever questions each course asked');
db.course_feedback.find(
  { $text: { $search: 'practical lab' } },
  { _id: 0, courseCode: 1, comment: 1, relevance: { $meta: 'textScore' } }
).sort({ relevance: { $meta: 'textScore' } }).limit(5).forEach(d => printjson(d));

db.course_feedback.aggregate([
  { $project: { courseCode: 1, r: { $objectToArray: '$ratings' } } },   // keys differ per course
  { $unwind: '$r' },
  { $group: { _id: { course: '$courseCode', question: '$r.k' }, avg: { $avg: '$r.v' }, n: { $sum: 1 } } },
  { $sort: { '_id.question': 1 } },
  { $group: { _id: '$_id.course', questions: { $push: { q: '$_id.question', avg: { $round: ['$avg', 2] }, n: '$n' } } } },
  { $sort: { _id: 1 } }
]).forEach(d => printjson(d));

// ---------------------------------------------------------------------
section('Q10 KEY-VALUE: session lookup by token, sliding expiry');
const token = db.portal_sessions.findOne({}, { _id: 1 })._id;
printjson(db.portal_sessions.findOne({ _id: token }));
db.portal_sessions.updateOne({ _id: token }, { $set: { expiresAt: new Date(Date.now() + 30 * 60 * 1000) } });
const kvPlan = db.portal_sessions.find({ _id: token }).explain().queryPlanner.winningPlan;
print(`Lookup by key uses plan stage: ${(kvPlan.queryPlan || kvPlan).stage}  (IDHACK = direct _id lookup)`);

// ---------------------------------------------------------------------
section('Q11 INDEX ANALYSIS: latest 10 quiz attempts of one student, index vs collection scan');
function stages(p) { const out = []; let n = p.queryPlan || p; while (n) { out.push(n.stage); n = n.inputStage; } return out.join(' <- '); }
function report(label, e) {
  const s = e.executionStats;
  print(`${label.padEnd(22)} plan=${stages(e.queryPlanner.winningPlan)}`);
  print(`${''.padEnd(22)} keysExamined=${s.totalKeysExamined} docsExamined=${s.totalDocsExamined} returned=${s.nReturned} timeMs=${s.executionTimeMillis}`);
}
const q = { studentId: 'CFU/2025/00004', type: 'quiz_attempt' };
report('With ix_events_*:', db.activity_events.find(q).sort({ ts: -1 }).limit(10).explain('executionStats'));
report('Forced COLLSCAN:', db.activity_events.find(q).sort({ ts: -1 }).limit(10).hint({ $natural: 1 }).explain('executionStats'));

// ---------------------------------------------------------------------
section('Q12 DELETE: purge login events older than 60 days (TTL would do this at 180 days)');
const del = db.activity_events.deleteMany({ type: 'login', ts: { $lt: new Date(Date.now() - 60 * DAY) } });
print(`deletedCount=${del.deletedCount}; remaining events=${db.activity_events.countDocuments()}`);
