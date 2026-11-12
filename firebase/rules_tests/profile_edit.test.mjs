import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';
import { FIRESTORE_HOST, FIRESTORE_PORT } from './emulator_config.mjs';

const rules = readFileSync(resolve('../../firebase/firestore.rules'), 'utf8');
let environment;
let student;
let labAdmin;
let superadmin;
let outsider;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'labflow-profile-rules-test',
    firestore: { rules, host: FIRESTORE_HOST, port: FIRESTORE_PORT },
  });
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    for (const [uid, role] of [
      ['student-1', 'student'],
      ['student-2', 'student'],
      ['lab-admin-1', 'lab_admin'],
      ['superadmin-1', 'superadmin'],
    ]) {
      await setDoc(doc(firestore, 'users', uid), {
        uid,
        email: `${uid}@example.invalid`,
        fullName: uid,
        role,
        status: 'active',
      });
    }
    await setDoc(doc(firestore, 'users', 'lab-admin-outsider'), {
      uid: 'lab-admin-outsider', role: 'lab_admin', status: 'active',
    });
    await setDoc(
      doc(firestore, 'lab_memberships', 'lab-admin-1__lab-1'),
      { userId: 'lab-admin-1', labId: 'lab-1', role: 'lab_admin', active: true },
    );
    await setDoc(doc(firestore, 'reports', 'report-1'), {
      reporterId: 'student-1', labId: 'lab-1',
    });
  });
  student = environment.authenticatedContext('student-1').firestore();
  labAdmin = environment.authenticatedContext('lab-admin-1').firestore();
  superadmin = environment.authenticatedContext('superadmin-1').firestore();
  outsider = environment.authenticatedContext('lab-admin-outsider').firestore();
});

test('report participants can create valid text, image, and mixed messages only', async () => {
  const message = (id, data) => {
    const omitImage = data.omitImage === true;
    const fields = { ...data };
    delete fields.omitImage;
    const payload = {
      senderId: 'student-1', senderRole: 'student', senderName: 'Student Demo',
      text: '', type: 'image', imageUrl: 'https://res.cloudinary.com/demo/image/upload/chat.jpg',
      createdAt: serverTimestamp(), deletedAt: null, ...fields,
    };
    if (omitImage) delete payload.imageUrl;
    return setDoc(doc(student, 'reports', 'report-1', 'messages', id), payload);
  };
  await assertSucceeds(message('image-1', {}));
  await assertSucceeds(message('text-1', {
    text: 'Pesan lama tetap didukung', type: 'text', omitImage: true,
  }));
  await assertSucceeds(message('mixed-1', { text: 'Caption', type: 'mixed' }));
  await assertFails(message('empty-1', { text: '', type: 'text', omitImage: true }));
  await assertFails(message('image-no-url', { type: 'image', omitImage: true }));
  await assertFails(message('long-text', { text: 'x'.repeat(1001), type: 'text', omitImage: true }));
  await assertFails(message('bad-type', { type: 'video' }));
  await assertFails(message('forged', { senderId: 'student-2' }));
  await assertFails(message('extra', { unsafeField: true }));
  await assertFails(setDoc(doc(outsider, 'reports', 'report-1', 'messages', 'outsider'), {
    senderId: 'lab-admin-outsider', senderRole: 'lab_admin', text: 'blocked',
    type: 'text', createdAt: serverTimestamp(), deletedAt: null,
  }));
});

test('legacy text message remains soft-deletable without new optional fields', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'reports', 'report-1', 'messages', 'legacy'), {
      senderId: 'student-1', senderRole: 'student', text: 'Old schema',
      createdAt: new Date(), deletedAt: null,
    });
  });
  await assertSucceeds(updateDoc(
    doc(student, 'reports', 'report-1', 'messages', 'legacy'),
    { deletedAt: serverTimestamp() },
  ));
});

after(async () => {
  await environment?.cleanup();
});

