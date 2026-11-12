export const config = {
  runner: 'local',
  port: 4723,
  path: '/',
  specs: [
    './tests/**/*.test.js'
  ],
  exclude: [],
  maxInstances: 1,
  capabilities: [{
    platformName: 'Android',
    'appium:automationName': 'UiAutomator2',
    'appium:udid': 'emulator-5554',
    'appium:appPackage': 'id.ac.unugha.labflow',
    'appium:appActivity': 'id.ac.unugha.labflow.MainActivity',
    'appium:noReset': true,
    'appium:fullReset': false,
    'appium:newCommandTimeout': 240,
    'appium:autoGrantPermissions': true,
  }],
  logLevel: 'info',
  bail: 0,
  waitforTimeout: 20000,
  connectionRetryTimeout: 120000,
  connectionRetryCount: 2,
  framework: 'mocha',
  reporters: ['spec'],
  mochaOpts: {
    ui: 'bdd',
    timeout: 120000,
  },
};
