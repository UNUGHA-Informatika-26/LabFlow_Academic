import { expect } from 'expect';
import { Selectors } from '../helpers/selectors.js';
import { takeEvidenceScreenshot, savePageSource } from '../helpers/evidence.js';

describe('TEST F: Bantuan Akses Akun (Self-Service Recovery Procedure)', () => {
  it('should open Bantuan Akses Akun page without email input and show template', async () => {
    // Locate and click "Lupa password?"
    const forgotBtn = await Selectors.forgotPasswordButton();
    await forgotBtn.waitForDisplayed({ timeout: 10000 });
    await forgotBtn.click();

    // Verify title "Bantuan Akses Akun"
    const title = await Selectors.byDescriptionContains('Bantuan Akses Akun');
    await title.waitForDisplayed({ timeout: 10000 });
    expect(await title.isDisplayed()).toBe(true);

    // Verify template notice
    const procedureNotice = await Selectors.byDescriptionContains('Prosedur Pemulihan Terkelola');
    expect(await procedureNotice.isDisplayed()).toBe(true);

    // Verify no email input field exists on this page (enforces managed recovery procedure)
    const editTexts = await $$('android.widget.EditText');
    expect(editTexts.length).toBe(0);

    // Scroll to and verify "Salin Template" button
    const copyBtn = await $(
      'android=new UiScrollable(new UiSelector().scrollable(true)).scrollIntoView(new UiSelector().descriptionContains("Salin Template"))'
    );
    await copyBtn.waitForDisplayed({ timeout: 10000 });
    expect(await copyBtn.isDisplayed()).toBe(true);
    await copyBtn.click();

    await takeEvidenceScreenshot(browser, '02_bantuan_akses_akun');
    await savePageSource(browser, '02_bantuan_akses_akun');

    // Return to Login page
    await browser.back();
    const loginBtn = await Selectors.loginButton();
    await loginBtn.waitForDisplayed({ timeout: 10000 });
    expect(await loginBtn.isDisplayed()).toBe(true);
  });
});
