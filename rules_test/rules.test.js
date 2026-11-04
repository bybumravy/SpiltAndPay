import { test, before, after, beforeEach } from 'node:test';
import fs from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  collection, getDocs, doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch,
  increment, deleteField, serverTimestamp, query, where,
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
    await setDoc(doc(d, 'sessions', id, 'members', 'A'), {
      userId: 'A', displayName: 'A', isGuest: false, amountOwed: 500000, amountPaid: 0, status: 'self',
    });
    await setDoc(doc(d, 'sessions', id, 'members', 'B'), {
      userId: 'B', displayName: 'B', isGuest: false, amountOwed: 500000, amountPaid: 0, status: 'ledger',
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
  b.update(doc(d, 'sessions', sid), {
    status: 'closed', closedAt: serverTimestamp(), totalAmount: 1000000,
    closeResult: { totalAmount: 1000000, transfers: [], guestObligationIds: [] },
  });
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

test('creator closes an open session atomically with a matching debt entry', async () => {
  await seedOpenSession();
  await assertSucceeds(closeBatch(db('A')).commit());
});

test('non-creator cannot close a session or write its debt entry', async () => {
  await seedOpenSession();
  await assertFails(closeBatch(db('B')).commit());
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
test('a session can only be closed once', async () => {
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
test('thành viên đọc được khoản chi và nghĩa vụ guest, người ngoài bị chặn', async () => {
  await seedOpenSession();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'sessions', 'S1', 'expenses', 'E1'), { amount: 100 });
    await setDoc(doc(d, 'sessions', 'S1', 'guestObligations', 'G1'), { amount: 50 });
  });
  await assertSucceeds(getDoc(doc(db('B'), 'sessions', 'S1', 'expenses', 'E1')));
  await assertSucceeds(getDoc(doc(db('B'), 'sessions', 'S1', 'guestObligations', 'G1')));
  await assertFails(getDoc(doc(db('Z'), 'sessions', 'S1', 'expenses', 'E1')));
  await assertFails(getDoc(doc(db('Z'), 'sessions', 'S1', 'guestObligations', 'G1')));
});

test('creator adds an expense only atomically with its session total update', async () => {
  await seedOpenSession();
  const d = db('A');
  const batch = writeBatch(d);
  batch.set(doc(d, 'sessions', 'S1', 'expenses', 'E1'), {
    description: 'Lunch', amount: 100, payerId: 'A', participantIds: ['A'],
    shares: { A: 100 }, sequence: 0,
  });
  batch.update(doc(d, 'sessions', 'S1'), { totalAmount: 1000100, lastExpenseMutationId: 'E1' });
  await assertSucceeds(batch.commit());
});

test('member cannot create an expense even while preserving the session total', async () => {
  await seedOpenSession();
  const d = db('B');
  const batch = writeBatch(d);
  batch.set(doc(d, 'sessions', 'S1', 'expenses', 'E1'), {
    description: 'Lunch', amount: 100, payerId: 'B', participantIds: ['B'],
    shares: { B: 100 }, sequence: 0,
  });
  batch.update(doc(d, 'sessions', 'S1'), { totalAmount: 1000100, lastExpenseMutationId: 'E1' });
  await assertFails(batch.commit());
});

test('client cannot create guest obligations before session close', async () => {
  await seedOpenSession();
  await assertFails(setDoc(doc(db('A'), 'sessions', 'S1', 'guestObligations', 'G1'), {
    payerId: 'A', guestMemberId: 'G', amount: 100, status: 'pending',
  }));
});


test('client không thể sửa total hoặc accounting outputs', async () => {
  await seedOpenSession();
  await assertFails(updateDoc(doc(db('A'), 'sessions', 'S1'), {
    totalAmount: 1, paidByMember: { A: 1 },
  }));
  await assertFails(updateDoc(doc(db('A'), 'sessions', 'S1'), {
    accounting: { accountNetPositions: { A: 999999 } },
  }));
});

test('creator can add, update, and delete expenses with the matching session totals', async () => {
  await seedOpenSession();
  const d = db('A');
  const expense = doc(d, 'sessions', 'S1', 'expenses', 'E1');
  const session = doc(d, 'sessions', 'S1');

  const add = writeBatch(d);
  add.set(expense, {
    description: 'Lunch', amount: 100, payerId: 'A', participantIds: ['A'],
    shares: { A: 100 }, sequence: 0,
  });
  add.update(session, { totalAmount: 1000100, lastExpenseMutationId: 'E1' });
  await assertSucceeds(add.commit());

  const edit = writeBatch(d);
  edit.update(expense, { amount: 200, shares: { A: 200 } });
  edit.update(session, { totalAmount: 1000200, lastExpenseMutationId: 'E1' });
  await assertSucceeds(edit.commit());

  const remove = writeBatch(d);
  remove.delete(expense);
  remove.update(session, { totalAmount: 1000000, lastExpenseMutationId: 'E1' });
  await assertSucceeds(remove.commit());
});

test('creator can create an initial session with multiple expenses atomically', async () => {
  const d = db('A');
  const batch = writeBatch(d);
  batch.set(doc(d, 'sessions', 'NEW'), {
    creatorId: 'A', title: 'Dinner', totalAmount: 300, splitMode: 'equal',
    status: 'open', memberUserIds: ['A'], createdAt: new Date(),
  });
  batch.set(doc(d, 'sessions', 'NEW', 'members', 'A'), {
    userId: 'A', displayName: 'A', isGuest: false, amountOwed: 300, amountPaid: 0, status: 'self',
  });
  batch.set(doc(d, 'sessions', 'NEW', 'expenses', 'E1'), {
    description: 'Food', amount: 100, payerId: 'A', participantIds: ['A'], shares: { A: 100 }, sequence: 0,
  });
  batch.set(doc(d, 'sessions', 'NEW', 'expenses', 'E2'), {
    description: 'Drinks', amount: 200, payerId: 'A', participantIds: ['A'], shares: { A: 200 }, sequence: 1,
  });
  await assertSucceeds(batch.commit());
});

test('client cannot rewrite member shares or accounting values', async () => {
  await seedOpenSession();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'sessions', 'S1', 'members', 'B'), {
      userId: 'B', displayName: 'B', isGuest: false, amountOwed: 300000, amountPaid: 0, status: 'ledger',
    });
  });
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

