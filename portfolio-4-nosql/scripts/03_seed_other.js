// =====================================================================
// Portfolio 4 - File: 03_seed_other.js
// Purpose: Seed the other four collections:
//   courses (graph), activity_events (50,000 events), course_feedback,
//   portal_sessions (key-value).
// A seeded pseudo-random generator (mulberry32) makes the content
// repeatable; event timestamps are relative to "now" so the TTL index
// does not delete them.
// =====================================================================

db = db.getSiblingDB('crestfield_nosql');

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = mulberry32(8103);
const pick = arr => arr[Math.floor(rand() * arr.length)];
const randInt = (min, max) => min + Math.floor(rand() * (max - min + 1));

// ---------------------------------------------------------------------
// 1. courses: prerequisite graph (edges stored on the child course)
// ---------------------------------------------------------------------
db.courses.insertMany([
  { _id: 'CSC 101', title: 'Introduction to Computing Sciences', units: 3, level: 100, prerequisites: [] },
  { _id: 'CSC 102', title: 'Introduction to Programming',        units: 3, level: 100, prerequisites: ['CSC 101'] },
  { _id: 'MTH 101', title: 'Elementary Mathematics I',           units: 3, level: 100, prerequisites: [] },
  { _id: 'MTH 102', title: 'Elementary Mathematics II',          units: 3, level: 100, prerequisites: ['MTH 101'] },
  { _id: 'CSC 201', title: 'Data Structures and Algorithms',     units: 3, level: 200, prerequisites: ['CSC 102', 'MTH 102'] },
  { _id: 'CSC 203', title: 'Database Systems I',                 units: 3, level: 200, prerequisites: ['CSC 102'] },
  { _id: 'MTH 201', title: 'Linear Algebra I',                   units: 3, level: 200, prerequisites: ['MTH 102'] },
  { _id: 'CSC 310', title: 'Operating Systems',                  units: 3, level: 300, prerequisites: ['CSC 201'] },
  { _id: 'CSC 313', title: 'Database Systems II',                units: 3, level: 300, prerequisites: ['CSC 203', 'CSC 201'] },
  { _id: 'CSC 410', title: 'Advanced Database Systems',          units: 3, level: 400, prerequisites: ['CSC 313', 'MTH 201'] },
  { _id: 'ACC 101', title: 'Principles of Accounting I',         units: 3, level: 100, prerequisites: [] },
  { _id: 'ACC 201', title: 'Financial Accounting I',             units: 3, level: 200, prerequisites: ['ACC 101'] },
  { _id: 'ECO 101', title: 'Principles of Economics I',          units: 2, level: 100, prerequisites: [] },
  { _id: 'ECO 201', title: 'Microeconomic Theory I',             units: 3, level: 200, prerequisites: ['ECO 101', 'MTH 101'] }
]);
print(`courses: ${db.courses.countDocuments()}`);

// ---------------------------------------------------------------------
// 2. activity_events: 50,000 events. The four event types have DIFFERENT
//    fields; a relational table would need many NULL columns or 4 tables.
// ---------------------------------------------------------------------
const students = db.students.find({}, { _id: 1, 'programme.code': 1 }).toArray();
const currentCourses = {
  'BSC-CSC': ['CSC 201', 'CSC 203', 'MTH 201'],
  'BSC-MTH': ['MTH 201', 'CSC 203'],
  'BSC-ACC': ['ACC 201', 'ECO 201'],
  'BSC-ECO': ['ECO 201', 'ACC 201']
};
const now = Date.now();
const DAY = 24 * 3600 * 1000;
const TOTAL_EVENTS = 50000;
let batch = [];

