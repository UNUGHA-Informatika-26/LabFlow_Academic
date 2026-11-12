'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

const projectId = process.env.GCLOUD_PROJECT || 'labflow-academic-2026';
const app = getApps()[0] || initializeApp({ projectId });
const auth = getAuth(app);
const db = getFirestore(app);
const base = `http://127.0.0.1:${process.env.FUNCTIONS_EMULATOR_PORT || '18081'}/${projectId}/us-central1`;

async function createUser(uid, email) {
  await auth.createUser({ uid, email, password: 'TestPassword!123' });
}

async function tokenFor(email) {
  const response = await fetch('http://127.0.0.1:18082/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-key', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'TestPassword!123', returnSecureToken: true }),
  });
  if (!response.ok) assert.fail(await response.text());
  return (await response.json()).idToken;
}

async function call(name, token, data) {
  const response = await fetch(`${base}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ data }),
  });
  return { response, body: await response.json() };
}

test('credential callables use Auth and Firestore emulators with role enforcement and mock email', async () => {
  await createUser('emu-superadmin', 'superadmin@example.test');
  await createUser('emu-superadmin-2', 'superadmin2@example.test');
  await createUser('emu-superadmin-3', 'superadmin3@example.test');
  await createUser('emu-inactive', 'inactive@example.test');
  await createUser('emu-student', 'student@example.test');
  await createUser('emu-target', 'target@example.test');
  await createUser('emu-target-2', 'target2@example.test');
  await db.collection('users').doc('emu-superadmin').set({ role: 'superadmin', status: 'active' });
  await db.collection('users').doc('emu-superadmin-2').set({ role: 'superadmin', status: 'active' });
  await db.collection('users').doc('emu-superadmin-3').set({ role: 'superadmin', status: 'active' });
  await db.collection('users').doc('emu-inactive').set({ role: 'superadmin', status: 'suspended' });
  await db.collection('users').doc('emu-student').set({ role: 'student', status: 'active' });
  await db.collection('users').doc('emu-target').set({ role: 'student', status: 'active', email: 'target@example.test' });
  await db.collection('users').doc('emu-target-2').set({ role: 'student', status: 'active', email: 'target2@example.test' });

  const superToken = await tokenFor('superadmin@example.test');
  const superToken2 = await tokenFor('superadmin2@example.test');
  const superToken3 = await tokenFor('superadmin3@example.test');
  const studentToken = await tokenFor('student@example.test');
  const unauthenticated = await call('adminSendPasswordReset', null, { targetUid: 'emu-target' });
  assert.equal(unauthenticated.response.status, 401);
  const student = await call('adminSendPasswordReset', studentToken, { targetUid: 'emu-target' });
  assert.equal(student.response.status, 403);
  const inactive = await call('adminSendPasswordReset', await tokenFor('inactive@example.test'), { targetUid: 'emu-target' });
  assert.equal(inactive.response.status, 403);
  const reset = await call('adminSendPasswordReset', superToken, { targetUid: 'emu-target' });
  assert.equal(reset.response.status, 200, JSON.stringify(reset.body));
  const change = await call('adminRequestEmailChange', superToken, { targetUid: 'emu-target', newEmail: 'new-target@example.test' });
  assert.equal(change.response.status, 200, JSON.stringify(change.body));
  const invalid = await call('adminRequestEmailChange', superToken2, { targetUid: 'emu-target', newEmail: 'not-an-email' });
  assert.equal(invalid.response.status, 400);
  const targetCooldown = await call('adminRequestEmailChange', superToken2, { targetUid: 'emu-target', newEmail: 'another-target@example.test' });
  assert.equal(targetCooldown.response.status, 409);
  const concurrent = await Promise.all([
    call('adminRequestEmailChange', superToken2, { targetUid: 'emu-target-2', newEmail: 'one-target@example.test' }),
    call('adminRequestEmailChange', superToken3, { targetUid: 'emu-target-2', newEmail: 'two-target@example.test' }),
  ]);
  const concurrentStatuses = concurrent.map((item) => item.response.status).sort();
  assert.equal(concurrentStatuses[0], 200);
  assert.ok([409, 429].includes(concurrentStatuses[1]));
  const profile = (await db.collection('users').doc('emu-target').get()).data();
  assert.equal(profile.email, 'target@example.test');
  assert.equal(profile.pendingEmail, 'new-target@example.test');
  assert.equal(profile.emailChangeStatus, 'sent');
});
