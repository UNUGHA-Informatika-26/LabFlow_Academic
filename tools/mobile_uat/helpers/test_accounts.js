// Fixture account definitions for Local UAT on Firebase Emulator
// Note: Passwords are read dynamically from environment variables, never hardcoded in git.

export const TEST_ACCOUNTS = {
  superadmin: {
    uid: 'superadmin-uat-01',
    email: 'superadmin.uat@labflow.test',
    fullName: 'Superadmin UAT',
    role: 'superadmin',
  },
  student: {
    uid: 'student-uat-01',
    email: 'student.uat@labflow.test',
    fullName: 'Mahasiswa UAT',
    role: 'student',
  },
  labadmin: {
    uid: 'labadmin-uat-01',
    email: 'labadmin.uat@labflow.test',
    fullName: 'Admin Laboratorium UAT',
    role: 'lab_admin',
  },
};

export function getTestPassword() {
  return process.env.LABFLOW_UAT_PASSWORD || 'UatTester123!';
}
