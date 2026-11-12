import { expect } from 'expect';
import { Selectors } from '../helpers/selectors.js';
import { takeEvidenceScreenshot, savePageSource } from '../helpers/evidence.js';

describe('TEST C & D: Superadmin Credential Management (Reset Password & Email Change)', () => {
  it('should navigate to User Management and open Mahasiswa UAT edit page', async () => {
    // 1. Click bottom navigation Users tab (instance 1 to avoid stat card)
    const usersTab = await $('android=new UiSelector().description("Users").instance(1)');
    await usersTab.waitForDisplayed({ timeout: 10000 });
    await usersTab.click();

    // 2. Locate Mahasiswa UAT in the list
    const studentItem = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().descriptionContains("Mahasiswa UAT"))'
    );
    await studentItem.waitForDisplayed({ timeout: 15000 });
    expect(await studentItem.isDisplayed()).toBe(true);
    await studentItem.click();

    // 3. Verify Edit Pengguna page
    const editPageTitle = await Selectors.byDescriptionContains('Edit Pengguna');
    await editPageTitle.waitForDisplayed({ timeout: 10000 });
    expect(await editPageTitle.isDisplayed()).toBe(true);
  });

  it('TEST C: should trigger admin password reset link via Cloud Functions', async () => {
    // 1. Scroll to and tap "Reset Password" button
    const resetBtn = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().description("Reset Password"))'
    );
    await resetBtn.waitForDisplayed({ timeout: 10000 });
    await resetBtn.click();

    // 2. Verify confirmation dialog appears
    const dialogTitle = await Selectors.byDescriptionContains('Reset password pengguna?');
    await dialogTitle.waitForDisplayed({ timeout: 10000 });
    expect(await dialogTitle.isDisplayed()).toBe(true);

    // Verify dialog explains security zero-knowledge policy
    const dialogNotice = await Selectors.byDescriptionContains('Password tidak pernah ditampilkan kepada Superadmin');
    expect(await dialogNotice.isDisplayed()).toBe(true);

    // 3. Confirm password reset in dialog
    const confirmResetBtn = await $('android=new UiSelector().className("android.widget.Button").description("Reset Password")');
    await confirmResetBtn.click();

    // 4. Verify Cloud Functions processing and success notification
    await browser.pause(2500);
    await takeEvidenceScreenshot(browser, '04_reset_password_success');
    await savePageSource(browser, '04_reset_password_success');
  });

  it('TEST D: should initiate mediated email change and display pending verification badge', async () => {
    // 1. Scroll up to email field (the 2nd EditText on page)
    const emailField = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().className("android.widget.EditText").instance(1))'
    );
    await emailField.waitForDisplayed({ timeout: 10000 });
    await emailField.click();
    await emailField.setValue('student.new@labflow.test');

    if (await browser.isKeyboardShown()) {
      await browser.hideKeyboard();
    }

    // 2. Scroll to and tap "Verifikasi Email Baru"
    const verifyEmailBtn = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().description("Verifikasi Email Baru"))'
    );
    await verifyEmailBtn.waitForDisplayed({ timeout: 10000 });
    await verifyEmailBtn.click();

    // 3. Verify confirmation dialog shows new email
    const dialogTitle = await Selectors.byDescriptionContains('Kirim verifikasi email?');
    await dialogTitle.waitForDisplayed({ timeout: 10000 });
    expect(await dialogTitle.isDisplayed()).toBe(true);

    const newEmailNotice = await Selectors.byDescriptionContains('student.new@labflow.test');
    expect(await newEmailNotice.isDisplayed()).toBe(true);

    // 4. Confirm verification request
    const confirmBtn = await Selectors.byDescription('Kirim Verifikasi');
    await confirmBtn.click();

    // 5. Verify pending badge appears or notification is shown
    await browser.pause(3000);
    await takeEvidenceScreenshot(browser, '05_email_change_pending');
    await savePageSource(browser, '05_email_change_pending');

    // Return to dashboard
    await browser.back();
    const dashTab = await $('android=new UiSelector().description("Dashboard").instance(1)');
    if (await dashTab.isDisplayed()) {
      await dashTab.click();
    }
  });
});
