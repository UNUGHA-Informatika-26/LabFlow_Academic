import { expect } from 'expect';
import { Selectors } from '../helpers/selectors.js';
import { TEST_ACCOUNTS, getTestPassword } from '../helpers/test_accounts.js';
import { takeEvidenceScreenshot, savePageSource } from '../helpers/evidence.js';

describe('TEST B: Superadmin Authentication & Dashboard Access', () => {
  it('should authenticate as Superadmin UAT and display administrative dashboard', async () => {
    // 1. Check if we need to log in
    const emailFields = await $$('android.widget.EditText');
    if (emailFields.length > 0) {
      // We are on login page
      const emailInput = emailFields[0];
      await emailInput.click();
      await emailInput.setValue(TEST_ACCOUNTS.superadmin.email);

      const passwordInput = emailFields[1];
      await passwordInput.click();
      await passwordInput.setValue(getTestPassword());

      if (await browser.isKeyboardShown()) {
        await browser.hideKeyboard();
      }

      const loginBtn = await Selectors.loginButton();
      await loginBtn.click();
    }

    // 2. Wait for Superadmin Dashboard bottom navigation bar
    const usersTab = await Selectors.byDescription('Users');
    await usersTab.waitForDisplayed({ timeout: 15000 });
    expect(await usersTab.isDisplayed()).toBe(true);

    const labsTab = await Selectors.byDescription('Laboratories');
    expect(await labsTab.isDisplayed()).toBe(true);

    const dashTab = await Selectors.byDescription('Dashboard');
    expect(await dashTab.isDisplayed()).toBe(true);

    // 3. Verify Kelola shortcut or statistics
    const kelolaAction = await Selectors.byDescriptionContains('Kelola');
    expect(await kelolaAction.isDisplayed()).toBe(true);

    await takeEvidenceScreenshot(browser, '03_superadmin_dashboard');
    await savePageSource(browser, '03_superadmin_dashboard');
  });
});