test('không cộng nợ trực tiếp vào khoản nợ có sẵn từ client', async () => {
  await seedDebt(-300000);
  await seedOpenSession('S2');
  await assertSucceeds(closeBatch(db('A'), { sid: 'S2', entryAmount: 50000, balanceDelta: -50000 }).commit());
});
test('client may write a creator-computed debt direction and sign', async () => {
  await seedDebt(0);
  await seedOpenSession('S2', { creatorId: 'B' });
  await assertSucceeds(closeBatch(db('B'), { sid: 'S2', from: 'A', to: 'B',
    entryAmount: 120000, balanceDelta: 120000 }).commit());
  await seedOpenSession('S3', { creatorId: 'B' });
  await assertFails(closeBatch(db('B'), { sid: 'S3', from: 'A', to: 'B',
    entryAmount: 120000, balanceDelta: -120000 }).commit());
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
test('guest status cannot be client-edited after close; collection uses callable', async () => {
  await seedOpenSession('S4', { status: 'closed' });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'sessions', 'S4', 'members', 'G1'), {
      userId: null, displayName: 'Khách', isGuest: true, amountOwed: 100000, amountPaid: 0, status: 'pending',
    });
  });
  await assertFails(updateDoc(doc(db('A'), 'sessions', 'S4', 'members', 'G1'), { status: 'paid' }));
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

test('members can list session members; outsiders cannot', async () => {
  await seedOpenSession();
  await assertSucceeds(getDocs(collection(db('A'), 'sessions', 'S1', 'members')));
  await assertSucceeds(getDocs(collection(db('B'), 'sessions', 'S1', 'members')));
  await assertFails(getDocs(collection(db('D'), 'sessions', 'S1', 'members')));
});

function fullDraftEdit(d, marker = 'draft-edit') {
  const b = writeBatch(d);
  b.update(doc(d, 'sessions', 'S1'), {
    title: 'Edited trip', totalAmount: 100001, memberUserIds: ['A', 'D'],
    splitMode: 'equal', lastExpenseMutationId: marker,
  });
  b.delete(doc(d, 'sessions', 'S1', 'members', 'B'));
  for (const [id, guest, owed, paid] of [['A',false,33334,0],['D',false,33334,100001],['G',true,33333,0]]) {
    b.set(doc(d, 'sessions', 'S1', 'members', id), {
      userId: guest ? null : id, displayName: id + ' edited', isGuest: guest,
      amountOwed: owed, amountPaid: paid, status: guest ? 'pending' : id === 'A' ? 'self' : 'ledger',
    });
  }
  b.set(doc(d, 'sessions', 'S1', 'expenses', 'edited'), {
    description: 'Changed payer and participants', amount:100001, payerId:'D',
    participantIds:['A','D','G'], shares:{A:33334,D:33334,G:33333}, sequence:0,
  });
  return b;
}

test('creator can atomically edit title membership payer shares and accounting of an open draft', async () => {
  await seedOpenSession();
  await assertSucceeds(fullDraftEdit(db('A')).commit());
  const parent = await getDoc(doc(db('A'), 'sessions', 'S1'));
  const payer = await getDoc(doc(db('D'), 'sessions', 'S1', 'members', 'D'));
  if (parent.data().totalAmount !== 100001 || payer.data().amountPaid !== 100001) throw new Error('Accounting not updated');
  await assertSucceeds(getDocs(collection(db('D'), 'sessions', 'S1', 'members')));
  await assertFails(getDoc(doc(db('B'), 'sessions', 'S1')));
  await assertFails(getDocs(collection(db('B'), 'sessions', 'S1', 'members')));
});

test('full edits do not grant non-creators write access or reopen closed sessions', async () => {
  await seedOpenSession();
  await assertFails(fullDraftEdit(db('B')).commit());
  await env.withSecurityRulesDisabled(async ctx => updateDoc(doc(ctx.firestore(), 'sessions', 'S1'), {status:'closed'}));
  await assertFails(fullDraftEdit(db('A')).commit());
});

