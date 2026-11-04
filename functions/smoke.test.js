import test from 'node:test';
import assert from 'node:assert/strict';
import { createSessionWithExpenses, health } from './index.js';

test('exports the Functions health handler', () => {
  assert.equal(typeof health, 'function');
});

test('exports createSessionWithExpenses as a deployable callable', () => {
  assert.equal(typeof createSessionWithExpenses, 'function');
  assert.ok(createSessionWithExpenses.__endpoint);
});
