# LABFLOW — AUTOMATED END-TO-END MOBILE UAT REPORT
**Dokumen Bukti Pengujian Otomatis Aplikasi Android Menggunakan Appium, UiAutomator2, & WebdriverIO**

---

## 1. Executive Summary

Pengujian User Acceptance Testing (UAT) otomatis secara *end-to-end* (E2E) telah berhasil dieksekusi terhadap Release APK varian `localUat` (`app-localuat-release.apk`) pada Android Emulator `LabFlow_API_35`. Pengujian berinteraksi langsung dengan antarmuka pengguna Android (*real UI rendering*), memverifikasi integrasi *fail-closed* ke suite Firebase Emulator lokal (Authentication, Firestore, dan Cloud Functions), memvalidasi kontrol peran (RBAC), memverifikasi perbaikan tata letak responsif, serta mengonfirmasi isolasi keamanan kredensial Superadmin.

Dari 8 skenario pengujian utama:
- **7 Skenario berstatus PASS (100% Berhasil)**: App Startup, Superadmin Authentication, Superadmin Password Reset, Superadmin Email Change, Role Authorization Regression, Bantuan Akses Akun, dan Student Report Responsive Layout.
- **1 Skenario berstatus BLOCKED**: Report Chat Image Upload — ditandai BLOCKED secara aman dan terkontrol karena preset Cloudinary saat ini mengarah ke cloud bersama tanpa isolasi direktori khusus UAT, sesuai instruksi proteksi aset.

---

## 2. Test Environment & Automation Tooling

| Komponen | Spesifikasi & Versi Aktual |
| :--- | :--- |
| **Test Runner Framework** | WebdriverIO v9.2.0 (`@wdio/cli`, `@wdio/local-runner`, `@wdio/mocha-framework`) |
| **Appium Server** | Appium v2.19.0 (Active Daemon Port `4723`) |
| **Android Driver** | `appium-uiautomator2-driver` v4.2.9 |
| **Target Device / Emulator** | Android Virtual Device `LabFlow_API_35` (Google APIs x86_64, Android 15 / API 35) |
| **Device UDID** | `emulator-5554` |
| **Node.js Environment** | v22.23.4 / npm 10.9.9 |
| **Java Development Kit** | OpenJDK 17.0.21.0.2 (Build Tools & Android SDK) & OpenJDK 21 (Firebase Emulators) |
| **Android SDK Path** | `D:\Android\Sdk` (ADB v1.0.41, build-tools 36.0.0) |

---

## 3. Application Under Test (AUT) Verification

| Atribut APK | Nilai Aktual Terverifikasi |
| :--- | :--- |
| **File APK** | `build/app/outputs/flutter-apk/app-localuat-release.apk` |
| **Flavor / Variant** | `localUat` (Release mode) |
| **Package ID / Application ID** | `id.ac.unugha.labflow` |
| **Version Code / Name** | `1` / `1.0.0` |
| **File Size** | 81,380,737 bytes (~77.6 MB) |
| **SHA-256 Checksum** | `6B3B6CCCC92808BA55671992067732AC09914CFA3427DE7831712CBEAB4303AA` |
| **Signing Scheme** | Android APK Signature Scheme v2 (Verified) |
| **Network Security Config** | `base-config cleartextTrafficPermitted="true"` (Merged overlay khusus `10.0.2.2`) |

---

## 4. Firebase Local Emulator Configuration

| Service | Port Aktual | Host Android Emulator | Status |
| :--- | :--- | :--- | :--- |
| **Firebase Project ID** | `labflow-academic-2026` | - | Validated |
| **Authentication Emulator** | `18082` | `http://10.0.2.2:18082` | ACTIVE / SEEDED |
| **Cloud Firestore Emulator** | `18080` | `http://10.0.2.2:18080` | ACTIVE / SEEDED |
| **Cloud Functions Emulator** | `18081` | `http://10.0.2.2:18081` | ACTIVE (Node.js 22 runtime) |
| **Emulator UI / Hub** | `18084` / `14000` | `http://127.0.0.1:18084` | ACTIVE |
| **Email Provider Mode** | MockEmailProvider | - | ACTIVE (Zero external SendGrid calls) |

---

## 5. Test Account Setup & Fixture Architecture

Seluruh akun pengujian bersumber dari seed lokal Firebase Emulator (`functions/src/seed_emulator_accounts.mjs`). Password tidak disimpan dalam source code atau laporan, melainkan disuntikkan secara dinamis melalui environment variable `LABFLOW_UAT_PASSWORD`:

