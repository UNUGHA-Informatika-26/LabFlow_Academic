import { expect } from 'expect';
import { Selectors } from '../helpers/selectors.js';
import { takeEvidenceScreenshot, savePageSource } from '../helpers/evidence.js';

describe('TEST A: Application Startup & Login Page Verification', () => {
  it('should launch LabFlow Local UAT and display Login Page without crash', async () => {
    // Wait for the app to settle
    await browser.pause(2000);

    const loginTitle = await Selectors.byDescriptionContains('Selamat Datang');
    await loginTitle.waitForDisplayed({ timeout: 15000 });

    const emailField = await Selectors.emailInput();
    const isEmailVisible = await emailField.isDisplayed();
    expect(isEmailVisible).toBe(true);

    const passwordField = await Selectors.passwordInput();
    const isPasswordVisible = await passwordField.isDisplayed();
    expect(isPasswordVisible).toBe(true);

    const loginBtn = await Selectors.loginButton();
    const isLoginBtnVisible = await loginBtn.isDisplayed();
    expect(isLoginBtnVisible).toBe(true);

    await takeEvidenceScreenshot(browser, '01_startup_login_page');
    await savePageSource(browser, '01_startup_login_page');
  });
});