test('student may edit own academic profile fields but not protected identity', async () => {
  await assertSucceeds(
    updateDoc(doc(student, 'users', 'student-1'), { fullName: 'Nama Baru' }),
  );
  await assertFails(
    updateDoc(doc(student, 'users', 'student-1'), { role: 'lab_admin' }),
  );
  await assertSucceeds(updateDoc(doc(student, 'users', 'student-1'), { phoneNumber: '+62 812 1234' }));
  await assertSucceeds(updateDoc(doc(student, 'users', 'student-1'), { profilePhotoUrl: 'https://res.cloudinary.com/example/image/upload/avatar.jpg' }));
  await assertSucceeds(updateDoc(doc(student, 'users', 'student-1'), { profilePhotoUrl: null }));
  await assertSucceeds(updateDoc(doc(student, 'users', 'student-1'), { nim: '000123' }));
  await assertSucceeds(updateDoc(doc(student, 'users', 'student-1'), { studyProgram: 'Informatika' }));
  await assertSucceeds(updateDoc(doc(student, 'users', 'student-1'), { semester: 14 }));
  await assertSucceeds(updateDoc(doc(student, 'users', 'student-1'), { semester: null }));
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), { semester: 15 }));
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), { nim: '   ' }));
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), { studyProgram: ' ' }));
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), { nip: 'ATTACK' }));
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), { nidn: 'ATTACK' }));
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), { email: 'attacker@example.invalid' }));
  await assertFails(
    updateDoc(doc(student, 'users', 'student-1'), { status: 'active-again' }),
  );
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), { phoneNumber: '1'.repeat(21) }));
  await assertFails(updateDoc(doc(student, 'users', 'student-1'), { extraField: true }));
  await assertFails(
    updateDoc(doc(student, 'users', 'student-1'), { uid: 'someone-else' }),
  );
  await assertFails(
    updateDoc(doc(student, 'users', 'student-1'), { fullName: '   ' }),
  );
  await assertFails(
    updateDoc(doc(student, 'users', 'student-2'), { fullName: 'Hijacked' }),
  );
});

test('lab admin may edit own staff identity but not student identity or membership', async () => {
  await assertSucceeds(
    updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), {
      fullName: 'Admin Lab Baru',
    }),
  );
  await assertSucceeds(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { phoneNumber: '+62 812' }));
  await assertSucceeds(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { profilePhotoUrl: null }));
  await assertSucceeds(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { nip: '000123' }));
  await assertSucceeds(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { nidn: '001234' }));
  await assertFails(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { nim: 'ATTACK' }));
  await assertFails(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { semester: 2 }));
  await assertFails(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { studyProgram: 'Attack' }));
  await assertFails(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { email: 'attacker@example.invalid' }));
  await assertFails(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { role: 'student' }));
  await assertFails(updateDoc(doc(labAdmin, 'users', 'lab-admin-1'), { status: 'disabled' }));
  await assertFails(
    updateDoc(doc(labAdmin, 'lab_memberships', 'lab-admin-1__lab-1'), {
      active: false,
    }),
  );
});

test('superadmin retains administrative update permission', async () => {
  await assertSucceeds(
    updateDoc(doc(superadmin, 'users', 'student-2'), {
      fullName: 'Diperbarui Admin',
    }),
  );
  await assertSucceeds(updateDoc(doc(superadmin, 'users', 'student-2'), {
    nim: 'STU-DEMO-002', studyProgram: 'Demo', semester: 2,
  }));
  await assertSucceeds(updateDoc(doc(superadmin, 'users', 'lab-admin-1'), {
    nip: 'DEMO-001', nidn: 'DEMO-002',
  }));
  await assertSucceeds(updateDoc(doc(superadmin, 'users', 'superadmin-1'), {
    fullName: 'Superadmin Baru', phoneNumber: '+62 800',
    profilePhotoUrl: 'https://res.cloudinary.com/example/image/upload/avatar.jpg',
  }));
  await assertFails(updateDoc(doc(superadmin, 'users', 'superadmin-1'), { nim: 'NO' }));
  assert.ok(environment);
});