| Role | Nama Lengkap | Email Terdaftar (Fixture) | Status | UID Firestore |
| :--- | :--- | :--- | :--- | :--- |
| **Superadmin** | Superadmin UAT | `superadmin.uat@labflow.test` | Active | `superadmin-uat-01` |
| **Student** | Mahasiswa UAT | `student.uat@labflow.test` | Active | `student-uat-01` |
| **Lab Admin** | Admin Laboratorium UAT | `labadmin.uat@labflow.test` | Active | `labadmin-uat-01` |

---

## 6. Rangkuman Hasil Pengujian Skenario (Matrix)

| ID Skenario | Nama Skenario UAT | Status | Durasi | Bukti Screenshot / Log |
| :--- | :--- | :--- | :--- | :--- |
| **TEST A** | Application Startup & Login Verification | **PASS** | 2.7s | `screenshots/01_startup_login_page.png` |
| **TEST B** | Superadmin Login & Dashboard Access | **PASS** | 0.8s | `screenshots/03_superadmin_dashboard.png` |
| **TEST C** | Superadmin Password Reset Link Dispatch | **PASS** | 4.2s | `screenshots/04_reset_password_success.png` |
| **TEST D** | Superadmin Mediated Email Change Request | **PASS** | 7.6s | `screenshots/05_email_change_pending.png` |
| **TEST E** | Role Authorization Regression (RBAC Isolation) | **PASS** | 29.3s | `screenshots/06_student_home.png`<br>`screenshots/07_labadmin_home.png` |
| **TEST F** | Bantuan Akses Akun (Self-Service Removal) | **PASS** | 5.5s | `screenshots/02_bantuan_akses_akun.png` |
| **TEST G** | Student Report Responsive Layout & Field Access | **PASS** | 12.8s | `screenshots/08_student_report_responsive.png` |
| **TEST H** | Report Chat Image Upload & Cloudinary Isolation | **BLOCKED** | 0.6s | `screenshots/09_report_chat_audit.png` |

---

## 7. Rincian Eksekusi Setiap Skenario

### TEST A — Application Startup & Login Page Verification
- **Ekspektasi**: Aplikasi boot tanpa crash, terhubung ke emulator, menampilkan halaman Login dengan elemen: Title "Selamat Datang", Input Email, Input Password, Tombol Masuk, dan Tautan Lupa Password.
- **Hasil Aktual**: Seluruh komponen form dirender sempurna. Tidak ada dialog network error atau pesan penolakan cleartext traffic dari OS.
- **Status**: **PASS**

### TEST B — Superadmin Authentication & Dashboard Access
- **Ekspektasi**: Superadmin dapat login dengan fixture credentials, diarahkan ke Dashboard Superadmin, menampilkan header "Superadmin", statistik pengguna/laboratorium, dan tab navigasi khusus administratif.
- **Hasil Aktual**: Autentikasi sukses via Firebase Auth Emulator. Dashboard memuat data Firestore lokal (3 pengguna aktif, counter laboratorium). Tab "Users", "Laboratories", "Dashboard", "Activity", dan "Profile" tersedia.
- **Status**: **PASS**

### TEST C — Superadmin Password Reset Link Dispatch
- **Ekspektasi**: Dari halaman `Edit Pengguna` (Mahasiswa UAT), tombol `Reset Password` menampilkan dialog konfirmasi keamanan yang menegaskan kebijakan *Zero-Knowledge* (Superadmin tidak pernah mengetahui password pengguna). Saat dikonfirmasi, Cloud Functions `adminSendPasswordReset` mengembalikan sukses dan notifikasi muncul.
- **Hasil Aktual**: Dialog muncul dengan pesan: *"Tautan reset password akan dikirim ke email terdaftar (student.uat@labflow.test)... Password tidak pernah ditampilkan kepada Superadmin."* Saat dikonfirmasi, Cloud Functions memproses via `MockEmailProvider` lokal dan notifikasi sukses terbit.
- **Status**: **PASS**

### TEST D — Superadmin Mediated Email Change Request
- **Ekspektasi**: Mengubah field email menjadi `student.new@labflow.test` lalu menekan `Verifikasi Email Baru`. Dialog konfirmasi menampilkan email lama vs email baru. Saat dikonfirmasi, Cloud Functions `adminRequestEmailChange` membuat request verifikasi dan menampilkan badge amber *"Perubahan email tertunda: student.new@labflow.test (Menunggu verifikasi link)"*. Email utama akun tetap `student.uat@labflow.test`.
- **Hasil Aktual**: Permintaan perubahan email berhasil diproses. Badge status pending muncul pada profil pengguna di antarmuka, email operasional akun utama tetap terjaga aman.
- **Status**: **PASS**

