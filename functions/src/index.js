'use strict';

const { randomUUID } = require('node:crypto');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { logger } = require('firebase-functions');
const { setGlobalOptions } = require('firebase-functions/v2');
const { defineSecret, defineString } = require('firebase-functions/params');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { HttpsError, onCall, onRequest } = require('firebase-functions/v2/https');
const {
  ANDROID_CHANNEL_ID,
  activeLabAdminIds,
  buildNotification,
  isPermanentTokenError,
  reportMessageRecipients,
} = require('./notification_core');
const { createEmailProvider } = require('./email_provider');

initializeApp();
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

const db = getFirestore();
const ROLE_COLLECTION = 'users';
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SENDGRID_API_KEY = defineSecret('SENDGRID_API_KEY');
const LABFLOW_EMAIL_FROM = defineString('LABFLOW_EMAIL_FROM', {
  default: 'noreply@labflow.ac.id',
});
const LABFLOW_AUTH_ACTION_URL = defineString('LABFLOW_AUTH_ACTION_URL', {
  default: 'https://labflow-academic-2026.firebaseapp.com/__/auth/action',
});
const LABFLOW_EMAIL_CHANGE_HANDLER_URL = defineString(
  'LABFLOW_EMAIL_CHANGE_HANDLER_URL',
  {
    default:
      'https://us-central1-labflow-academic-2026.cloudfunctions.net/completeEmailChange',
  },
);
const LABFLOW_FIREBASE_WEB_API_KEY = defineString('LABFLOW_FIREBASE_WEB_API_KEY', {
  default: '',
});
const TARGET_COOLDOWN_MS = 15 * 60 * 1000;
const ACTOR_COOLDOWN_MS = 60 * 1000;
const emailFunctionOptions = process.env.FUNCTIONS_EMULATOR === 'true'
  ? {}
  : { secrets: [SENDGRID_API_KEY] };

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Autentikasi diperlukan.');
  }
  return request.auth.uid;
}

async function requireActiveSuperadmin(request) {
  const actorUid = requireAuth(request);
  const actor = await activeProfile(actorUid, 'superadmin');
  if (!actor) {
    throw new HttpsError('permission-denied', 'Hanya Superadmin aktif yang diizinkan.');
  }
  return actorUid;
}

function validateEmail(value) {
  const email = typeof value === 'string' ? value.trim().toLowerCase() : '';
  if (!EMAIL_PATTERN.test(email) || email.length > 254) {
    throw new HttpsError('invalid-argument', 'Format email tidak valid.');
  }
  return email;
}

function actionCodeSettings() {
  const url = LABFLOW_AUTH_ACTION_URL.value();
  if (!url) {
    throw new HttpsError(
      'failed-precondition',
      'Konfigurasi tautan autentikasi belum tersedia.',
    );
  }
  return { url, handleCodeInApp: false };
}

function emailChangeHandlerUrl({ oobCode, targetUid, requestId }) {
  const raw = LABFLOW_EMAIL_CHANGE_HANDLER_URL.value();
  const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true';
  const localHandler = isEmulator && /^http:\/\/127\.0\.0\.1(?::\d+)?\//.test(raw || '');
  if (!raw || (!raw.startsWith('https://') && !localHandler)) {
    throw new HttpsError(
      'failed-precondition',
      'Handler verifikasi email belum dikonfigurasi dengan HTTPS.',
    );
  }
  const url = new URL(raw);
  url.searchParams.set('oobCode', oobCode);
  url.searchParams.set('targetUid', targetUid);
  url.searchParams.set('requestId', requestId);
  return url.toString();
}

async function sendAuthEmail({ to, subject, text, type, actionLink }) {
  const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true';
  const apiKey = isEmulator ? undefined : SENDGRID_API_KEY.value();
  const from = isEmulator ? undefined : LABFLOW_EMAIL_FROM.value();
  try {
    const provider = createEmailProvider({
      apiKey: isEmulator ? undefined : apiKey,
      from: isEmulator ? undefined : from,
      isEmulator,
      outboxPath: process.env.LABFLOW_MOCK_EMAIL_OUTBOX,
    });
    await provider.send({ to, subject, text, type, actionLink });
  } catch (error) {
    logger.error('Auth email provider rejected the request', {
      status: error.status || 'provider_error',
      provider: isEmulator ? 'mock' : 'sendgrid',
    });
    throw new HttpsError('internal', 'Email autentikasi gagal dikirim.');
  }
}

