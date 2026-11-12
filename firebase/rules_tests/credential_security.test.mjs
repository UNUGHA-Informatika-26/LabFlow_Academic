import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';
import { FIRESTORE_HOST, FIRESTORE_PORT } from './emulator_config.mjs';

const rules = readFileSync(resolve('../../firebase/firestore.rules'), 'utf8');
let environment;
let superadmin;
let student;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'labflow-credential-rules-test',
    firestore: { rules, host: FIRESTORE_HOST, port: FIRESTORE_PORT },
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'superadmin-1'), {
      uid: 'superadmin-1', role: 'superadmin', status: 'active', fullName: 'Admin',
      email: 'admin@example.invalid', emailVerified: true,
    });
    await setDoc(doc(context.firestore(), 'users', 'student-1'), {
      uid: 'student-1', role: 'student', status: 'active', fullName: 'Student',
      email: 'student@example.invalid', emailVerified: true,
    });
  });
  superadmin = environment.authenticatedContext('superadmin-1').firestore();
  student = environment.authenticatedContext('student-1').firestore();
});

test('Superadmin can edit allowed profile fields but not credential fields', async () => {
  await assertSucceeds(updateDoc(doc(superadmin, 'users', 'student-1'), {
    fullName: 'Student Updated', updatedAt: new Date(),
  }));
  await assertFails(updateDoc(doc(superadmin, 'users', 'student-1'), {
    email: 'forged@example.invalid',
  }));
  await assertFails(updateDoc(doc(superadmin, 'users', 'student-1'), {
    pendingEmail: 'pending@example.invalid',
  }));
  await assertFails(updateDoc(doc(superadmin, 'users', 'student-1'), {
    emailVerified: false,
  }));
});

test('user cannot change own credential fields', async () => {
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), {
    email: 'forged@example.invalid',
  }));
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), {
    emailVerified: false,
  }));
});

test('client cannot create credential audit logs', async () => {
  await assertFails(setDoc(doc(superadmin, 'activity_logs', 'forged-credential'), {
    type: 'credential', title: 'Forged', createdAt: new Date(),
  }));
  await assertSucceeds(setDoc(doc(superadmin, 'activity_logs', 'valid-user'), {
    type: 'user', title: 'User update', createdAt: new Date(),
  }));
});

after(async () => environment?.cleanup());