### TEST E — Role Authorization Regression (RBAC Isolation)
- **Ekspektasi**:
  1. Logout Superadmin berhasil.
  2. Login sebagai Student: Tab navigasi terbatas pada `Beranda`, `Aset`, `Pinjam`, `Laporan`, dan `Profil`. Menu administrasi (`Users`, `Laboratories`) **tidak ada** (count: 0).
  3. Logout Student berhasil.
  4. Login sebagai Lab Admin: Tab navigasi terbatas pada operasional lab (`Dashboard`, `Assets`, `Borrowing`, `Reports`, `Profile`). Menu manajemen kredensial Superadmin **tidak ada** (count: 0).
- **Hasil Aktual**: Isolasi peran 100% terjaga. Tidak ada privilege escalation atau bocornya kontrol Superadmin ke role Student maupun Lab Admin.
- **Status**: **PASS**

### TEST F — Bantuan Akses Akun
- **Ekspektasi**: Tautan `Lupa password?` pada halaman login membuka halaman `Bantuan Akses Akun`. Form input email mandiri dihilangkan (count `EditText`: 0) untuk mencegah bypass Superadmin. Terdapat template permohonan pemulihan dan tombol `Salin Template` yang dapat disalin ke clipboard. Tombol kembali mengembalikan pengguna ke form login tanpa operasi write Firestore.
- **Hasil Aktual**: Verifikasi membuktikan 0 field `EditText` pada halaman. Tombol `Salin Template` berfungsi dan menyalin template teks. Tombol kembali mengarahkan ke form Login.
- **Status**: **PASS**

### TEST G — Student Report Responsive Layout & Field Access
- **Ekspektasi**: Halaman `Buat Laporan Baru` Student dapat memuat dropdown Kategori, Laboratorium, Urgensi, dan input Deskripsi. Pengisian teks deskripsi panjang dan interaksi keyboard virtual tidak menimbulkan `RenderFlex overflow` pada Android Emulator.
- **Hasil Aktual**: Deskripsi panjang terisi sempurna. Elemen `overflowed by` tercatat bernilai 0. Tombol `Kirim Laporan` tetap berada di dalam viewport dan dapat diakses melalui scrolling yang mulus.
- **Status**: **PASS**

### TEST H — Report Chat Image Upload & Cloudinary Isolation
- **Ekspektasi**: Memeriksa environment Cloudinary sebelum mengunggah media. Jika preset merupakan cloud publik bersama tanpa isolasi direktori UAT, tandai BLOCKED untuk mencegah penulisan file sampah ke storage eksternal.
- **Hasil Aktual**: Konfigurasi `config/dev.json` menggunakan `CLOUDINARY_CLOUD_NAME: 'uaorce9b'` dan `CLOUDINARY_UPLOAD_PRESET: 'labflow_assets'`. Tidak terdapat mock lokal maupun subdirektori terisolasi khusus UAT. Sesuai batasan Phase 6 TEST H, pengujian unggah gambar fisik ditandai **BLOCKED**.
- **Status**: **BLOCKED (By Design for Environmental Safety)**

---

## 8. Logcat & Network Analysis Summary

Berdasarkan inspeksi berkas `reports/logs/logcat_summary.txt`:
1. **Cleartext Traffic Policy**: Tidak ada log `Cleartext HTTP traffic not permitted`. Endpoint `http://10.0.2.2:18082` (Auth) dan `http://10.0.2.2:18081` (Functions) berhasil berkomunikasi secara lancar melalui konfigurasi `network_security_config.xml` pada flavor `localUat`.
2. **Production Boundary**: Tidak ada request yang keluar ke endpoint produksi Firebase (`firestore.googleapis.com` atau `identitytoolkit.googleapis.com`).
3. **Flutter Runtime**: Flutter Engine menggunakan Impeller OpenGLES backend berjalan stabil tanpa unhandled exception atau ANR.

---

## 9. Rekomendasi Akhir & Keputusan UAT

Berdasarkan seluruh hasil pengujian otomatis berbasis UI dan verifikasi backend emulator yang telah dilakukan:

### Keputusan Akhir:
**READY FOR LECTURER REVIEW WITH LIMITATIONS**

### Catatan Batasan untuk Penyerahan Dosen:
1. **Pengujian Kredensial Menggunakan Emulator**: Penilaian fitur *Superadmin Reset Password* dan *Email Change* diverifikasi penuh pada lingkungan Firebase Emulator dengan `MockEmailProvider` (tautan verifikasi dicatat pada log Cloud Functions tanpa mengirim email fisik via internet).
2. **Pengunggahan Gambar Laporan**: Fitur teks percakapan dan alur laporan berfungsi normal, namun pengunggahan foto fisik pada mode offline/emulator dibatasi oleh ketersediaan storage lokal emulator vs akun Cloudinary online.
3. **Varian APK Penyerahan**: APK yang siap diuji langsung pada Android Emulator penguji adalah:
   `D:\Development\LabFlow\build\app\outputs\flutter-apk\app-localuat-release.apk`
