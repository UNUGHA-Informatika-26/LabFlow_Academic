import { expect } from 'expect';
import { Selectors } from '../helpers/selectors.js';
import { TEST_ACCOUNTS, getTestPassword } from '../helpers/test_accounts.js';
import { takeEvidenceScreenshot, savePageSource } from '../helpers/evidence.js';

describe('TEST E: Role Authorization Regression (Student & Lab Admin Isolation)', () => {
  it('should log out from Superadmin', async () => {
    // 1. Go to Profile tab
    const profileTab = await $('android=new UiSelector().description("Profile")');
    await profileTab.waitForDisplayed({ timeout: 10000 });
    await profileTab.click();

    // 2. Scroll to and tap "Keluar dari LabFlow"
    const logoutBtn = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().descriptionContains("Keluar"))'
    );
    await logoutBtn.waitForDisplayed({ timeout: 10000 });
    await logoutBtn.click();

    // 3. Confirm logout in dialog
    const confirmLogout = await $('android=new UiSelector().className("android.widget.Button").description("Keluar")');
    await confirmLogout.waitForDisplayed({ timeout: 10000 });
    await confirmLogout.click();

    // 4. Verify redirected to Login page
    const loginBtn = await Selectors.loginButton();
    await loginBtn.waitForDisplayed({ timeout: 15000 });
    expect(await loginBtn.isDisplayed()).toBe(true);
  });

  it('should authenticate as Student and verify restricted role access', async () => {
    // 1. Enter student credentials
    const editTexts = await $$('android.widget.EditText');
    await editTexts[0].click();
    await editTexts[0].setValue(TEST_ACCOUNTS.student.email);

    await editTexts[1].click();
    await editTexts[1].setValue(getTestPassword());

    if (await browser.isKeyboardShown()) {
      await browser.hideKeyboard();
    }

    const loginBtn = await Selectors.loginButton();
    await loginBtn.click();

    // 2. Verify Student bottom navigation tabs
    const berandaTab = await $('android=new UiSelector().description("Beranda")');
    await berandaTab.waitForDisplayed({ timeout: 15000 });
    expect(await berandaTab.isDisplayed()).toBe(true);

    const laporanTab = await $('android=new UiSelector().description("Laporan")');
    expect(await laporanTab.isDisplayed()).toBe(true);

    const profilTab = await $('android=new UiSelector().description("Profil")');
    expect(await profilTab.isDisplayed()).toBe(true);

    // 3. Assert NO administrative tabs exist
    const adminTabs = await $$('android=new UiSelector().description("Laboratories")');
    expect(adminTabs.length).toBe(0);

    const userTabs = await $$('android=new UiSelector().description("Users")');
    expect(userTabs.length).toBe(0);

    await takeEvidenceScreenshot(browser, '06_student_home');
    await savePageSource(browser, '06_student_home');

    // 4. Logout Student
    await profilTab.click();
    const logoutBtn = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().descriptionContains("Keluar"))'
    );
    await logoutBtn.waitForDisplayed({ timeout: 10000 });
    await logoutBtn.click();

    const confirmLogout = await $('android=new UiSelector().className("android.widget.Button").description("Keluar")');
    await confirmLogout.waitForDisplayed({ timeout: 10000 });
    await confirmLogout.click();

    await loginBtn.waitForDisplayed({ timeout: 15000 });
    expect(await loginBtn.isDisplayed()).toBe(true);
  });

  it('should authenticate as Lab Admin and verify operational scope without Superadmin privileges', async () => {
    // 1. Enter Lab Admin credentials
    const editTexts = await $$('android.widget.EditText');
    await editTexts[0].click();
    await editTexts[0].setValue(TEST_ACCOUNTS.labadmin.email);

    await editTexts[1].click();
    await editTexts[1].setValue(getTestPassword());

    if (await browser.isKeyboardShown()) {
      await browser.hideKeyboard();
    }

    const loginBtn = await Selectors.loginButton();
    await loginBtn.click();

    // 2. Verify Lab Admin bottom navigation
    const assetsTab = await $('android=new UiSelector().description("Assets")');
    await assetsTab.waitForDisplayed({ timeout: 15000 });
    expect(await assetsTab.isDisplayed()).toBe(true);

    const borrowingTab = await $('android=new UiSelector().description("Borrowing")');
    expect(await borrowingTab.isDisplayed()).toBe(true);

    // 3. Verify NO Superadmin management access
    const userTabs = await $$('android=new UiSelector().description("Users")');
    expect(userTabs.length).toBe(0);

    await takeEvidenceScreenshot(browser, '07_labadmin_home');
    await savePageSource(browser, '07_labadmin_home');

    // 4. Logout Lab Admin
    const profileTab = await $('android=new UiSelector().description("Profile")');
    await profileTab.click();

    const logoutBtn = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().descriptionContains("Keluar"))'
    );
    await logoutBtn.waitForDisplayed({ timeout: 10000 });
    await logoutBtn.click();

    const confirmLogout = await $('android=new UiSelector().className("android.widget.Button").description("Keluar")');
    await confirmLogout.waitForDisplayed({ timeout: 10000 });
    await confirmLogout.click();

    await loginBtn.waitForDisplayed({ timeout: 15000 });
    expect(await loginBtn.isDisplayed()).toBe(true);
  });
});
