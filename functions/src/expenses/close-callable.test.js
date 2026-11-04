import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { closeSession } from '../../index.js';

const emulatorAvailable = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const app = emulatorAvailable ? initializeApp({ projectId: 'demo-splitpay' }, `expense-close-${process.pid}`) : null;
const firestore = app ? getFirestore(app) : null;
const invoke = (uid, data) => closeSession.run({ auth: { uid }, data });

before(async () => {
  if (!firestore) return;
  const session = firestore.collection('sessions').doc('close-test');
  await session.set({ creatorId: 'A', status: 'open', totalAmount: 10, memberUserIds: ['A', 'B', 'G'] });
  await session.collection('members').doc('A').set({ userId: 'A', isGuest: false, amountOwed: 0, amountPaid: 0, status: 'self' });
  await session.collection('members').doc('B').set({ userId: 'B', isGuest: false, amountOwed: 0, amountPaid: 0, status: 'ledger' });
  await session.collection('members').doc('G').set({ userId: null, isGuest: true, amountOwed: 0, amountPaid: 0, status: 'pending' });
  await session.collection('expenses').doc('E1').set({ description: 'meal', amount: 10, payerId: 'A', participantIds: ['A', 'B', 'G'] });
});

after(async () => {
  if (!firestore) return;
  await firestore.recursiveDelete(firestore.collection('sessions').doc('close-test'));
  await firestore.recursiveDelete(firestore.collection('debts').doc('A_B'));
  await deleteApp(app);
});

test('creator closes itemized session once and retries idempotently', { skip: !emulatorAvailable }, async () => {
  const first = await invoke('A', { sessionId: 'close-test' });
  assert.equal(first.totalAmount, 10);
  const obligations = await firestore.collection('sessions').doc('close-test').collection('guestObligations').get();
  assert.equal(obligations.size, 1);
  const second = await invoke('A', { sessionId: 'close-test' });
  assert.deepEqual(second, first);
  assert.equal((await firestore.collection('sessions').doc('close-test').collection('guestObligations').get()).size, 1);
});
