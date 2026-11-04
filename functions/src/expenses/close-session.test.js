import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateSessionClose } from './close-session.js';

test('calculates account settlement and payer-owned guest claims across items', () => {
  const result = calculateSessionClose({
    items: [
      { id: 'E1', amount: 10, payerId: 'A', participantIds: ['A', 'B', 'G'] },
      { id: 'E2', amount: 8, payerId: 'B', participantIds: ['A', 'B'] },
    ],
    members: [
      { id: 'A', userId: 'A', isGuest: false },
      { id: 'B', userId: 'B', isGuest: false },
      { id: 'G', userId: null, isGuest: true },
    ],
    creatorId: 'A',
  });
  assert.equal(result.totalAmount, 18);
  assert.deepEqual(result.obligations.map(({ payerId, guestMemberId, amount }) => ({ payerId, guestMemberId, amount })), [
    { payerId: 'A', guestMemberId: 'G', amount: 3 },
  ]);
  assert.deepEqual(result.transfers, [{ from: 'A', to: 'B', amount: 1 }]);
});

test('preserves legacy allocations and creator fallback when amountPaid is absent or zero', () => {
  const result = calculateSessionClose({
    items: [],
    members: [
      { id: 'A-member', userId: 'A', isGuest: false, amountOwed: 60, amountPaid: 0 },
      { id: 'B-member', userId: 'B', isGuest: false, amountOwed: 30 },
      { id: 'G-member', userId: null, isGuest: true, amountOwed: 10 },
    ],
    creatorId: 'A',
  });
  assert.equal(result.totalAmount, 100);
  assert.deepEqual(result.transfers, [{ from: 'B', to: 'A', amount: 30 }]);
  assert.deepEqual(result.obligations, []);
});

test('rejects item totals that disagree with the stored session total', () => {
  assert.throws(() => calculateSessionClose({ items: [
    { id: 'E1', amount: 5, payerId: 'A', participantIds: ['A'] },
  ], members: [{ id: 'A', userId: 'A', isGuest: false }], creatorId: 'A', expectedTotal: 6 }), /total/i);
});
