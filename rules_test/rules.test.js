import { test, before, after, beforeEach } from 'node:test';
import fs from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch,
  increment, deleteField, serverTimestamp,
} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-splitpay',
    firestore: { rules: fs.readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const db = (uid) => env.authenticatedContext(uid).firestore();

// Phiên 1000k: A tạo, A/B/C là thành viên.
async function seedOpenSession(id = 'S1', extra = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'sessions', id), {
      creatorId: 'A', title: 'x', totalAmount: 1000000, splitMode: 'equal',
      status: 'open', memberUserIds: ['A', 'B', 'C'], createdAt: new Date(), ...extra,
    });
  });
}

// B nợ A 300k (A < B → userA = A, balance âm), sổ đã có sẵn.
async function seedDebt(balance = -300000, pending = null) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'debts', 'A_B'), {
      userA: 'A', userB: 'B', participants: ['A', 'B'], balance,
      updatedAt: new Date(), ...(pending ? { pendingPaymentId: pending } : {}),
    });
  });
}

// Tương đương closeSession của app: đóng phiên + entry + balance trong 1 batch.
function closeBatch(d, { entryAmount = 300000, balanceDelta = -300000, sid = 'S1',
                         from = 'B', to = 'A', amountForEntry } = {}) {
  const b = writeBatch(d);
  b.update(doc(d, 'sessions', sid), { status: 'closed', closedAt: serverTimestamp() });
  b.set(doc(d, 'debts', 'A_B', 'entries', sid), {
    sessionId: sid, fromUserId: from, toUserId: to,
    amount: amountForEntry ?? entryAmount, createdAt: serverTimestamp(),
  });
  b.set(doc(d, 'debts', 'A_B'), {
    userA: 'A', userB: 'B', participants: ['A', 'B'],
    balance: increment(balanceDelta), lastEntryId: sid, updatedAt: serverTimestamp(),
  }, { merge: true });
  return b;
}

// ── Tạo phiên ────────────────────────────────────────────────────────────────

function createBatch(d, { total = 1000000, owed = 500000, paid = 0, creator = 'A' } = {}) {
  const b = writeBatch(d);
  b.set(doc(d, 'sessions', 'N1'), {
    creatorId: creator, title: 't', totalAmount: total, splitMode: 'equal',
    status: 'open', memberUserIds: ['A', 'B'], createdAt: new Date(),
  });
  b.set(doc(d, 'sessions', 'N1', 'members', 'A'), {
    userId: 'A', displayName: 'A', isGuest: false, amountOwed: owed, amountPaid: paid, status: 'self',
  });
  b.set(doc(d, 'sessions', 'N1', 'members', 'B'), {
    userId: 'B', displayName: 'B', isGuest: false, amountOwed: owed, amountPaid: 0, status: 'ledger',
  });
  return b;
}

test('tạo phiên hợp lệ', async () => {
  await assertSucceeds(createBatch(db('A')).commit());
});
test('không tạo phiên mạo danh người tạo khác', async () => {
  await assertFails(createBatch(db('B'), { creator: 'A' }).commit());
});
test('không tạo phiên tổng bill <= 0', async () => {
  await assertFails(createBatch(db('A'), { total: 0 }).commit());
});
test('không tạo phần chia lớn hơn tổng bill', async () => {
  await assertFails(createBatch(db('A'), { owed: 2000000 }).commit());
});
test('không tạo phần chia / ứng tiền âm', async () => {
  await assertFails(createBatch(db('A'), { owed: -5 }).commit());
  await assertFails(createBatch(db('A'), { paid: -5 }).commit());
});
test('người khác không tự thêm member vào phiên của A', async () => {
  await seedOpenSession();
  await assertFails(setDoc(doc(db('B'), 'sessions', 'S1', 'members', 'B'), {
    userId: 'B', displayName: 'B', isGuest: false, amountOwed: 0, amountPaid: 0, status: 'ledger',
  }));
});

// ── Đóng phiên / ghi nợ ──────────────────────────────────────────────────────

