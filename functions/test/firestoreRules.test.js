/**
 * Firestore Security Rules – Emulator Tests
 *
 * Covers:
 *   Issue #195 – Facility users must not be able to self-approve requests
 *   Issue #196 – Users must not be able to claim a facilityId they don't own
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

const { describe, test, before, after, beforeEach } = require('node:test');
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
const OTHER_FACILITY_ID = 'facility-beta';
const FACILITY_EMAIL = 'alpha@example.com';
const OTHER_EMAIL = 'beta@example.com';

const ADMIN_UID = 'admin-uid-001';
const FACILITY_HEAD_UID = 'head-uid-001';
const ATTACKER_UID = 'attacker-uid-001';

// ─── Helpers ──────────────────────────────────────────────────────────────────

let testEnv;

function authedDb(uid, email) {
  return testEnv.authenticatedContext(uid, { email }).firestore();
}

// ─── Setup / Teardown ─────────────────────────────────────────────────────────

before(async () => {
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

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    // Facilities
    await db.doc(`facilities/${FACILITY_ID}`).set({ email: FACILITY_EMAIL, name: 'Alpha Facility' });
    await db.doc(`facilities/${OTHER_FACILITY_ID}`).set({ email: OTHER_EMAIL, name: 'Beta Facility' });

    // Admin user
    await db.doc(`users/${ADMIN_UID}`).set({ role: 'admin' });

    // Facility head (legitimate, already registered)
    await db.doc(`users/${FACILITY_HEAD_UID}`).set({
      role: 'facility_head',
      facilityId: FACILITY_ID,
    });

    // An existing pending request owned by the facility head
    await db.doc('requests/req-001').set({
      facilityId: FACILITY_ID,
      status: 'pending',
      quantity: 10,
      type: 'indent',
    });

    // Inventory & Medicines
    await db.doc(`inventory/${FACILITY_ID}`).set({ name: 'Alpha Inventory' });
    await db.doc(`inventory/${FACILITY_ID}/medicines/med-001`).set({ name: 'Paracetamol' });

    // Daily Usage Logs
    await db.doc(`daily_usage_logs/${FACILITY_ID}`).set({ created: true });
    await db.doc(`daily_usage_logs/${FACILITY_ID}/logs/log-001`).set({ quantity: 5 });
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

// ═══════════════════════════════════════════════════════════════════════════════
// Issue #196 – facilityId ownership on user self-registration
// ═══════════════════════════════════════════════════════════════════════════════

describe('Issue #196 – users facilityId ownership on create', () => {
  test('user CAN register when their email matches the facility email', async () => {
    const db = authedDb('new-head-uid', FACILITY_EMAIL);
    await assertSucceeds(
      db.doc('users/new-head-uid').set({
        role: 'facility_head',
        facilityId: FACILITY_ID,
      }),
    );
  });

  test('attacker CANNOT self-register with a facilityId that belongs to another email', async () => {
    const db = authedDb(ATTACKER_UID, 'attacker@evil.example');
    await assertFails(
      db.doc(`users/${ATTACKER_UID}`).set({
        role: 'facility_head',
        facilityId: FACILITY_ID, // owned by FACILITY_EMAIL, not attacker's email
      }),
    );
  });

  test('attacker CANNOT register with a non-existent facilityId', async () => {
    const db = authedDb(ATTACKER_UID, 'attacker@evil.example');
    await assertFails(
      db.doc(`users/${ATTACKER_UID}`).set({
        role: 'facility_head',
        facilityId: 'does-not-exist',
      }),
    );
  });

  test('attacker CANNOT omit facilityId to bypass the ownership check', async () => {
    const db = authedDb(ATTACKER_UID, 'attacker@evil.example');
    await assertFails(
      db.doc(`users/${ATTACKER_UID}`).set({
        role: 'facility_head',
        // facilityId deliberately omitted
      }),
    );
  });

  test('admin CAN create a user document with any facilityId', async () => {
    const db = authedDb(ADMIN_UID, 'admin@mediflow.internal');
    await assertSucceeds(
      db.doc('users/any-new-user').set({
        role: 'facility_head',
        facilityId: FACILITY_ID,
      }),
    );
  });

  test('user CANNOT create a user document for a different uid', async () => {
    const db = authedDb(ATTACKER_UID, FACILITY_EMAIL);
    await assertFails(
      db.doc(`users/${FACILITY_HEAD_UID}`).set({
        role: 'facility_head',
        facilityId: FACILITY_ID,
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Issue #274 – Database wipe and delete rules enforcement
// ═══════════════════════════════════════════════════════════════════════════════

describe('Issue #274 – database wipe and delete rules enforcement', () => {
  test('admin CAN delete inventory and medicines documents', async () => {
    const db = authedDb(ADMIN_UID, 'admin@mediflow.internal');
    await assertSucceeds(db.doc(`inventory/${FACILITY_ID}/medicines/med-001`).delete());
    await assertSucceeds(db.doc(`inventory/${FACILITY_ID}`).delete());
  });

  test('facility head CANNOT delete inventory or medicines documents', async () => {
    const db = authedDb(FACILITY_HEAD_UID, FACILITY_EMAIL);
    await assertFails(db.doc(`inventory/${FACILITY_ID}/medicines/med-001`).delete());
    await assertFails(db.doc(`inventory/${FACILITY_ID}`).delete());
  });

  test('admin CAN delete daily_usage_logs and logs documents', async () => {
    const db = authedDb(ADMIN_UID, 'admin@mediflow.internal');
    await assertSucceeds(db.doc(`daily_usage_logs/${FACILITY_ID}/logs/log-001`).delete());
    await assertSucceeds(db.doc(`daily_usage_logs/${FACILITY_ID}`).delete());
  });

  test('facility head CANNOT delete daily_usage_logs or logs documents', async () => {
    const db = authedDb(FACILITY_HEAD_UID, FACILITY_EMAIL);
    await assertFails(db.doc(`daily_usage_logs/${FACILITY_ID}/logs/log-001`).delete());
    await assertFails(db.doc(`daily_usage_logs/${FACILITY_ID}`).delete());
  });

  test('unauthenticated user CANNOT delete inventory, medicines, daily_usage_logs, or requests documents', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc(`inventory/${FACILITY_ID}`).delete());
    await assertFails(db.doc(`inventory/${FACILITY_ID}/medicines/med-001`).delete());
    await assertFails(db.doc(`daily_usage_logs/${FACILITY_ID}`).delete());
    await assertFails(db.doc(`daily_usage_logs/${FACILITY_ID}/logs/log-001`).delete());
    await assertFails(db.doc('requests/req-001').delete());
  });
});
