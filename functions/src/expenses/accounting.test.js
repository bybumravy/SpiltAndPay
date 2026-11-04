import test from 'node:test';
import assert from 'node:assert/strict';
import { allocateExpense } from './allocation.js';
import { aggregateSession } from './settlement.js';

test('allocates an expense evenly with stable remainder order', () => {
  assert.deepEqual(allocateExpense(10, ['A', 'B', 'C']), { A: 4, B: 3, C: 3 });
  assert.deepEqual(allocateExpense(7, ['A']), { A: 7 });
});

test('rejects invalid expense amounts and participant lists', () => {
  for (const amount of [0, -1, 1.5, Number.NaN]) {
    assert.throws(() => allocateExpense(amount, ['A']), /amount/i);
  }
  assert.throws(() => allocateExpense(10, []), /participant/i);
  assert.throws(() => allocateExpense(10, ['A', 'A']), /participant/i);
});

test('aggregates mixed account and guest shares against the actual payer', () => {
  const result = aggregateSession(
    [
      { id: 'e1', amount: 10, payerId: 'A', participantIds: ['A', 'B', 'G'] },
      { id: 'e2', amount: 8, payerId: 'B', participantIds: ['A', 'B'] },
    ],
    [
      { id: 'A', type: 'account' },
      { id: 'B', type: 'account' },
      { id: 'G', type: 'guest' },
    ],
  );

  assert.deepEqual(result, {
    totalAmount: 18,
    paidByMember: { A: 10, B: 8 },
    owedByMember: { A: 8, B: 7, G: 3 },
    guestClaimsByPayer: { A: 3 },
    accountNetPositions: { A: -1, B: 1 },
  });
});

test('aggregated account positions sum to zero with multiple guest claims', () => {
  const result = aggregateSession(
    [
      { id: 'e1', amount: 11, payerId: 'A', participantIds: ['A', 'B', 'G1'] },
      { id: 'e2', amount: 7, payerId: 'B', participantIds: ['A', 'B', 'G2'] },
    ],
    [
      { id: 'A', type: 'account' },
      { id: 'B', type: 'account' },
      { id: 'G1', type: 'guest' },
      { id: 'G2', type: 'guest' },
    ],
  );

  assert.equal(result.totalAmount, 18);
  assert.deepEqual(result.guestClaimsByPayer, { A: 3, B: 2 });
  assert.equal(Object.values(result.accountNetPositions).reduce((sum, value) => sum + value, 0), 0);
});
