import { expect } from 'expect';
import { Selectors } from '../helpers/selectors.js';
import { TEST_ACCOUNTS, getTestPassword } from '../helpers/test_accounts.js';
import { takeEvidenceScreenshot, savePageSource } from '../helpers/evidence.js';

describe('TEST G: Student Report Page Responsive Layout & Field Access', () => {
  it('should navigate to Create Report page and verify all fields are accessible without overflow', async () => {
    // 1. Ensure logged in as Student
    const emailFields = await $$('android.widget.EditText');
    if (emailFields.length > 0) {
      await emailFields[0].click();
      await emailFields[0].setValue(TEST_ACCOUNTS.student.email);

      await emailFields[1].click();
      await emailFields[1].setValue(getTestPassword());

      if (await browser.isKeyboardShown()) {
        await browser.hideKeyboard();
      }

      const loginBtn = await Selectors.loginButton();
      await loginBtn.click();
    }

    // 2. Open Laporan tab
    const laporanTab = await $('android=new UiSelector().description("Laporan")');
    await laporanTab.waitForDisplayed({ timeout: 15000 });
    await laporanTab.click();

    // 3. Tap "Buat Laporan" button
    const createReportBtn = await $('android=new UiSelector().descriptionContains("Buat Laporan")');
    await createReportBtn.waitForDisplayed({ timeout: 10000 });
    await createReportBtn.click();

    // 4. Verify Create Report page fields
    const pageHeader = await $('android=new UiSelector().descriptionContains("Buat Laporan")');
    await pageHeader.waitForDisplayed({ timeout: 10000 });
    expect(await pageHeader.isDisplayed()).toBe(true);

    // Verify Dropdown / form elements exist
    const kategoriField = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().descriptionContains("Kategori"))'
    );
    expect(await kategoriField.isDisplayed()).toBe(true);

    // 5. Fill long text into Deskripsi to test responsive layout
    const descInput = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().className("android.widget.EditText"))'
    );
    await descInput.waitForDisplayed({ timeout: 10000 });
    await descInput.click();
    await descInput.setValue(
      'Pengujian tata letak responsif: deskripsi laporan kendala perangkat laboratorium komputer LabFlow untuk memastikan tidak ada RenderFlex overflow pada Android Virtual Device API 35.'
    );

    // Verify keyboard interaction does not crash or break layout
    const isKeyboardActive = await browser.isKeyboardShown();
    if (isKeyboardActive) {
      await browser.hideKeyboard();
    }

    // 6. Scroll into view and verify "Kirim Laporan" submit button
    const submitBtn = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().descriptionContains("Kirim Laporan"))'
    );
    await submitBtn.waitForDisplayed({ timeout: 10000 });
    expect(await submitBtn.isDisplayed()).toBe(true);

    // 7. Verify no UI overflow banners are present
    const overflowElements = await $$('android=new UiSelector().descriptionContains("overflowed by")');
    expect(overflowElements.length).toBe(0);

    await takeEvidenceScreenshot(browser, '08_student_report_responsive');
    await savePageSource(browser, '08_student_report_responsive');

    // Return to Laporan list
    await browser.back();
  });
});
