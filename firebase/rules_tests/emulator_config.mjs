const [configuredHost, configuredPort] = (process.env.FIRESTORE_EMULATOR_HOST || '').split(':');

export const FIRESTORE_HOST = configuredHost || '127.0.0.1';
export const FIRESTORE_PORT = Number(
  process.env.FIRESTORE_EMULATOR_PORT || configuredPort || 18080,
);
