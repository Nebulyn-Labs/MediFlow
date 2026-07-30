/**
 * Firestore Security Rules – Emulator Tests
 *
 * Covers:
 *   Issue #195 – Facility users must not be able to self-approve requests
 *
 * Prerequisites:
 *   • Firebase Emulator Suite running with Firestore enabled
 *     (firebase emulators:start --only firestore)
 *   • FIRESTORE_EMULATOR_HOST env var set (default: 127.0.0.1:8080)
 *
 * Run:
 *   npm test --prefix functions -- --testPathPattern firestoreRules
 */

'use strict';

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const { resolve } = require('path');

// ─── Constants ────────────────────────────────────────────────────────────────

const PROJECT_ID = 'mediflow-test';
const RULES_PATH = resolve(__dirname, '../../firestore.rules');

const FACILITY_ID = 'facility-alpha';
const FACILITY_EMAIL = 'alpha@example.com';

const ADMIN_UID = 'admin-uid-001';
const FACILITY_HEAD_UID = 'head-uid-001';

// ─── Helpers ──────────────────────────────────────────────────────────────────

let testEnv;

function authedDb(uid, email) {
  return testEnv.authenticatedContext(uid, { email }).firestore();
}

// ─── Setup / Teardown ─────────────────────────────────────────────────────────

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: process.env.FIRESTORE_EMULATOR_HOST
        ? process.env.FIRESTORE_EMULATOR_HOST.split(':')[0]
        : '127.0.0.1',
      port: process.env.FIRESTORE_EMULATOR_HOST
        ? parseInt(process.env.FIRESTORE_EMULATOR_HOST.split(':')[1], 10)
        : 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await db.doc(`facilities/${FACILITY_ID}`).set({ email: FACILITY_EMAIL, name: 'Alpha Facility' });
    await db.doc(`users/${ADMIN_UID}`).set({ role: 'admin' });
    await db.doc(`users/${FACILITY_HEAD_UID}`).set({
      role: 'facility_head',
      facilityId: FACILITY_ID,
    });
    await db.doc('requests/req-001').set({
      facilityId: FACILITY_ID,
      status: 'pending',
      quantity: 10,
      type: 'indent',
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Issue #195 – Self-approval of requests
// ═══════════════════════════════════════════════════════════════════════════════

describe('Issue #195 – requests self-approval guard', () => {
  test('admin can set status to "approved"', async () => {
    const db = authedDb(ADMIN_UID, 'admin@mediflow.internal');
    await assertSucceeds(
      db.doc('requests/req-001').update({ status: 'approved' }),
    );
  });

  test('admin can set status to "fulfilled"', async () => {
    const db = authedDb(ADMIN_UID, 'admin@mediflow.internal');
    await assertSucceeds(
      db.doc('requests/req-001').update({ status: 'fulfilled' }),
    );
  });

  test('facility head CANNOT set status to "approved" on their own request', async () => {
    const db = authedDb(FACILITY_HEAD_UID, FACILITY_EMAIL);
    await assertFails(
      db.doc('requests/req-001').update({ status: 'approved' }),
    );
  });

  test('facility head CANNOT set status to "fulfilled" on their own request', async () => {
    const db = authedDb(FACILITY_HEAD_UID, FACILITY_EMAIL);
    await assertFails(
      db.doc('requests/req-001').update({ status: 'fulfilled' }),
    );
  });

  test('facility head CAN update quantity without changing status', async () => {
    const db = authedDb(FACILITY_HEAD_UID, FACILITY_EMAIL);
    await assertSucceeds(
      db.doc('requests/req-001').update({ quantity: 20 }),
    );
  });

  test('facility head CAN set status back to "pending" (withdraw)', async () => {
    const db = authedDb(FACILITY_HEAD_UID, FACILITY_EMAIL);
    await assertSucceeds(
      db.doc('requests/req-001').update({ status: 'pending', quantity: 5 }),
    );
  });

  test('unauthenticated user CANNOT update a request', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.doc('requests/req-001').update({ status: 'pending' }),
    );
  });
});