for (let i = 0; i < TOTAL_EVENTS; i++) {
  const st = pick(students);
  const course = pick(currentCourses[st.programme.code]);
  const ts = new Date(now - Math.floor(rand() * 90 * DAY));     // last 90 days
  const r = rand();
  let ev;
  if (r < 0.30) {
    ev = { type: 'login', device: pick(['android', 'iphone', 'windows', 'macos', 'linux']),
           ip: `10.${randInt(0, 255)}.${randInt(0, 255)}.${randInt(1, 254)}` };
  } else if (r < 0.65) {
    ev = { type: 'material_download', courseCode: course,
           material: { id: `MAT-${randInt(1, 40)}`, fileType: pick(['pdf', 'pptx', 'mp4']), sizeKb: randInt(200, 90000) } };
  } else if (r < 0.85) {
    const maxScore = pick([10, 20]);
    ev = { type: 'quiz_attempt', courseCode: course, quizId: `Q${randInt(1, 8)}`,
           score: randInt(Math.floor(maxScore * 0.3), maxScore), maxScore,
           durationSec: randInt(120, 1800), attempt: randInt(1, 3) };
  } else {
    ev = { type: 'forum_post', courseCode: course, threadId: `T-${randInt(1, 60)}`,
           wordCount: randInt(5, 400), hasAttachment: rand() < 0.1 };
  }
  batch.push(Object.assign({ studentId: st._id, ts }, ev));
  if (batch.length === 5000) {          // bulk insert in batches of 5,000
    db.activity_events.insertMany(batch);
    batch = [];
  }
}
if (batch.length) db.activity_events.insertMany(batch);
print(`activity_events: ${db.activity_events.countDocuments()}`);

// ---------------------------------------------------------------------
// 3. course_feedback: each course asks different questions.
// ---------------------------------------------------------------------
const questionSets = {
  'CSC 101': ['clarity', 'pace', 'materials'],
  'CSC 102': ['clarity', 'pace', 'labEquipment', 'labSupport'],    // practical course
  'MTH 101': ['clarity', 'pace', 'tutorials'],
  'MTH 102': ['clarity', 'pace', 'tutorials'],
  'ACC 101': ['clarity', 'materials', 'realWorldExamples'],
  'ECO 101': ['clarity', 'materials', 'realWorldExamples']
};
const comments = [
  'The practical lab sessions helped me understand the topics',
  'Lectures were clear but the pace was too fast',
  'More tutorial questions before the exam would help',
  'Lab computers were often not working',
  'Excellent real world examples from Nigerian companies',
  'Course materials were uploaded late',
  'The lecturer explained difficult concepts patiently',
  'Too much content for a two unit course',
  'Group projects were useful and practical',
  'Please provide past questions for revision'
];
const feedback = [];
for (const [courseCode, questions] of Object.entries(questionSets)) {
  const n = randInt(15, 25);
  for (let i = 0; i < n; i++) {
    const ratings = {};
    questions.forEach(q => { ratings[q] = randInt(1, 5); });
    const doc = { courseCode, session: '2025/2026', ratings, submittedAt: new Date(now - randInt(200, 300) * DAY + randInt(0, 90) * DAY) };
    if (rand() < 0.7) doc.comment = pick(comments);         // comment is optional
    if (rand() < 0.2) doc.wouldRecommend = rand() < 0.75;   // only some forms had this question
    feedback.push(doc);
  }
}
db.course_feedback.insertMany(feedback);
print(`course_feedback: ${db.course_feedback.countDocuments()}`);

// ---------------------------------------------------------------------
// 4. portal_sessions: key-value pairs (token -> session data), 30 min life.
// ---------------------------------------------------------------------
const sessions = students.slice(0, 5).map((st, i) => ({
  _id: `tok_${(8103 + i).toString(16)}_${st._id.replace(/\//g, '')}`,
  studentId: st._id,
  roles: ['student'],
  createdAt: new Date(now),
  expiresAt: new Date(now + 30 * 60 * 1000)
}));
db.portal_sessions.insertMany(sessions);
print(`portal_sessions: ${db.portal_sessions.countDocuments()}`);
