import test from 'node:test';
import assert from 'node:assert/strict';
import { assertExpenseSessionAccess, calculateExpenseTotal, validateExpenseForMembers, validateExpenseInput } from './mutations.js';

test('calculates a safe session total from expense amounts', () => {
  assert.equal(calculateExpenseTotal([{ amount: 1250 }, { amount: 875 }]), 2125);
  assert.equal(calculateExpenseTotal([]), 0);
  assert.throws(() => calculateExpenseTotal([{ amount: Number.MAX_SAFE_INTEGER }, { amount: 1 }]), /total/i);
  assert.throws(() => calculateExpenseTotal([{ amount: -1 }]), /amount/i);
});

test('rejects unsafe or non-positive expense totals', () => {
  assert.throws(() => calculateExpenseTotal([{ amount: Number.MAX_SAFE_INTEGER }, { amount: 1 }]), /total/i);
  assert.throws(() => calculateExpenseTotal([{ amount: 0 }]), /amount/i);
  assert.throws(() => calculateExpenseTotal([{ amount: -1 }]), /amount/i);
});

test('accepts a valid expense with account payer and ordered member participants', () => {
  assert.deepEqual(
    validateExpenseInput({
      description: 'Lunch',
      amount: 100,
      payerId: 'A',
      participantIds: ['A', 'G'],
    }),
    { description: 'Lunch', amount: 100, payerId: 'A', participantIds: ['A', 'G'] },
  );
});

test('requires the authenticated user to own an open session', () => {
  assert.doesNotThrow(() => assertExpenseSessionAccess({ creatorId: 'A', status: 'open' }, 'A'));
  assert.throws(() => assertExpenseSessionAccess({ creatorId: 'A', status: 'open' }, 'B'), /creator/i);
  assert.throws(() => assertExpenseSessionAccess({ creatorId: 'A', status: 'closed' }, 'A'), /open/i);
});

test('requires an account payer and current members as participants', () => {
  const members = new Map([
    ['A', { userId: 'A', isGuest: false }],
    ['G', { userId: null, isGuest: true }],
  ]);
  assert.doesNotThrow(() => validateExpenseForMembers({ payerId: 'A', participantIds: ['A', 'G'] }, members));
  assert.throws(() => validateExpenseForMembers({ payerId: 'G', participantIds: ['A'] }, members), /payer/i);
  assert.throws(() => validateExpenseForMembers({ payerId: 'A', participantIds: ['missing'] }, members), /participant/i);
});

test('rejects invalid amount, payer, and empty or duplicate participants', () => {
  const valid = { description: 'Lunch', amount: 100, payerId: 'A', participantIds: ['A'] };
  for (const amount of [0, -1, 1.2, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => validateExpenseInput({ ...valid, amount }), /amount/i);
  }
  assert.throws(() => validateExpenseInput({ ...valid, payerId: '' }), /payer/i);
  assert.throws(() => validateExpenseInput({ ...valid, participantIds: [] }), /participant/i);
  assert.throws(() => validateExpenseInput({ ...valid, participantIds: ['A', 'A'] }), /participant/i);
});