async function targetUser(targetUid) {
  if (typeof targetUid !== 'string' || targetUid.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'UID pengguna tidak valid.');
  }
  const profileSnapshot = await db.collection(ROLE_COLLECTION).doc(targetUid).get();
  if (!profileSnapshot.exists) {
    throw new HttpsError('not-found', 'Pengguna tidak ditemukan.');
  }
  try {
    return {
      profile: profileSnapshot.data(),
      authUser: await getAuth().getUser(targetUid),
    };
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'Akun autentikasi pengguna tidak ditemukan.');
    }
    throw error;
  }
}

function isRecent(timestamp, durationMs) {
  return timestamp?.toMillis && Date.now() - timestamp.toMillis() < durationMs;
}

async function reserveActor(actorUid, kind) {
  const reference = db.collection('credential_rate_limits').doc(actorUid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const data = snapshot.data() || {};
    if (isRecent(data[`${kind}At`], ACTOR_COOLDOWN_MS)) {
      throw new HttpsError('resource-exhausted', 'Terlalu banyak permintaan. Coba lagi nanti.');
    }
    transaction.set(reference, {
      [`${kind}At`]: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function reserveEmailChange({ actorUid, targetUid, newEmail }) {
  const reference = db.collection(ROLE_COLLECTION).doc(targetUid);
  const requestId = randomUUID();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'Pengguna tidak ditemukan.');
    }
    const data = snapshot.data() || {};
    if (['pending', 'sent'].includes(data.emailChangeStatus) &&
        isRecent(data.emailChangeRequestedAt, TARGET_COOLDOWN_MS)) {
      throw new HttpsError('already-exists', 'Permintaan perubahan email masih diproses.');
    }
    transaction.update(reference, {
      pendingEmail: newEmail,
      emailChangeRequestId: requestId,
      emailChangeStatus: 'pending',
      emailChangeRequestedAt: FieldValue.serverTimestamp(),
      emailChangeRequestedBy: actorUid,
    });
  });
  return requestId;
}

