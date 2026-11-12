import { initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const projectId = process.env.FIREBASE_PROJECT_ID || 'labflow-academic-2026';

// Proteksi mutlak: pastikan environment mengarah ke Emulator
const authEmulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:18082';
const firestoreEmulatorHost = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';

process.env.FIREBASE_AUTH_EMULATOR_HOST = authEmulatorHost;
process.env.FIRESTORE_EMULATOR_HOST = firestoreEmulatorHost;
process.env.GCLOUD_PROJECT = projectId;

console.log('--- LABFLOW LOCAL EMULATOR SEED ---');
console.log(`Project ID          : ${projectId}`);
console.log(`Auth Emulator Host  : ${authEmulatorHost}`);
console.log(`Firestore Host      : ${firestoreEmulatorHost}`);

const app = getApps()[0] || initializeApp({ projectId });
const auth = getAuth(app);
const db = getFirestore(app);

const testPassword = process.env.LABFLOW_UAT_PASSWORD || 'UatTester123!';

const FIXTURES = [
  {
    uid: 'superadmin-uat-01',
    email: 'superadmin.uat@labflow.test',
    fullName: 'Superadmin UAT',
    role: 'superadmin',
    status: 'active',
  },
  {
    uid: 'student-uat-01',
    email: 'student.uat@labflow.test',
    fullName: 'Mahasiswa UAT',
    role: 'student',
    status: 'active',
    nim: '20260001',
    studyProgram: 'Informatika',
    semester: 5,
  },
  {
    uid: 'labadmin-uat-01',
    email: 'labadmin.uat@labflow.test',
    fullName: 'Admin Laboratorium UAT',
    role: 'lab_admin',
    status: 'active',
    nip: '198501012026011001',
  },
];

async function seedAccount(fixture) {
  try {
    await auth.getUser(fixture.uid);
    await auth.updateUser(fixture.uid, {
      email: fixture.email,
      password: testPassword,
      displayName: fixture.fullName,
      emailVerified: true,
    });
    console.log(`[AUTH] Diperbarui : ${fixture.email} (${fixture.uid})`);
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      await auth.createUser({
        uid: fixture.uid,
        email: fixture.email,
        password: testPassword,
        displayName: fixture.fullName,
        emailVerified: true,
      });
      console.log(`[AUTH] Dibuat     : ${fixture.email} (${fixture.uid})`);
    } else {
      throw error;
    }
  }

  const userDocRef = db.collection('users').doc(fixture.uid);
  const firestoreData = {
    uid: fixture.uid,
    email: fixture.email,
    fullName: fixture.fullName,
    role: fixture.role,
    status: fixture.status,
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (fixture.nim) firestoreData.nim = fixture.nim;
  if (fixture.studyProgram) firestoreData.studyProgram = fixture.studyProgram;
  if (fixture.semester) firestoreData.semester = fixture.semester;
  if (fixture.nip) firestoreData.nip = fixture.nip;

  await userDocRef.set(firestoreData, { merge: true });
  console.log(`[FIRESTORE] Disinkronkan : users/${fixture.uid} [role: ${fixture.role}, status: ${fixture.status}]`);
}

async function run() {
  for (const fixture of FIXTURES) {
    await seedAccount(fixture);
  }
  console.log('--- SEED SELESAI DENGAN SUKSES ---');
  console.log('Akun siap digunakan untuk login Local UAT pada Android Emulator.');
}

run().catch((err) => {
  console.error('[ERROR] Gagal melakukan seed akun emulator:', err);
  process.exit(1);
});
