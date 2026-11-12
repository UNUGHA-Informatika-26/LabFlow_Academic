'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { MockEmailProvider, createEmailProvider } = require('../src/email_provider');

test('mock provider captures safe email metadata without network transport', async () => {
  const provider = new MockEmailProvider();
  const result = await provider.send({
    to: 'target@example.test', subject: 'Subject', type: 'password_reset',
    actionLink: 'https://example.test/action',
  });
  assert.equal(result.accepted, true);
});

test('mock provider failure modes are deterministic', async () => {
  const previous = process.env.LABFLOW_MOCK_EMAIL_MODE;
  for (const mode of ['failure', 'timeout']) {
    process.env.LABFLOW_MOCK_EMAIL_MODE = mode;
    await assert.rejects(() => new MockEmailProvider().send({ to: 'target@example.test' }));
  }
  process.env.LABFLOW_MOCK_EMAIL_MODE = previous;
});

test('emulator provider selection cannot fall back to SendGrid', () => {
  const provider = createEmailProvider({ isEmulator: true, apiKey: 'ignored', from: 'ignored' });
  assert.equal(provider.constructor.name, 'MockEmailProvider');
});
