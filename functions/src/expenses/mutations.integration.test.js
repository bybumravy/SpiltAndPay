import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { mutateExpense } from '../../index.js';

const emulatorAvailable = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const projectId = 'demo-splitpay';
const app = emulatorAvailable ? initializeApp({ projectId }, `expense-mutations-${process.pid}`) : null;
const firestore = app ? getFirestore(app) : null;
const invoke = (uid, data) => mutateExpense.run({ auth: { uid }, data });

before(async () => {
  if (!firestore) return;
  await firestore.collection('sessions').doc('mutation-test').set({
    creatorId: 'creator', status: 'open', memberUserIds: ['creator', 'other'], totalAmount: 0,
  });
  await firestore.collection('sessions').doc('mutation-test').collection('members').doc('creator').set({
    userId: 'creator', isGuest: false,
  });
  await firestore.collection('sessions').doc('mutation-test').collection('members').doc('other').set({
    userId: 'other', isGuest: false,
  });
  await firestore.collection('sessions').doc('mutation-test').collection('members').doc('guest').set({
    userId: null, isGuest: true,
  });
});

after(async () => {
  if (!firestore) return;
  await firestore.recursiveDelete(firestore.collection('sessions').doc('mutation-test'));
  await deleteApp(app);
});

beforeEach(async () => {
  if (!firestore) return;
  await firestore.collection('sessions').doc('mutation-test').update({ totalAmount: 0 });
  const expenses = firestore.collection('sessions').doc('mutation-test').collection('expenses');
  for (const doc of (await expenses.get()).docs) await doc.ref.delete();
});

test('creator can add, update and delete expense items transactionally', { skip: !emulatorAvailable }, async () => {
  const sessionRef = firestore.collection('sessions').doc('mutation-test');
  const seedRef = sessionRef.collection('expenses').doc('seed');
  await seedRef.set({ description: 'Seed', amount: 100, payerId: 'creator', participantIds: ['creator'] });
  await sessionRef.update({ totalAmount: 100 });
  const added = await invoke('creator', {
    sessionId: 'mutation-test', operation: 'add',
    expense: { description: 'Lunch', amount: 1000, payerId: 'creator', participantIds: ['creator', 'guest'] },
  });
  assert.equal(added.deleted, false);
  const itemRef = firestore.collection('sessions').doc('mutation-test').collection('expenses').doc(added.expenseId);
  assert.equal((await itemRef.get()).data().amount, 1000);
  assert.equal((await firestore.collection('sessions').doc('mutation-test').get()).data().totalAmount, 1100);

  await invoke('creator', {
    sessionId: 'mutation-test', expenseId: added.expenseId, operation: 'update',
    expense: { description: 'Dinner', amount: 2000, payerId: 'creator', participantIds: ['creator'] },
  });
  assert.equal((await itemRef.get()).data().description, 'Dinner');
  assert.equal((await firestore.collection('sessions').doc('mutation-test').get()).data().totalAmount, 2100);
  assert.deepEqual(await invoke('creator', { sessionId: 'mutation-test', expenseId: added.expenseId, operation: 'delete' }), {
    expenseId: added.expenseId, deleted: true,
  });
  assert.equal((await itemRef.get()).exists, false);
  assert.equal((await firestore.collection('sessions').doc('mutation-test').get()).data().totalAmount, 100);
});

test('cannot delete the final expense item and leave an inconsistent empty session', { skip: !emulatorAvailable }, async () => {
  const sessionRef = firestore.collection('sessions').doc('mutation-test');
  const itemRef = sessionRef.collection('expenses').doc('only-item');
  await itemRef.set({ description: 'Item', amount: 1000, payerId: 'creator', participantIds: ['creator'] });
  await sessionRef.update({ totalAmount: 1000 });
  await assert.rejects(invoke('creator', {
    sessionId: 'mutation-test', expenseId: 'only-item', operation: 'delete',
  }), { code: 'failed-precondition' });
  assert.equal((await itemRef.get()).exists, true);
  assert.equal((await sessionRef.get()).data().totalAmount, 1000);
});

test('legacy sessions without items reject itemized mutations without changing totals', { skip: !emulatorAvailable }, async () => {
  const sessionRef = firestore.collection('sessions').doc('mutation-test');
  await sessionRef.update({ totalAmount: 3000 });
  await assert.rejects(invoke('creator', {
    sessionId: 'mutation-test', operation: 'add',
    expense: { description: 'New item', amount: 1000, payerId: 'creator', participantIds: ['creator'] },
  }), { code: 'failed-precondition' });
  assert.equal((await sessionRef.get()).data().totalAmount, 3000);
});

test('mutation rejects noncreator, closed session and stale payer or participant', { skip: !emulatorAvailable }, async () => {
  const data = { sessionId: 'mutation-test', operation: 'add', expense: {
    description: 'Lunch', amount: 1000, payerId: 'creator', participantIds: ['creator'],
  } };
  await assert.rejects(invoke('other', data), { code: 'permission-denied' });
  await firestore.collection('sessions').doc('mutation-test').update({ status: 'closed' });
  await assert.rejects(invoke('creator', data), { code: 'failed-precondition' });
  await firestore.collection('sessions').doc('mutation-test').update({ status: 'open' });
  await assert.rejects(invoke('creator', { ...data, expense: { ...data.expense, payerId: 'guest' } }), { code: 'invalid-argument' });
  await assert.rejects(invoke('creator', { ...data, expense: { ...data.expense, participantIds: ['removed'] } }), { code: 'invalid-argument' });
});

test('item additions do not silently include later-added members', { skip: !emulatorAvailable }, async () => {
  const sessionRef = firestore.collection('sessions').doc('mutation-test');
  await sessionRef.collection('members').doc('later').set({ userId: 'later', isGuest: false });
  const result = await invoke('creator', {
    sessionId: 'mutation-test', operation: 'add',
    expense: { description: 'Lunch', amount: 1000, payerId: 'creator', participantIds: ['creator'] },
  });
  const stored = (await sessionRef.collection('expenses').doc(result.expenseId).get()).data();
  assert.deepEqual(stored.participantIds, ['creator']);
  await sessionRef.collection('members').doc('later').delete();
});
