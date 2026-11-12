import path from 'node:path';
import fs from 'node:fs';

const SCREENSHOT_DIR = path.resolve('reports/screenshots');
const LOG_DIR = path.resolve('reports/logs');

export async function takeEvidenceScreenshot(driver, name) {
  if (!fs.existsSync(SCREENSHOT_DIR)) {
    fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
  }
  const filename = `${name.replace(/[^a-zA-Z0-9_-]/g, '_')}.png`;
  const targetPath = path.join(SCREENSHOT_DIR, filename);
  await driver.saveScreenshot(targetPath);
  return targetPath;
}

export async function savePageSource(driver, name) {
  if (!fs.existsSync(LOG_DIR)) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
  }
  const filename = `${name.replace(/[^a-zA-Z0-9_-]/g, '_')}_source.xml`;
  const targetPath = path.join(LOG_DIR, filename);
  const source = await driver.getPageSource();
  fs.writeFileSync(targetPath, source, 'utf-8');
  return targetPath;
}