test('draft member accounting changes require a parent edit and cannot change user identity', async () => {
  await seedOpenSession();
  await assertFails(updateDoc(doc(db('A'), 'sessions', 'S1', 'members', 'B'), {amountPaid:100}));
  const actor = db('A');
  const b = fullDraftEdit(actor);
  b.update(doc(actor, 'sessions', 'S1', 'members', 'A'), {userId:'D'});
  await assertFails(b.commit());
});

test('edited open draft still closes once and accepts a matching full payment', async () => {
  await seedOpenSession();
  await assertSucceeds(fullDraftEdit(db('A')).commit());
  const d = db('A'); const b = writeBatch(d);
  b.update(doc(d,'sessions','S1'), {status:'closed',closedAt:serverTimestamp(),closeResult:{totalAmount:100001}, totalAmount:100001});
  b.set(doc(d,'debts','A_D'), {userA:'A',userB:'D',participants:['A','D'],balance:33334,lastEntryId:'S1',updatedAt:serverTimestamp()});
  b.set(doc(d,'debts','A_D','entries','S1'), {sessionId:'S1',fromUserId:'A',toUserId:'D',amount:33334,createdAt:serverTimestamp()});
  b.set(doc(d,'sessions','S1','guestObligations','edited_G'), {sessionId:'S1',expenseId:'edited',payerId:'D',guestMemberId:'G',amount:33333,status:'pending'});
  await assertSucceeds(b.commit());
  await assertFails(fullDraftEdit(d, 'closed-edit').commit());
  const pay = writeBatch(d);
  pay.set(doc(d,'debts','A_D','payments','P1'), {fromUserId:'A',toUserId:'D',amount:33334,status:'pending',createdAt:serverTimestamp()});
  pay.update(doc(d,'debts','A_D'), {pendingPaymentId:'P1'});
  await assertSucceeds(pay.commit());
  const creditor = db('D');
  const confirm = writeBatch(creditor);
  confirm.update(doc(creditor,'debts','A_D','payments','P1'), {status:'confirmed',confirmedAt:serverTimestamp()});
  confirm.update(doc(creditor,'debts','A_D'), {balance:0,pendingPaymentId:deleteField(),updatedAt:serverTimestamp()});
  await assertSucceeds(confirm.commit());
  await assertSucceeds(updateDoc(doc(db('D'),'sessions','S1','guestObligations','edited_G'), {status:'collected',collectedBy:'D',collectedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('A'),'sessions','S1','guestObligations','edited_G'), {status:'collected',collectedBy:'A',collectedAt:serverTimestamp()}));
});

const invitation = (s = 'A', r = 'B') => ({senderId:s, recipientId:r, participants:[s,r], senderName:s, recipientName:r, status:'pending', createdAt:serverTimestamp()});
test('friendship requires recipient consent and blocks direct contact writes', async () => {
  await assertFails(setDoc(doc(db('A'), 'users/A/contacts/B'), {name:'B'}));
  await assertFails(setDoc(doc(db('A'), 'users/B/contacts/A'), {name:'A'}));
  await assertSucceeds(setDoc(doc(db('A'), 'friendRequests/A_B'), invitation()));
  await assertFails(updateDoc(doc(db('A'), 'friendRequests/A_B'), {status:'accepted'}));
  await assertFails(updateDoc(doc(db('C'), 'friendRequests/A_B'), {status:'accepted'}));
  await assertFails(setDoc(doc(db('B'), 'friendRequests/B_A'), invitation('B','A')));
  await assertFails(setDoc(doc(db('B'), 'users/A/contacts/B'), {name:'B'}));
  const recipientDb = db('B');
  const batch = writeBatch(recipientDb);
  batch.update(doc(recipientDb, 'friendRequests/A_B'), {status:'accepted'});
  batch.set(doc(recipientDb, 'users/A/contacts/B'), {name:'B'});
  batch.set(doc(recipientDb, 'users/B/contacts/A'), {name:'A'});
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(db('B'), 'friendRequests/A_B'), {status:'pending'}));
  await assertFails(getDoc(doc(db('C'), 'friendRequests/A_B')));
  await assertSucceeds(getDocs(query(collection(db('B'), 'friendRequests'), where('participants','array-contains','B'))));
});
test('invitations block forgery and self invites; participants can reject or cancel', async () => {
  await assertFails(setDoc(doc(db('C'), 'friendRequests/A_B'), invitation()));
  await assertFails(setDoc(doc(db('A'), 'friendRequests/A_A'), invitation('A','A')));
  await assertSucceeds(setDoc(doc(db('A'), 'friendRequests/A_B'), invitation()));
  await assertFails(deleteDoc(doc(db('C'), 'friendRequests/A_B')));
  await assertSucceeds(deleteDoc(doc(db('B'), 'friendRequests/A_B')));
  await assertSucceeds(setDoc(doc(db('A'), 'friendRequests/A_B'), invitation()));
  await assertSucceeds(deleteDoc(doc(db('A'), 'friendRequests/A_B')));
});
