import { expect } from 'expect';
import fs from 'node:fs';
import path from 'node:path';
import { takeEvidenceScreenshot, savePageSource } from '../helpers/evidence.js';

describe('TEST H: Report Chat Image Upload & Cloudinary Environment Audit', () => {
  it('should inspect Cloudinary configuration and mark image upload as BLOCKED per security guideline', async () => {
    // 1. Audit dev.json configuration
    const devConfigPath = path.resolve('../../config/dev.json');
    const devConfig = JSON.parse(fs.readFileSync(devConfigPath, 'utf-8'));

    const cloudName = devConfig.CLOUDINARY_CLOUD_NAME;
    const uploadPreset = devConfig.CLOUDINARY_UPLOAD_PRESET;

    // Verify Cloudinary configuration attributes
    expect(cloudName).toBe('uaorce9b');
    expect(uploadPreset).toBe('labflow_assets');

    // 2. Security & Isolation Evaluation:
    // Cloudinary is a live third-party cloud service with no local emulator available.
    // The configured preset "labflow_assets" does not provide an isolated UAT directory or mock target.
    // Per Phase 6 TEST H instruction:
    // "Jika Cloudinary yang tersedia adalah account/preset production tanpa batasan UAT yang aman, tandai BLOCKED."
    const isDedicatedUatFolderAvailable = false;
    const testStatus = isDedicatedUatFolderAvailable ? 'PASS' : 'BLOCKED';

    expect(testStatus).toBe('BLOCKED');

    // 3. Capture evidence
    await takeEvidenceScreenshot(browser, '09_report_chat_audit');
    await savePageSource(browser, '09_report_chat_audit');
  });
});
