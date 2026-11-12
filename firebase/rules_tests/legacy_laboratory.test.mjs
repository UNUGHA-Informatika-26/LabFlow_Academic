import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteField,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';
import { FIRESTORE_HOST, FIRESTORE_PORT } from './emulator_config.mjs';

const rules = readFileSync(resolve('../../firebase/firestore.rules'), 'utf8');
let environment;
let superadmin;
let labAdmin;
let student;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'labflow-legacy-lab-rules-test',
    firestore: { rules, host: FIRESTORE_HOST, port: FIRESTORE_PORT },
  });
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    for (const [uid, role] of [
      ['superadmin-1', 'superadmin'],
      ['lab-admin-1', 'lab_admin'],
      ['student-1', 'student'],
    ]) {
      await setDoc(doc(firestore, 'users', uid), {
        uid,
        email: `${uid}@example.invalid`,
        fullName: uid,
        role,
        status: 'active',
      });
    }

    // Seed a legacy laboratory document with:
    // - legacy code ('IOT') not matching ^LAB-[A-Z0-9]+-[0-9]{2}$
    // - short legacy name ('M')
    // - extra legacy field ('legacyNote')
    // - missing createdAt
    await setDoc(doc(firestore, 'laboratories', 'legacy-lab'), {
      name: 'M',
      code: 'IOT',
      description: 'Laboratorium Legacy Versi Awal',
      location: 'Gedung Lama',
      status: 'active',
      legacyNote: 'Data lama yang tetap aman',
    });
  });

  superadmin = environment.authenticatedContext('superadmin-1').firestore();
  labAdmin = environment.authenticatedContext('lab-admin-1').firestore();
  student = environment.authenticatedContext('student-1').firestore();
});

after(async () => {
  await environment?.cleanup();
});

test('superadmin can update unrelated fields on legacy laboratory without migrating legacy code or name', async () => {
  await assertSucceeds(
    updateDoc(doc(superadmin, 'laboratories', 'legacy-lab'), {
      status: 'inactive',
      location: 'Gedung FMIKOM Lantai 3',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('superadmin cannot set a new invalid code, short name, or empty location on legacy laboratory', async () => {
  await assertFails(
    updateDoc(doc(superadmin, 'laboratories', 'legacy-lab'), {
      code: 'INVALID-CODE',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(superadmin, 'laboratories', 'legacy-lab'), {
      name: 'AB',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(superadmin, 'laboratories', 'legacy-lab'), {
      location: '',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(superadmin, 'laboratories', 'legacy-lab'), {
      unexpectedField: 'injected',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('superadmin can upgrade legacy laboratory code and name to valid standard format', async () => {
  await assertSucceeds(
    updateDoc(doc(superadmin, 'laboratories', 'legacy-lab'), {
      name: 'Laboratorium IoT Terpadu',
      code: 'LAB-IOT-01',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('new laboratory creation strictly requires valid format and non-superadmin cannot modify laboratories', async () => {
  await assertSucceeds(
    setDoc(doc(superadmin, 'laboratories', 'new-valid-lab'), {
      name: 'Laboratorium Jaringan',
      code: 'LAB-JAR-01',
      description: 'Praktikum Jaringan',
      location: 'Gedung B',
      status: 'active',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );

  await assertFails(
    setDoc(doc(superadmin, 'laboratories', 'new-invalid-lab'), {
      name: 'Laboratorium Baru',
      code: 'JAR-01',
      description: 'Kode salah',
      location: 'Gedung B',
      status: 'active',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );

  await assertFails(
    updateDoc(doc(labAdmin, 'laboratories', 'legacy-lab'), {
      status: 'active',
      updatedAt: serverTimestamp(),
    }),
  );

  await assertFails(
    updateDoc(doc(student, 'laboratories', 'legacy-lab'), {
      status: 'active',
      updatedAt: serverTimestamp(),
    }),
  );

  // Extra field injection on create must be rejected:
  await assertFails(
    setDoc(doc(superadmin, 'laboratories', 'new-extra-field-lab'), {
      name: 'Laboratorium Jaringan 2',
      code: 'LAB-JAR-02',
      description: 'Praktikum Jaringan',
      location: 'Gedung B',
      status: 'active',
      extraIllegalField: 'illegal',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );

  // Deleting required fields or mutating createdAt on update must be rejected:
  await assertFails(
    updateDoc(doc(superadmin, 'laboratories', 'new-valid-lab'), {
      name: deleteField(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(superadmin, 'laboratories', 'new-valid-lab'), {
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  // Updating without updatedAt timestamp must be rejected:
  await assertFails(
    updateDoc(doc(superadmin, 'laboratories', 'new-valid-lab'), {
      location: 'Gedung C Tanpa Timestamp',
    }),
  );

  assert.ok(environment);
});
