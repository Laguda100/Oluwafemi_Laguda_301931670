// =====================================================================
// Portfolio 4 - File: 05_validation_tests.js
// Purpose: Prove the $jsonSchema validator and unique index reject bad
//          documents. Expected: every line starts with PASS.
// =====================================================================

db = db.getSiblingDB('crestfield_nosql');

function validStudent() {
  return {
    _id: 'CFU/2026/09999',
    name: { first: 'Test', last: 'Student' },
    email: 'test.student@students.crestfield.edu.ng',
    gender: 'F', entryYear: 2026, currentLevel: 100, status: 'ACTIVE',
    programme: { code: 'BSC-CSC', name: 'B.Sc. Computer Science', department: 'Computer Science',
                 faculty: 'Faculty of Computing and Applied Sciences' },
    transcript: [], cgpa: null
  };
}
const oneCourse = c => [{ session: '2026/2027', semester: 1, courses: [c] }];

function expectReject(label, fn) {
  try {
    fn();
    print(`FAIL  ${label}: was accepted`);
    db.students.deleteMany({ _id: { $in: ['CFU/2026/09999', 'CFU/2026/09998'] } });
  } catch (e) {
    print(`PASS  ${label}: rejected (code ${e.code} ${e.codeName || ''})`);
  }
}

expectReject('N1 exam score 85 (> 70)', () => {
  const d = validStudent();
  d.transcript = oneCourse({ code: 'CSC 101', units: 3, ca: 20, exam: 85, total: 105, grade: 'A', gradePoint: 5 });
  db.students.insertOne(d);
});
expectReject('N2 invalid matric number', () => {
  const d = validStudent(); d._id = 'CFU-2026-1'; db.students.insertOne(d);
});
expectReject('N3 missing required field programme', () => {
  const d = validStudent(); delete d.programme; db.students.insertOne(d);
});
expectReject('N4 grade letter G not in enum', () => {
  const d = validStudent();
  d.transcript = oneCourse({ code: 'CSC 101', units: 3, ca: 20, exam: 50, total: 70, grade: 'G', gradePoint: 5 });
  db.students.insertOne(d);
});
expectReject('N5 duplicate email (unique index)', () => {
  const d = validStudent(); d._id = 'CFU/2026/09998';
  d.email = db.students.findOne({ _id: 'CFU/2025/00001' }).email;
  db.students.insertOne(d);
});
expectReject('N6 update an existing exam score to 90', () => {
  db.students.updateOne({ _id: 'CFU/2025/00002' }, { $set: { 'transcript.0.courses.0.exam': 90 } });
});

try {
  db.students.insertOne(validStudent());
  print('PASS  N7 valid document accepted (then deleted)');
  db.students.deleteOne({ _id: 'CFU/2026/09999' });
} catch (e) {
  print(`FAIL  N7 valid document rejected: ${e.message}`);
}
