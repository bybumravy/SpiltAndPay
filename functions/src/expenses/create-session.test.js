import test from 'node:test';
import assert from 'node:assert/strict';
import { validateExpenseInput } from './mutations.js';
import { createSessionWithExpenses } from './create-session.js';

const validPayload = (overrides = {}) => ({
  sessionId: 's-1',
  creatorId: 'creator',
  session: { title: 'Dinner', totalAmount: 100 },
  members: [{ memberId: 'creator', userId: 'creator' }],
  expenses: [{
    expenseId: 'e-1',
    description: 'Food',
    amount: 100,
    payerId: 'creator',
    participantIds: ['creator'],
  }],
  ...overrides,
});

function fakeFirestore() {
  const writes = [];
  return {
    writes,
    collection(name) {
      assert.equal(name, 'sessions');
      return {
        doc(id) {
          return {
            id,
            collection(name) {
              return {
                doc(childId) {
                  return { path: `sessions/${id}/${name}/${childId}` };
                },
              };
            },
          };
        },
      };
    },
    batch() {
      return {
        set: (...args) => writes.push(['set', ...args]),
        commit: async () => writes.push(['commit']),
      };
    },
  };
}

test('create-session operation validates and persists the whole session and expense list atomically', async () => {
  const firestore = fakeFirestore();
  const create = createSessionWithExpenses({ firestore, validateExpenseInput });
  const result = await create(validPayload());

  assert.equal(result.sessionId, 's-1');
  assert.deepEqual(firestore.writes.map(([operation]) => operation), ['set', 'set', 'set', 'commit']);
  assert.equal(firestore.writes[1][1].path, 'sessions/s-1/members/creator');
  assert.equal(firestore.writes[2][1].path, 'sessions/s-1/expenses/e-1');
  assert.equal(firestore.writes[2][2].sequence, 1);
});

test('create-session operation rejects mismatched total before committing any writes', async () => {
  const firestore = fakeFirestore();
  const create = createSessionWithExpenses({ firestore, validateExpenseInput });

  await assert.rejects(
    create(validPayload({ session: { totalAmount: 101 } })),
    /total/i,
  );
  assert.equal(firestore.writes.length, 0);
});

test('create-session callable requires the authenticated creator', async () => {
  const create = createSessionWithExpenses({ firestore: {}, validateExpenseInput });
  await assert.rejects(
    create.callable.run({
      auth: { uid: 'other' },
      data: { sessionId: 's-1', creatorId: 'creator', session: {}, members: [], expenses: [] },
    }),
    { code: 'permission-denied' },
  );
});

test('rejects a session exceeding Firestore atomic batch write limit before writing', async () => {
  const firestore = fakeFirestore();
  const create = createSessionWithExpenses({ firestore, validateExpenseInput });
  const members = Array.from({ length: 499 }, (_, index) => ({
    memberId: index === 0 ? 'creator' : `member-${index}`,
    userId: index === 0 ? 'creator' : `user-${index}`,
  }));
  const expenses = Array.from({ length: 2 }, (_, index) => ({
    expenseId: `expense-${index}`,
    description: 'Item',
    amount: 1,
    payerId: 'creator',
    participantIds: ['creator'],
  }));

  await assert.rejects(
    create(validPayload({
      session: { totalAmount: 2 },
      members,
      expenses,
    })),
    /batch|writes|500/i,
  );
  assert.equal(firestore.writes.length, 0);
});
