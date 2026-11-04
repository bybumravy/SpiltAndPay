import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { markGuestObligationCollected } from '../../index.js';

const emulatorAvailable = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const app = emulatorAvailable ? initializeApp({ projectId: 'demo-splitpay' }, `guest-collection-${process.pid}`) : null;
const firestore = app ? getFirestore(app) : null;
const invoke = (uid) => markGuestObligationCollected.run({
  auth: { uid }, data: { sessionId: 'collect-test', obligationId: 'O1' },
});

before(async () => {
  if (!firestore) return;
  await firestore.collection('sessions').doc('collect-test').set({ status: 'closed' });
  await firestore.collection('sessions').doc('collect-test').collection('guestObligations').doc('O1').set({
    sessionId: 'collect-test', expenseId: 'E1', payerId: 'payer', guestMemberId: 'guest', amount: 20, status: 'pending',
  });
  await firestore.collection('debts').doc('payer_guest').set({ balance: 0 });
});

after(async () => {
  if (!firestore) return;
  await firestore.recursiveDelete(firestore.collection('sessions').doc('collect-test'));
  await firestore.recursiveDelete(firestore.collection('debts').doc('payer_guest'));
  await deleteApp(app);
});

test('payer can confirm guest collection once; creator/nonpayer cannot and debt is unchanged', { skip: !emulatorAvailable }, async () => {
  await assert.rejects(invoke('creator'), { code: 'permission-denied' });
  await assert.rejects(invoke('guest'), { code: 'permission-denied' });
  const result = await invoke('payer');
  assert.equal(result.status, 'collected');
  const obligation = (await firestore.collection('sessions').doc('collect-test').collection('guestObligations').doc('O1').get()).data();
  assert.equal(obligation.collectedBy, 'payer');
  assert.equal(obligation.status, 'collected');
  assert.equal((await firestore.collection('debts').doc('payer_guest').get()).data().balance, 0);
  assert.deepEqual(await invoke('payer'), result);
});
