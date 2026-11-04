import test from 'node:test';
import assert from 'node:assert/strict';
import { canCollectGuestObligation, collectGuestObligation } from './guest-collection.js';

test('only the actual payer can collect a pending guest obligation', () => {
  const obligation = { payerId: 'payer', status: 'pending' };
  assert.equal(canCollectGuestObligation(obligation, 'payer'), true);
  assert.equal(canCollectGuestObligation(obligation, 'creator'), false);
  assert.equal(canCollectGuestObligation({ ...obligation, status: 'collected' }, 'payer'), false);
});

test('collection is idempotent and retains the original audit record', () => {
  const timestamp = new Date('2026-11-02T00:00:00Z');
  const collected = collectGuestObligation({
    obligation: { id: 'G1', payerId: 'payer', amount: 50, status: 'pending', sessionId: 'S1' },
    actorId: 'payer',
    collectedAt: timestamp,
  });
  assert.equal(collected.status, 'collected');
  assert.equal(collected.collectedAt, timestamp);
  assert.deepEqual(collectGuestObligation({ obligation: collected, actorId: 'payer', collectedAt: new Date() }), collected);
});