test('creator đóng phiên đúng: entry + balance khớp', async () => {
  await seedOpenSession();
  await assertSucceeds(closeBatch(db('A')).commit());
});
test('balance tăng nhiều hơn entry → bị chặn', async () => {
  await seedOpenSession();
  await assertFails(closeBatch(db('A'), { balanceDelta: -900000 }).commit());
});
test('balance sai dấu so với entry → bị chặn', async () => {
  await seedOpenSession();
  await assertFails(closeBatch(db('A'), { balanceDelta: 300000 }).commit());
});
test('entry lớn hơn tổng bill → bị chặn', async () => {
  await seedOpenSession();
  await assertFails(closeBatch(db('A'), { entryAmount: 5000000, balanceDelta: -5000000 }).commit());
});
test('không phải creator thì không đóng phiên / ghi nợ được', async () => {
  await seedOpenSession();
  await assertFails(closeBatch(db('B')).commit());
});
test('không ghi nợ cho người ngoài phiên', async () => {
  await seedOpenSession('S2', { memberUserIds: ['A', 'C'] });
  await assertFails(closeBatch(db('A'), { sid: 'S2' }).commit()); // B không thuộc S2
});
test('không đóng phiên 2 lần để cộng nợ trùng', async () => {
  await seedOpenSession();
  await assertSucceeds(closeBatch(db('A')).commit());
  await assertFails(closeBatch(db('A')).commit());
});

// ── Sửa trực tiếp balance / dữ liệu tiền ────────────────────────────────────

test('con nợ không tự xóa nợ', async () => {
  await seedDebt();
  await assertFails(updateDoc(doc(db('B'), 'debts', 'A_B'), { balance: 0 }));
});
test('chủ nợ không tự tăng nợ', async () => {
  await seedDebt();
  await assertFails(updateDoc(doc(db('A'), 'debts', 'A_B'), { balance: -9000000 }));
});
test('không xóa khoản nợ', async () => {
  await seedDebt();
  await assertFails(deleteDoc(doc(db('A'), 'debts', 'A_B')));
});
test('người ngoài không đọc được nợ của A-B', async () => {
  await seedDebt();
  await assertFails(getDoc(doc(db('C'), 'debts', 'A_B')));
  await assertSucceeds(getDoc(doc(db('B'), 'debts', 'A_B')));
});
test('không sửa tổng bill / phần chia sau khi tạo', async () => {
  await seedOpenSession();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'sessions', 'S1', 'members', 'B'), {
      userId: 'B', displayName: 'B', isGuest: false, amountOwed: 300000, amountPaid: 0, status: 'ledger',
    });
  });
  await assertFails(updateDoc(doc(db('A'), 'sessions', 'S1'), { totalAmount: 1 }));
  await assertFails(updateDoc(doc(db('A'), 'sessions', 'S1', 'members', 'B'), { amountOwed: 1 }));
  await assertSucceeds(updateDoc(doc(db('A'), 'sessions', 'S1'), { title: 'tên mới' }));
});
test('không xóa phiên đã đóng', async () => {
  await seedOpenSession('S3', { status: 'closed' });
  await assertFails(deleteDoc(doc(db('A'), 'sessions', 'S3')));
});

// ── Thanh toán ───────────────────────────────────────────────────────────────

function payBatch(d, { amount = 300000, pid = 'P1', from = 'B', to = 'A' } = {}) {
  const b = writeBatch(d);
  b.set(doc(d, 'debts', 'A_B', 'payments', pid), {
    fromUserId: from, toUserId: to, amount, status: 'pending', createdAt: serverTimestamp(),
  });
  b.update(doc(d, 'debts', 'A_B'), { pendingPaymentId: pid });
  return b;
}

function confirmBatch(d, { pid = 'P1', delta = 300000 } = {}) {
  const b = writeBatch(d);
  b.update(doc(d, 'debts', 'A_B', 'payments', pid), { status: 'confirmed', confirmedAt: serverTimestamp() });
  b.update(doc(d, 'debts', 'A_B'), {
    balance: increment(delta), pendingPaymentId: deleteField(), updatedAt: serverTimestamp(),
  });
  return b;
}

test('con nợ báo đã chuyển đúng số đang nợ', async () => {
  await seedDebt();
  await assertSucceeds(payBatch(db('B')).commit());
});
test('con nợ không báo chuyển sai số tiền', async () => {
  await seedDebt();
  await assertFails(payBatch(db('B'), { amount: 100 }).commit());
  await assertFails(payBatch(db('B'), { amount: 9000000 }).commit());
});
test('người không nợ không thể báo đã chuyển', async () => {
  await seedDebt();
  await assertFails(payBatch(db('A'), { from: 'A', to: 'B' }).commit()); // A không nợ B
});
test('chủ nợ xác nhận đúng: balance về 0', async () => {
  await seedDebt();
  await assertSucceeds(payBatch(db('B')).commit());
  await assertSucceeds(confirmBatch(db('A')).commit());
});
test('con nợ không tự xác nhận payment của mình', async () => {
  await seedDebt();
  await assertSucceeds(payBatch(db('B')).commit());
  await assertFails(confirmBatch(db('B')).commit());
});
test('chủ nợ xác nhận nhưng trừ sai số tiền → bị chặn', async () => {
  await seedDebt();
  await assertSucceeds(payBatch(db('B')).commit());
  await assertFails(confirmBatch(db('A'), { delta: 999999 }).commit());
  await assertFails(confirmBatch(db('A'), { delta: 100 }).commit());
});
test('không xác nhận 2 lần', async () => {
  await seedDebt();
  await assertSucceeds(payBatch(db('B')).commit());
  await assertSucceeds(confirmBatch(db('A')).commit());
  await assertFails(confirmBatch(db('A')).commit());
});
test('không tạo payment thứ 2 khi đang chờ xác nhận', async () => {
  await seedDebt();
  await assertSucceeds(payBatch(db('B')).commit());
  await assertFails(payBatch(db('B'), { pid: 'P2' }).commit());
});
test('không sửa số tiền payment', async () => {
  await seedDebt();
  await assertSucceeds(payBatch(db('B')).commit());
  await assertFails(updateDoc(doc(db('A'), 'debts', 'A_B', 'payments', 'P1'),
    { status: 'confirmed', amount: 1 }));
});

