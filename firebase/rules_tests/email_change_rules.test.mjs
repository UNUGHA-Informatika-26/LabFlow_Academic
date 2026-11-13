import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, serverTimestamp } from 'firebase/firestore';
import { FIRESTORE_HOST, FIRESTORE_PORT } from './emulator_config.mjs';

const rules = readFileSync(resolve('../../firebase/firestore.rules'), 'utf8');
let environment;
let superadmin;
let student;
let labAdmin;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'labflow-email-change-rules-test',
    firestore: { rules, host: FIRESTORE_HOST, port: FIRESTORE_PORT },
  });

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'superadmin-1'), {
      uid: 'superadmin-1', role: 'superadmin', status: 'active', fullName: 'Super Admin',
      email: 'admin@labflow.test', emailVerified: true,
    });
    await setDoc(doc(context.firestore(), 'users', 'student-1'), {
      uid: 'student-1', role: 'student', status: 'active', fullName: 'Student One',
      email: 'student1@labflow.test', emailVerified: true,
    });
    await setDoc(doc(context.firestore(), 'users', 'labadmin-1'), {
      uid: 'labadmin-1', role: 'lab_admin', status: 'active', fullName: 'Lab Admin One',
      email: 'labadmin1@labflow.test', emailVerified: true,
    });
  });

  superadmin = environment.authenticatedContext('superadmin-1').firestore();
  student = environment.authenticatedContext('student-1').firestore();
  labAdmin = environment.authenticatedContext('labadmin-1').firestore();
});

test('Student can create email change request for own UID with status pending', async () => {
  await assertSucceeds(setDoc(doc(student, 'email_change_requests', 'req-1'), {
    uid: 'student-1',
    currentEmail: 'student1@labflow.test',
    requestedEmail: 'newstudent@labflow.test',
    reason: 'Alamat email lama sudah tidak aktif',
    status: 'pending',
    requestedAt: new Date(),
  }));
});

test('Student CANNOT create email change request for other UID or pre-approve it', async () => {
  // Other UID
  await assertFails(setDoc(doc(student, 'email_change_requests', 'req-forged-uid'), {
    uid: 'superadmin-1',
    currentEmail: 'admin@labflow.test',
    requestedEmail: 'forged@labflow.test',
    reason: 'Alasan penipuan identitas pengguna',
    status: 'pending',
    requestedAt: new Date(),
  }));

  // Pre-approve status
  await assertFails(setDoc(doc(student, 'email_change_requests', 'req-preapproved'), {
    uid: 'student-1',
    currentEmail: 'student1@labflow.test',
    requestedEmail: 'newstudent@labflow.test',
    reason: 'Alasan permohonan mandiri',
    status: 'approved',
    requestedAt: new Date(),
  }));
});

test('Superadmin can approve or reject pending request, but Lab Admin or Student cannot', async () => {
  // Student tries to approve
  await assertFails(updateDoc(doc(student, 'email_change_requests', 'req-1'), {
    status: 'approved',
    reviewedBy: 'student-1',
    reviewedAt: new Date(),
  }));

  // Lab admin tries to approve
  await assertFails(updateDoc(doc(labAdmin, 'email_change_requests', 'req-1'), {
    status: 'approved',
    reviewedBy: 'labadmin-1',
    reviewedAt: new Date(),
  }));

  // Superadmin approves
  await assertSucceeds(updateDoc(doc(superadmin, 'email_change_requests', 'req-1'), {
    status: 'approved',
    reviewedBy: 'superadmin-1',
    reviewedAt: new Date(),
  }));
});

test('Superadmin cannot modify original requestedEmail or reason during review', async () => {
  // Setup another pending request
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'email_change_requests', 'req-2'), {
      uid: 'student-1',
      currentEmail: 'student1@labflow.test',
      requestedEmail: 'original@labflow.test',
      reason: 'Alasan permohonan asli',
      status: 'pending',
      requestedAt: new Date(),
    });
  });

  await assertFails(updateDoc(doc(superadmin, 'email_change_requests', 'req-2'), {
    status: 'approved',
    requestedEmail: 'tampered@labflow.test',
    reviewedBy: 'superadmin-1',
    reviewedAt: new Date(),
  }));
});

