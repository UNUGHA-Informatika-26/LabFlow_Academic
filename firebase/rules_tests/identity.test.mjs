import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, writeBatch, Timestamp } from 'firebase/firestore';
import { FIRESTORE_HOST, FIRESTORE_PORT } from './emulator_config.mjs';

const rules = readFileSync(resolve('../../firebase/firestore.rules'), 'utf8');
let env;
let studentDb;

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-labflow-identity-rules', firestore: { rules, host: FIRESTORE_HOST, port: FIRESTORE_PORT } });
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', 'student-1'), { role: 'student', status: 'active', fullName: 'Nama Asli' });
    await setDoc(doc(db, 'laboratories', 'lab-1'), { status: 'active' });
    await setDoc(doc(db, 'assets', 'asset-doc-1'), { labId: 'lab-1', name: 'ESP32 S3', code: 'ESP32-S3-001', status: 'available', condition: 'good', stock: 4 });
  });
  studentDb = env.authenticatedContext('student-1').firestore();
});

test('new borrowing identity and inventory code snapshots must match source documents', async () => {
  const create = async (requestId, studentName, requestedAssetCode) => {
    const batch = writeBatch(studentDb);
    batch.set(doc(studentDb, 'borrow_requests', requestId), {
      requestNumber: 'BRW-2026-TEST01', studentId: 'student-1', studentName,
      labId: 'lab-1', purpose: 'Praktikum', borrowDate: Timestamp.fromDate(new Date('2026-10-28T00:00:00Z')),
      expectedReturnDate: Timestamp.fromDate(new Date('2026-10-29T00:00:00Z')), status: 'pending',
      studentNote: null, approvedBy: null, approvedAt: null, rejectionReason: null,
      createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    });
    batch.set(doc(studentDb, 'borrow_requests', requestId, 'items', 'item-1'), {
      itemId: 'asset-doc-1', itemName: 'ESP32 S3', quantity: 1,
      requestedAssetId: 'asset-doc-1', requestedAssetCode,
    });
    await batch.commit();
  };
  await assertSucceeds(create('valid-request', 'Nama Asli', 'ESP32-S3-001'));
  await assertFails(create('forged-name', 'Nama Palsu', 'ESP32-S3-001'));
  await assertFails(create('forged-code', 'Nama Asli', 'asset-doc-1'));
});

after(async () => env?.cleanup());
