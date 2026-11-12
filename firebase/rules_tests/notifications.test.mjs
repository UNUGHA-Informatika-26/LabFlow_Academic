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
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';
import { FIRESTORE_HOST, FIRESTORE_PORT } from './emulator_config.mjs';

const rules = readFileSync(resolve('../../firebase/firestore.rules'), 'utf8');
let environment;
const clients = {};

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-labflow-notifications-rules',
    firestore: { rules, host: FIRESTORE_HOST, port: FIRESTORE_PORT },
  });
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [uid, role] of [
      ['student-1', 'student'],
      ['lab-admin-1', 'lab_admin'],
      ['superadmin-1', 'superadmin'],
      ['outsider', 'student'],
    ]) {
      await setDoc(doc(db, 'users', uid), { role, status: 'active' });
    }
    for (const [uid, role] of [
      ['student-1', 'student'],
      ['lab-admin-1', 'lab_admin'],
      ['superadmin-1', 'superadmin'],
    ]) {
      await setDoc(doc(db, 'notifications', `notice-${uid}`), {
        recipientId: uid,
        recipientRole: role,
        title: 'Pembaruan',
        body: 'Pembaruan tersedia.',
        isRead: false,
        read: false,
      });
    }
    await setDoc(doc(db, 'notifications', 'legacy-student'), {
      studentId: 'student-1', read: false,
    });
  });
  for (const uid of ['student-1', 'lab-admin-1', 'superadmin-1', 'outsider']) {
    clients[uid] = environment.authenticatedContext(uid).firestore();
  }
});

test('all three roles can query and mark only their own notifications read', async () => {
  for (const uid of ['student-1', 'lab-admin-1', 'superadmin-1']) {
    const own = query(
      collection(clients[uid], 'notifications'),
      where('recipientId', '==', uid),
    );
    const result = await assertSucceeds(getDocs(own));
    assert.equal(result.size, 1);
    await assertSucceeds(updateDoc(doc(clients[uid], 'notifications', `notice-${uid}`), {
      isRead: true,
      read: true,
    }));
    await assertFails(getDoc(doc(clients[uid], 'notifications', `notice-${uid === 'student-1' ? 'lab-admin-1' : 'student-1'}`)));
    await assertFails(updateDoc(doc(clients[uid], 'notifications', `notice-${uid}`), {
      title: 'tampered',
    }));
    await assertFails(setDoc(doc(clients[uid], 'notifications', 'client-created'), {
      recipientId: uid,
    }));
  }
});

test('legacy Student notification remains readable and can be marked read', async () => {
  await assertSucceeds(getDoc(doc(clients['student-1'], 'notifications', 'legacy-student')));
  await assertSucceeds(updateDoc(doc(clients['student-1'], 'notifications', 'legacy-student'), {
    read: true,
  }));
  await assertFails(getDoc(doc(clients.outsider, 'notifications', 'legacy-student')));
});

test('notification read state is private per account and clients cannot forge feed events', async () => {
  const ownState = doc(clients['student-1'], 'users', 'student-1', 'notification_states', 'event-abc');
  await assertSucceeds(setDoc(ownState, { isRead: true, readAt: serverTimestamp() }));
  await assertSucceeds(getDoc(ownState));
  await assertFails(getDoc(doc(clients.outsider, 'users', 'student-1', 'notification_states', 'event-abc')));
  await assertFails(setDoc(doc(clients['student-1'], 'users', 'student-1', 'notification_states', 'forged'), {
    isRead: false, readAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(clients['student-1'], 'notifications', 'forged-event'), {
    recipientId: 'student-1', title: 'Forged', body: 'Fake event',
  }));
});

test('FCM token records are private to the owning active account and schema-checked', async () => {
  const tokenRef = doc(clients['student-1'], 'users', 'student-1', 'fcmTokens', 'token-hash');
  await assertSucceeds(setDoc(tokenRef, {
    fid: 'firebase-installation-id-long-enough-for-validation',
    platform: 'android',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(tokenRef));
  await assertSucceeds(updateDoc(tokenRef, { updatedAt: serverTimestamp() }));
  await assertSucceeds((await import('firebase/firestore')).deleteDoc(tokenRef));
  await assertFails(getDoc(doc(clients.outsider, 'users', 'student-1', 'fcmTokens', 'token-hash')));
  await assertFails(setDoc(doc(clients['student-1'], 'users', 'student-1', 'fcmTokens', 'bad-token'), {
    fid: 'short', platform: 'android', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(clients['student-1'], 'users', 'student-1', 'fcmTokens', 'extra-field'), {
    fid: 'firebase-installation-id-long-enough-for-validation', platform: 'android',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ownerRole: 'superadmin',
  }));
});

after(async () => environment?.cleanup());