async function setEmailChangeStatus(targetUid, requestId, status) {
  const reference = db.collection(ROLE_COLLECTION).doc(targetUid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const data = snapshot.data() || {};
    if (data.emailChangeRequestId !== requestId) return;
    transaction.update(reference, {
      emailChangeStatus: status,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function writeCredentialAudit({ requestId, actorUid, targetUid, title, status }) {
  const reference = db.collection('activity_logs').doc(`credential_${requestId}`);
  try {
    await reference.create({
      type: 'credential',
      title,
      description: `Credential operation ${status}.`,
      actorUid,
      targetUid,
      requestId,
      status,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    await db.collection('credential_operations').doc(requestId).set({
      actorUid,
      targetUid,
      status,
      auditStatus: 'pending',
      auditErrorCode: error.code || 'unknown',
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    logger.error('Credential audit log reconciliation required', {
      requestId,
      errorCode: error.code || 'unknown',
    });
  }
}

exports.adminRequestEmailChange = onCall(
  emailFunctionOptions,
  async (request) => {
  const actorUid = await requireActiveSuperadmin(request);
  const targetUid = request.data?.targetUid;
  if (targetUid === actorUid) {
    throw new HttpsError('failed-precondition', 'Superadmin tidak dapat mengubah email sendiri melalui User Management.');
  }
  const newEmail = validateEmail(request.data?.newEmail);
  const target = await targetUser(targetUid);
  if (!target.authUser.email) {
    throw new HttpsError('failed-precondition', 'Akun target tidak memiliki email saat ini.');
  }
  if (target.authUser.email?.toLowerCase() === newEmail) {
    throw new HttpsError('already-exists', 'Email baru sama dengan email saat ini.');
  }

  try {
    const existing = await getAuth().getUserByEmail(newEmail);
    if (existing.uid !== targetUid) {
      throw new HttpsError('already-exists', 'Email tersebut sudah digunakan oleh akun lain.');
    }
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error.code !== 'auth/user-not-found') throw error;
  }

  await reserveActor(actorUid, 'emailChange');
  const requestId = await reserveEmailChange({ actorUid, targetUid, newEmail });
  try {
    const link = await getAuth().generateVerifyAndChangeEmailLink(
      target.authUser.email,
      newEmail,
      actionCodeSettings(),
    );
    const oobCode = new URL(link).searchParams.get('oobCode');
    if (!oobCode) {
      throw new HttpsError('internal', 'Kode verifikasi email tidak tersedia.');
    }
    await sendAuthEmail({
      to: newEmail,
      subject: 'Verifikasi perubahan email LabFlow',
      type: 'email_change_verification',
      actionLink: emailChangeHandlerUrl({ oobCode, targetUid, requestId }),
      text: `Permintaan perubahan email LabFlow dibuat oleh Superadmin. Verifikasi email baru melalui tautan berikut:\n\n${emailChangeHandlerUrl({ oobCode, targetUid, requestId })}\n\nJika Anda tidak meminta perubahan ini, abaikan email ini.`,
    });
  } catch (error) {
    await setEmailChangeStatus(targetUid, requestId, 'failed');
    throw error;
  }
  await setEmailChangeStatus(targetUid, requestId, 'sent');
  await writeCredentialAudit({
    requestId,
    actorUid,
    targetUid,
    title: 'Verifikasi perubahan email dikirim',
    status: 'sent',
  });
  return { status: 'verification_sent', requestId };
  },
);

exports.adminSendPasswordReset = onCall(
  emailFunctionOptions,
  async (request) => {
  const actorUid = await requireActiveSuperadmin(request);
  const targetUid = request.data?.targetUid;
  if (targetUid === actorUid) {
    throw new HttpsError('failed-precondition', 'Gunakan Forgot Password untuk akun sendiri.');
  }
  const target = await targetUser(targetUid);
  if (!target.authUser.email) {
    throw new HttpsError('failed-precondition', 'Akun target tidak memiliki email.');
  }
  await reserveActor(actorUid, 'passwordReset');
  const requestId = randomUUID();
  const link = await getAuth().generatePasswordResetLink(
    target.authUser.email,
    actionCodeSettings(),
  );
  await sendAuthEmail({
    to: target.authUser.email,
    subject: 'Atur ulang password LabFlow',
    type: 'password_reset',
    actionLink: link,
    text: `Superadmin menginisiasi reset password akun LabFlow Anda. Atur password baru melalui tautan berikut:\n\n${link}\n\nJika Anda tidak meminta ini, hubungi Superadmin LabFlow.`,
  });
  await writeCredentialAudit({
    requestId,
    actorUid,
    targetUid,
    title: 'Reset password dikirim',
    status: 'sent',
  });
  return { status: 'reset_sent', requestId };
  },
);

exports.completeEmailChange = onRequest(async (request, response) => {
  if (!['GET', 'POST'].includes(request.method)) {
    response.status(405).set('Allow', 'GET, POST').send('Method tidak diizinkan.');
    return;
  }
  response.set({
    'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': "default-src 'none'; form-action 'self'; base-uri 'none'",
  });
  const parameters = request.method === 'GET' ? request.query : (request.body || {});
  const { oobCode, targetUid, requestId } = parameters;
  if (typeof oobCode !== 'string' || typeof targetUid !== 'string' ||
      typeof requestId !== 'string' || oobCode.length > 4096 ||
      targetUid.length > 128 || requestId.length > 128) {
    response.status(400).send('Tautan verifikasi tidak valid.');
    return;
  }

  const profileReference = db.collection(ROLE_COLLECTION).doc(targetUid);
  const profileSnapshot = await profileReference.get();
  const profile = profileSnapshot.data() || {};
  if (!profileSnapshot.exists || profile.emailChangeRequestId !== requestId ||
      !['pending', 'sent'].includes(profile.emailChangeStatus) ||
      !profile.pendingEmail) {
    response.status(400).send('Tautan verifikasi sudah tidak berlaku.');
    return;
  }

  if (request.method === 'GET') {
    const escapeHtml = (value) => String(value)
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
    const action = escapeHtml((request.originalUrl || '').split('?')[0]);
    response.status(200).type('html').send(
      '<!doctype html><meta charset="utf-8"><title>Konfirmasi email LabFlow</title>' +
      '<h1>Konfirmasi perubahan email</h1>' +
      '<p>Tekan tombol di bawah untuk menyelesaikan verifikasi email.</p>' +
      `<form method="post" action="${action}">` +
      `<input type="hidden" name="oobCode" value="${escapeHtml(oobCode)}">` +
      `<input type="hidden" name="targetUid" value="${escapeHtml(targetUid)}">` +
      `<input type="hidden" name="requestId" value="${escapeHtml(requestId)}">` +
      '<button type="submit">Konfirmasi perubahan email</button></form>',
    );
    return;
  }

  const apiKey = LABFLOW_FIREBASE_WEB_API_KEY.value();
  if (!apiKey) {
    response.status(500).send('Konfigurasi verifikasi belum tersedia.');
    return;
  }
  const firebaseResponse = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:update?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ oobCode }),
    },
  );
  if (!firebaseResponse.ok) {
    await setEmailChangeStatus(targetUid, requestId, 'failed');
    response.status(400).send('Tautan verifikasi kedaluwarsa atau sudah digunakan.');
    return;
  }
  const result = await firebaseResponse.json();
  if (result.localId !== targetUid || result.email !== profile.pendingEmail ||
      result.emailVerified !== true) {
    await setEmailChangeStatus(targetUid, requestId, 'failed');
    response.status(400).send('Verifikasi email tidak dapat dikonfirmasi.');
    return;
  }

  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(profileReference);
    const data = current.data() || {};
    if (data.emailChangeRequestId !== requestId || data.pendingEmail !== result.email) {
      throw new Error('stale-email-change-request');
    }
    transaction.update(profileReference, {
      email: result.email,
      emailVerified: true,
      emailChangeStatus: 'completed',
      emailVerifiedAt: FieldValue.serverTimestamp(),
      pendingEmail: FieldValue.delete(),
      emailChangeRequestId: FieldValue.delete(),
      emailChangeRequestedAt: FieldValue.delete(),
      emailChangeRequestedBy: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await writeCredentialAudit({
    requestId,
    actorUid: profile.emailChangeRequestedBy,
    targetUid,
    title: 'Perubahan email terverifikasi',
    status: 'completed',
  });
  response.status(200).send('Email LabFlow berhasil diverifikasi. Anda dapat menutup halaman ini.');
});

async function activeProfile(uid, expectedRole) {
  if (!uid || typeof uid !== 'string') return null;
  const snapshot = await db.collection(ROLE_COLLECTION).doc(uid).get();
  const profile = snapshot.data();
  if (
    !snapshot.exists ||
    profile?.status !== 'active' ||
    (expectedRole && profile.role !== expectedRole)
  ) {
    return null;
  }
  return profile;
}

async function activeLabAdmins(labId, excludedUid = '') {
  if (!labId || typeof labId !== 'string') return [];
  const snapshot = await db
    .collection('lab_memberships')
    .where('labId', '==', labId)
    .get();
  const memberships = snapshot.docs
    .map((document) => ({ id: document.id, ...document.data() }))
    .filter((membership) =>
      membership.id === `${membership.userId}__${labId}` &&
      membership.role === 'lab_admin' &&
      membership.active === true,
    );
  const uniqueIds = [...new Set(memberships.map((membership) => membership.userId))]
    .filter((uid) => uid !== excludedUid);
  const activeUsers = await Promise.all(
    uniqueIds.map(async (uid) =>
      (await activeProfile(uid, 'lab_admin')) ? uid : null,
    ),
  );
  const activeUserIds = new Set(activeUsers.filter(Boolean));
  return activeLabAdminIds(memberships, activeUserIds, excludedUid);
}

async function activeSuperadmins(excludedUid = '') {
  const snapshot = await db
    .collection(ROLE_COLLECTION)
    .where('role', '==', 'superadmin')
    .where('status', '==', 'active')
    .get();
  return snapshot.docs
    .map((document) => document.id)
    .filter((uid) => uid !== excludedUid);
}

async function writeNotification({ eventId, recipientId, recipientRole, type,
  entityType, entityId, actorId, createdAt }) {
  const notice = buildNotification({
    eventId,
    recipientId,
    recipientRole,
    type,
    entityType,
    entityId,
    actorId,
    createdAt: createdAt || FieldValue.serverTimestamp(),
  });
  if (!notice) return false;
  const data = { ...notice.data };
  // Keep legacy Student clients readable during migration.
  if (recipientRole === 'student') data.studentId = recipientId;
  await db.collection('notifications').doc(notice.id).create(data).catch((error) => {
    if (error.code === 6 || error.code === 'already-exists') return;
    throw error;
  });
  return true;
}

async function notifyMany({ eventId, recipientIds, recipientRole, type,
  entityType, entityId, actorId }) {
  const unique = [...new Set(recipientIds)].filter((uid) => uid && uid !== actorId);
  await Promise.all(unique.map((recipientId) => writeNotification({
    eventId,
    recipientId,
    recipientRole,
    type,
    entityType,
    entityId,
    actorId,
  })));
}

exports.onBorrowRequestCreated = onDocumentCreated(
  { document: 'borrow_requests/{requestId}', retry: true },
  async (event) => {
    const request = event.data?.data();
    if (!request || request.status !== 'pending') return;
    const studentIsActive = await activeProfile(request.studentId, 'student');
    if (!studentIsActive) return;
    const recipientIds = await activeLabAdmins(request.labId, request.studentId);
    await notifyMany({
      eventId: event.id,
      recipientIds,
      recipientRole: 'lab_admin',
      type: 'borrow_request',
      entityType: 'borrow_request',
      entityId: event.params.requestId,
      actorId: request.studentId,
    });
  },
);

const BORROW_STATUS_TYPES = Object.freeze({
  approved: 'borrow_approved',
  rejected: 'borrow_rejected',
  waiting_pickup: 'borrow_waiting_pickup',
  active: 'borrow_active',
  returned: 'borrow_returned',
  cancelled: 'borrow_cancelled',
  canceled: 'borrow_cancelled',
});

exports.onBorrowRequestUpdated = onDocumentUpdated(
  { document: 'borrow_requests/{requestId}', retry: true },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    const type = BORROW_STATUS_TYPES[after.status];
    if (!type) return;
    if (type === 'borrow_cancelled') {
      const actorId = after.cancelledBy || after.canceledBy || after.studentId;
      const recipientIds = await activeLabAdmins(after.labId, actorId);
      await notifyMany({
        eventId: event.id, recipientIds, recipientRole: 'lab_admin', type,
        entityType: 'borrow_request', entityId: event.params.requestId, actorId,
      });
      return;
    }
    if (!(await activeProfile(after.studentId, 'student'))) return;
    const actorId = after.approvedBy || after.rejectedBy || after.updatedBy || null;
    await notifyMany({
      eventId: event.id,
      recipientIds: [after.studentId],
      recipientRole: 'student',
      type,
      entityType: 'borrow_request',
      entityId: event.params.requestId,
      actorId,
    });
  },
);

exports.onReportCreated = onDocumentCreated(
  { document: 'reports/{reportId}', retry: true },
  async (event) => {
    const report = event.data?.data();
    if (!report || report.status !== 'open') return;
    if (!(await activeProfile(report.reporterId, 'student'))) return;
    const recipientIds = await activeLabAdmins(report.labId, report.reporterId);
    await notifyMany({
      eventId: event.id,
      recipientIds,
      recipientRole: 'lab_admin',
      type: 'report_created',
      entityType: 'report',
      entityId: event.params.reportId,
      actorId: report.reporterId,
    });
  },
);

exports.onReportUpdated = onDocumentUpdated(
  { document: 'reports/{reportId}', retry: true },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    if (!(await activeProfile(after.reporterId, 'student'))) return;
    await notifyMany({
      eventId: event.id,
      recipientIds: [after.reporterId],
      recipientRole: 'student',
      type: 'report_status_changed',
      entityType: 'report',
      entityId: event.params.reportId,
      actorId: after.assignedTo || null,
    });
  },
);

exports.onReportMessageCreated = onDocumentCreated(
  {
    document: 'reports/{reportId}/messages/{messageId}',
    retry: true,
  },
  async (event) => {
    const message = event.data?.data();
    if (!message || message.deletedAt != null) return;
    const reportSnapshot = await db.collection('reports').doc(event.params.reportId).get();
    const report = reportSnapshot.data();
    if (!reportSnapshot.exists || !report) return;
    const sender = await activeProfile(message.senderId);
    if (!sender || !['student', 'lab_admin'].includes(sender.role)) return;
    if (message.senderRole !== sender.role) return;

    let recipients;
    if (sender.role === 'student' && message.senderId === report.reporterId) {
      recipients = await activeLabAdmins(report.labId, message.senderId);
    } else if (
      sender.role === 'lab_admin' &&
      (await activeLabAdmins(report.labId)).includes(message.senderId) &&
      (await activeProfile(report.reporterId, 'student'))
    ) {
      recipients = [report.reporterId];
    } else {
      return;
    }
    await notifyMany({
      eventId: event.id,
      recipientIds: recipients,
      recipientRole: sender.role === 'student' ? 'lab_admin' : 'student',
      type: 'report_message',
      entityType: 'report',
      entityId: event.params.reportId,
      actorId: message.senderId,
    });
  },
);

exports.onSuperadminActivityCreated = onDocumentCreated(
  { document: 'activity_logs/{activityId}', retry: true },
  async (event) => {
    const activity = event.data?.data();
    if (!activity || !['user', 'laboratory', 'membership'].includes(activity.type)) return;
    if (!(await activeProfile(activity.actorUid, 'superadmin'))) return;
    const recipientIds = await activeSuperadmins(activity.actorUid);
    await notifyMany({
      eventId: event.id,
      recipientIds,
      recipientRole: 'superadmin',
      type: 'admin_activity',
      entityType: 'admin_activity',
      entityId: event.params.activityId,
      actorId: activity.actorUid,
    });
  },
);

async function claimPush(notificationRef) {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(notificationRef);
    if (!snapshot.exists) return null;
    const data = snapshot.data();
    const state = data.pushState || 'pending';
    if (['sent', 'no_tokens'].includes(state)) return null;
    if (state === 'sending') {
      const claimedAt = data.pushClaimedAt;
      if (claimedAt instanceof Timestamp && Date.now() - claimedAt.toMillis() < 180_000) {
        return null;
      }
    }
    transaction.update(notificationRef, {
      pushState: 'sending',
      pushClaimedAt: FieldValue.serverTimestamp(),
      pushAttempts: FieldValue.increment(1),
    });
    return data;
  });
}

function invalidTokenIds(response, tokenDocs) {
  const ids = [];
  response.responses.forEach((item, index) => {
    if (!item.success && isPermanentTokenError(item.error?.code)) {
      ids.push(tokenDocs[index].id);
    }
  });
  return ids;
}

exports.dispatchNotificationPush = onDocumentCreated(
  { document: 'notifications/{notificationId}', retry: true },
  async (event) => {
    const notificationRef = event.data?.ref;
    if (!notificationRef) return;
    const data = await claimPush(notificationRef);
    if (!data) return;

    const tokensSnapshot = await db
      .collection('users')
      .doc(data.recipientId)
      .collection('fcmTokens')
      .get();
    const tokenDocs = tokensSnapshot.docs.filter((document) =>
      typeof document.data().fid === 'string' && document.data().fid.length > 0,
    );
    if (tokenDocs.length === 0) {
      await notificationRef.update({ pushState: 'no_tokens' });
      return;
    }

    let successCount = 0;
    let failureCount = 0;
    const staleTokenIds = [];
    try {
      for (let offset = 0; offset < tokenDocs.length; offset += 500) {
        const chunk = tokenDocs.slice(offset, offset + 500);
        const response = await getMessaging().sendEachForMulticast({
          fids: chunk.map((document) => document.data().fid),
          notification: { title: data.title, body: data.body },
          data: {
            eventId: String(data.eventId),
            notificationId: event.params.notificationId,
            type: String(data.type),
            entityType: String(data.entityType),
            entityId: String(data.entityId),
            route: String(data.route),
          },
          android: {
            priority: 'high',
            notification: {
              channelId: ANDROID_CHANNEL_ID,
              sound: 'default',
              tag: event.params.notificationId,
              icon: 'ic_stat_labflow',
            },
          },
        });
        successCount += response.successCount;
        failureCount += response.failureCount;
        staleTokenIds.push(...invalidTokenIds(response, chunk));
      }
      if (staleTokenIds.length > 0) {
        const batch = db.batch();
        for (const tokenId of staleTokenIds) batch.delete(
          db.collection('users').doc(data.recipientId).collection('fcmTokens').doc(tokenId),
        );
        await batch.commit();
      }
      await notificationRef.update({
        pushState: successCount > 0 ? 'sent' : 'failed',
        pushSuccessCount: successCount,
        pushFailureCount: failureCount,
        pushCompletedAt: FieldValue.serverTimestamp(),
      });
      logger.info('Notification push dispatch completed', {
        notificationId: event.params.notificationId,
        recipientId: data.recipientId,
        successCount,
        failureCount,
        staleTokenCount: staleTokenIds.length,
      });
      if (successCount === 0 && failureCount > staleTokenIds.length) {
        throw new Error('FCM delivery failed for all currently registered tokens.');
      }
    } catch (error) {
      await notificationRef.update({
        pushState: 'pending',
        pushLastErrorCode: typeof error?.code === 'string' ? error.code : 'send-failed',
      });
      throw error;
    }
  },
);