// ── Luồng hợp lệ khác (đảm bảo rules không chặn nhầm) ───────────────────────

test('đóng phiên lần 2 cộng dồn vào khoản nợ có sẵn', async () => {
  await seedDebt(-300000);
  await seedOpenSession('S2');
  await assertSucceeds(closeBatch(db('A'), { sid: 'S2', entryAmount: 50000, balanceDelta: -50000 }).commit());
});
test('chiều nợ ngược: A nợ B thì balance tăng', async () => {
  await seedDebt(0);
  await seedOpenSession('S2', { creatorId: 'B' });
  await assertSucceeds(closeBatch(db('B'), { sid: 'S2', from: 'A', to: 'B',
    entryAmount: 120000, balanceDelta: 120000 }).commit());
  await seedOpenSession('S3', { creatorId: 'B' });
  await assertFails(closeBatch(db('B'), { sid: 'S3', from: 'A', to: 'B',
    entryAmount: 120000, balanceDelta: -120000 }).commit()); // sai dấu
});
test('A (userA) là con nợ cũng báo chuyển & được xác nhận', async () => {
  await seedDebt(200000); // A nợ B 200k
  const dA = db('A');
  const b = writeBatch(dA);
  b.set(doc(dA, 'debts', 'A_B', 'payments', 'P9'),
    { fromUserId: 'A', toUserId: 'B', amount: 200000, status: 'pending', createdAt: serverTimestamp() });
  b.update(doc(dA, 'debts', 'A_B'), { pendingPaymentId: 'P9' });
  await assertSucceeds(b.commit());
  const dB = db('B');
  const c = writeBatch(dB);
  c.update(doc(dB, 'debts', 'A_B', 'payments', 'P9'), { status: 'confirmed', confirmedAt: serverTimestamp() });
  c.update(doc(dB, 'debts', 'A_B'), { balance: increment(-200000), pendingPaymentId: deleteField(), updatedAt: serverTimestamp() });
  await assertSucceeds(c.commit());
});
test('creator đánh dấu khách đã trả (kể cả sau khi đóng phiên)', async () => {
  await seedOpenSession('S4', { status: 'closed' });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'sessions', 'S4', 'members', 'G1'), {
      userId: null, displayName: 'Khách', isGuest: true, amountOwed: 100000, amountPaid: 0, status: 'pending',
    });
  });
  await assertSucceeds(updateDoc(doc(db('A'), 'sessions', 'S4', 'members', 'G1'), { status: 'paid' }));
  await assertFails(updateDoc(doc(db('B'), 'sessions', 'S4', 'members', 'G1'), { status: 'paid' }));
});
test('xóa phiên đang mở (kèm member) được; người khác thì không', async () => {
  await seedOpenSession('S5');
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'sessions', 'S5', 'members', 'B'), {
      userId: 'B', displayName: 'B', isGuest: false, amountOwed: 1, amountPaid: 0, status: 'ledger',
    });
  });
  const dB = db('B');
  const bad = writeBatch(dB);
  bad.delete(doc(dB, 'sessions', 'S5', 'members', 'B'));
  bad.delete(doc(dB, 'sessions', 'S5'));
  await assertFails(bad.commit());
  const dA = db('A');
  const ok = writeBatch(dA);
  ok.delete(doc(dA, 'sessions', 'S5', 'members', 'B'));
  ok.delete(doc(dA, 'sessions', 'S5'));
  await assertSucceeds(ok.commit());
});
test('thành viên đọc được phiên, người ngoài thì không', async () => {
  await seedOpenSession('S6');
  await assertSucceeds(getDoc(doc(db('B'), 'sessions', 'S6')));
  await assertFails(getDoc(doc(db('Z'), 'sessions', 'S6')));
});