test('Requester CANNOT complete request if auth token email_verified is false', async () => {
  const studentUnverified = environment.authenticatedContext('student-1', {
    email: 'newstudent@labflow.test',
    email_verified: false,
  }).firestore();

  await assertFails(updateDoc(doc(studentUnverified, 'email_change_requests', 'req-1'), {
    status: 'completed',
    completedAt: serverTimestamp(),
  }));
});

test('Requester CANNOT complete request if auth token email differs from requestedEmail', async () => {
  const studentMismatched = environment.authenticatedContext('student-1', {
    email: 'other@labflow.test',
    email_verified: true,
  }).firestore();

  await assertFails(updateDoc(doc(studentMismatched, 'email_change_requests', 'req-1'), {
    status: 'completed',
    completedAt: serverTimestamp(),
  }));
});

test('Requester CANNOT complete request if completedAt is not serverTimestamp', async () => {
  const studentVerified = environment.authenticatedContext('student-1', {
    email: 'newstudent@labflow.test',
    email_verified: true,
  }).firestore();

  await assertFails(updateDoc(doc(studentVerified, 'email_change_requests', 'req-1'), {
    status: 'completed',
    completedAt: new Date(Date.now() - 10000),
  }));
});

test('Requester can complete request only with matching verified auth token and serverTimestamp', async () => {
  const studentVerified = environment.authenticatedContext('student-1', {
    email: 'newstudent@labflow.test',
    email_verified: true,
  }).firestore();

  await assertSucceeds(updateDoc(doc(studentVerified, 'email_change_requests', 'req-1'), {
    status: 'completed',
    completedAt: serverTimestamp(),
  }));
});

test('Email synchronization in users/{userId} requires matching verified Auth token email', async () => {
  // Unverified email fails
  const studentUnverified = environment.authenticatedContext('student-1', {
    email: 'newstudent@labflow.test',
    email_verified: false,
  }).firestore();

  await assertFails(updateDoc(doc(studentUnverified, 'users', 'student-1'), {
    email: 'newstudent@labflow.test',
    emailVerified: true,
    updatedAt: new Date(),
  }));

  // Mismatched token email fails
  const studentMismatched = environment.authenticatedContext('student-1', {
    email: 'other@labflow.test',
    email_verified: true,
  }).firestore();

  await assertFails(updateDoc(doc(studentMismatched, 'users', 'student-1'), {
    email: 'newstudent@labflow.test',
    emailVerified: true,
    updatedAt: new Date(),
  }));
});

test('Email sync is rejected if payload emailVerified is false or updatedAt is invalid', async () => {
  const studentVerified = environment.authenticatedContext('student-1', {
    email: 'newstudent@labflow.test',
    email_verified: true,
  }).firestore();

  // emailVerified on payload false fails
  await assertFails(updateDoc(doc(studentVerified, 'users', 'student-1'), {
    email: 'newstudent@labflow.test',
    emailVerified: false,
    updatedAt: new Date(),
  }));

  // updatedAt not a valid timestamp fails
  await assertFails(updateDoc(doc(studentVerified, 'users', 'student-1'), {
    email: 'newstudent@labflow.test',
    emailVerified: true,
    updatedAt: 'not-a-timestamp',
  }));
});

test('Email sync succeeds when matching verified token and valid payload are provided', async () => {
  const studentVerified = environment.authenticatedContext('student-1', {
    email: 'newstudent@labflow.test',
    email_verified: true,
  }).firestore();

  await assertSucceeds(updateDoc(doc(studentVerified, 'users', 'student-1'), {
    email: 'newstudent@labflow.test',
    emailVerified: true,
    updatedAt: new Date(),
  }));
});

test('Email sync cannot alter user role or status', async () => {
  const studentVerified = environment.authenticatedContext('student-1', {
    email: 'newstudent@labflow.test',
    email_verified: true,
  }).firestore();

  // Try altering role
  await assertFails(updateDoc(doc(studentVerified, 'users', 'student-1'), {
    email: 'newstudent@labflow.test',
    emailVerified: true,
    role: 'superadmin',
    updatedAt: new Date(),
  }));

  // Try altering status
  await assertFails(updateDoc(doc(studentVerified, 'users', 'student-1'), {
    email: 'newstudent@labflow.test',
    emailVerified: true,
    status: 'inactive',
    updatedAt: new Date(),
  }));
});

after(async () => environment?.cleanup());
