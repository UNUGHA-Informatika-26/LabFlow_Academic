'use strict';

const fs = require('node:fs/promises');

class MockEmailProvider {
  constructor({ outboxPath = process.env.LABFLOW_MOCK_EMAIL_OUTBOX } = {}) {
    this.outboxPath = outboxPath;
  }

  async send({ to, subject, type, actionLink }) {
    const mode = process.env.LABFLOW_MOCK_EMAIL_MODE || 'success';
    if (mode === 'failure') throw new Error('mock-email-failure');
    if (mode === 'timeout') {
      await new Promise((resolve) => setTimeout(resolve, 100));
      throw new Error('mock-email-timeout');
    }
    if (typeof to !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) {
      throw new Error('mock-email-invalid-recipient');
    }
    const message = {
      to,
      subject,
      type,
      actionLink,
      timestamp: new Date().toISOString(),
    };
    if (this.outboxPath) {
      let messages = [];
      try { messages = JSON.parse(await fs.readFile(this.outboxPath, 'utf8')); } catch (_) { /* first write */ }
      messages.push(message);
      await fs.writeFile(this.outboxPath, JSON.stringify(messages), 'utf8');
    }
    return { accepted: true };
  }
}

class SendGridEmailProvider {
  constructor({ apiKey, from, fetchImpl = fetch }) {
    this.apiKey = apiKey;
    this.from = from;
    this.fetchImpl = fetchImpl;
  }

  async send({ to, subject, text }) {
    const response = await this.fetchImpl('https://api.sendgrid.com/v3/mail/send', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        personalizations: [{ to: [{ email: to }] }],
        from: { email: this.from, name: 'LabFlow' },
        subject,
        content: [{ type: 'text/plain', value: text }],
      }),
    });
    if (!response.ok) {
      const error = new Error('sendgrid-rejected');
      error.status = response.status;
      throw error;
    }
    return { accepted: true };
  }
}

function createEmailProvider({ apiKey, from, isEmulator, outboxPath }) {
  if (isEmulator) return new MockEmailProvider({ outboxPath });
  if (!apiKey || !from) throw new Error('email-provider-not-configured');
  return new SendGridEmailProvider({ apiKey, from });
}

module.exports = { MockEmailProvider, SendGridEmailProvider, createEmailProvider };
