// =====================================================================
// Portfolio 4 - File: 02_load_students.js
// Purpose: Import the student documents exported from PostgreSQL
//          (data/students.ndjson, one JSON document per line).
// =====================================================================

db = db.getSiblingDB('crestfield_nosql');
const fs = require('fs');
const path = '/portfolio/portfolio-4-nosql/data/students.ndjson';

const docs = fs.readFileSync(path, 'utf8')
  .split('\n')
  .filter(line => line.trim().length > 0)
  .map(line => {
    const d = JSON.parse(line);
    d.dateOfBirth = new Date(d.dateOfBirth);   // JSON has no date type, so convert to BSON Date
    d.migratedAt  = new Date();
    return d;
  });

const res = db.students.insertMany(docs, { ordered: true });
print(`Inserted ${Object.keys(res.insertedIds).length} student documents from ${path}`);

print('\nSample document (CFU/2025/00001):');
printjson(db.students.findOne({ _id: 'CFU/2025/00001' }));

const s = db.students.stats();
print(`\nstudents: count=${s.count}, avgObjSize=${s.avgObjSize} bytes, storageSize=${s.storageSize} bytes`);
