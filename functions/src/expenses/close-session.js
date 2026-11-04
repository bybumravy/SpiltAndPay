import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { aggregateSession } from './settlement.js';

function simplifyPositions(net) {
  const debtors = Object.entries(net).filter(([, amount]) => amount < 0)
    .map(([uid, amount]) => ({ uid, amount: -amount }))
    .sort((a, b) => b.amount - a.amount || a.uid.localeCompare(b.uid));
  const creditors = Object.entries(net).filter(([, amount]) => amount > 0)
    .map(([uid, amount]) => ({ uid, amount }))
    .sort((a, b) => b.amount - a.amount || a.uid.localeCompare(b.uid));
  const transfers = [];
  while (debtors.length && creditors.length) {
    const debtor = debtors[0];
    const creditor = creditors[0];
    const amount = Math.min(debtor.amount, creditor.amount);
    transfers.push({ from: debtor.uid, to: creditor.uid, amount });
    debtor.amount -= amount;
    creditor.amount -= amount;
    if (debtor.amount === 0) debtors.shift();
    if (creditor.amount === 0) creditors.shift();
    debtors.sort((a, b) => b.amount - a.amount || a.uid.localeCompare(b.uid));
    creditors.sort((a, b) => b.amount - a.amount || a.uid.localeCompare(b.uid));
  }
  if (debtors.length || creditors.length) throw new TypeError('Account positions must sum to zero');
  return transfers;
}

function validLegacyAmount(value, field) {
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError(`${field} must be a nonnegative safe integer`);
  return value;
}

function sharesFor(item) {
  const { amount, participantIds } = item;
  if (!Number.isSafeInteger(amount) || amount <= 0 || !Array.isArray(participantIds) || participantIds.length === 0 ||
      participantIds.some((id) => typeof id !== 'string' || !id.trim()) || new Set(participantIds).size !== participantIds.length) {
    throw new TypeError('Expense amount and participants are invalid');
  }
  const base = Math.floor(amount / participantIds.length);
  const remainder = amount % participantIds.length;
  return Object.fromEntries(participantIds.map((id, index) => [id, base + (index < remainder ? 1 : 0)]));
}

export function calculateSessionClose({ items, members, creatorId, expectedTotal }) {
  if (!Array.isArray(items) || !Array.isArray(members) || typeof creatorId !== 'string' || !creatorId) {
    throw new TypeError('Session close inputs are invalid');
  }
  const memberById = new Map();
  for (const member of members) {
    if (!member || typeof member.id !== 'string' || !member.id.trim() || memberById.has(member.id)) {
      throw new TypeError('Session members must have unique ids');
    }
    memberById.set(member.id, member);
  }

  if (items.length) {
    const normalizedMembers = members.map((member) => ({
      id: member.id,
      type: member.isGuest === true || !member.userId ? 'guest' : 'account',
    }));
    const aggregate = aggregateSession(items, normalizedMembers);
    if (expectedTotal !== undefined && aggregate.totalAmount !== expectedTotal) {
      throw new TypeError('Expense total does not match session total');
    }
    const obligations = [];
    for (const item of items) {
      const shares = sharesFor(item);
      const payer = memberById.get(item.payerId);
      if (!payer || payer.isGuest === true || !payer.userId) throw new TypeError('Expense payer must be an account member');
      for (const memberId of item.participantIds) {
        const member = memberById.get(memberId);
        if (!member) throw new TypeError('Expense participant must be a current member');
        if ((member.isGuest === true || !member.userId) && shares[memberId] > 0) {
          obligations.push({
            id: `${item.id}_${memberId}`,
            expenseId: item.id,
            payerId: payer.userId,
            guestMemberId: memberId,
            amount: shares[memberId],
            status: 'pending',
          });
        }
      }
    }
    const accountNetByUid = {};
    const paidByMember = {};
    const owedByMember = {};
    for (const member of members) {
      if (member.isGuest === true || !member.userId) continue;
      accountNetByUid[member.userId] = (accountNetByUid[member.userId] ?? 0) + (aggregate.accountNetPositions[member.id] ?? 0);
      paidByMember[member.id] = aggregate.paidByMember[member.id] ?? 0;
      owedByMember[member.id] = aggregate.owedByMember[member.id] ?? 0;
    }
    return {
      totalAmount: aggregate.totalAmount,
      paidByMember: aggregate.paidByMember,
      owedByMember: aggregate.owedByMember,
      obligations,
      transfers: simplifyPositions(accountNetByUid),
    };
  }

  const totalOwed = members.reduce((sum, member) => sum + validLegacyAmount(member.amountOwed, 'amountOwed'), 0);
  const paidSum = members.reduce((sum, member) => sum + validLegacyAmount(member.amountPaid ?? 0, 'amountPaid'), 0);
  const legacy = paidSum === 0;
  if (!legacy && paidSum !== totalOwed) throw new TypeError('Paid total does not match owed total');
  if (expectedTotal !== undefined && totalOwed !== expectedTotal) throw new TypeError('Legacy owed total does not match session total');
  const net = {};
  for (const member of members) {
    if (member.isGuest === true || !member.userId) continue;
    const paid = legacy && member.userId === creatorId ? totalOwed : member.amountPaid ?? 0;
    net[member.userId] = (net[member.userId] ?? 0) + paid - member.amountOwed;
  }
  const guestOwed = members.filter((member) => member.isGuest === true || !member.userId)
    .reduce((sum, member) => sum + validLegacyAmount(member.amountOwed, 'amountOwed'), 0);
  net[creatorId] = (net[creatorId] ?? 0) - guestOwed;
  return { totalAmount: totalOwed, paidByMember: {}, owedByMember: {}, obligations: [], transfers: simplifyPositions(net) };
}

export function createCloseSession({ firestore = getFirestore() } = {}) {
  return onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign-in is required.');
    const { sessionId } = request.data ?? {};
    if (typeof sessionId !== 'string' || !sessionId.trim()) {
      throw new HttpsError('invalid-argument', 'sessionId is required.');
    }
    const sessionRef = firestore.collection('sessions').doc(sessionId);
    return firestore.runTransaction(async (transaction) => {
      const sessionSnapshot = await transaction.get(sessionRef);
      if (!sessionSnapshot.exists) throw new HttpsError('not-found', 'Session not found.');
      const session = sessionSnapshot.data();
      if (session.status === 'closed' && session.closeResult) return session.closeResult;
      if (session.creatorId !== request.auth.uid) throw new HttpsError('permission-denied', 'Only the session creator can close it.');
      if (session.status !== 'open') throw new HttpsError('failed-precondition', 'Only open sessions can be closed.');

      const membersSnapshot = await transaction.get(sessionRef.collection('members'));
      const itemsSnapshot = await transaction.get(sessionRef.collection('expenses'));
      const members = membersSnapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      const items = itemsSnapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      let result;
      try {
        result = calculateSessionClose({
          items,
          members,
          creatorId: session.creatorId,
          expectedTotal: session.totalAmount,
        });
      } catch (error) {
        throw new HttpsError('failed-precondition', error.message);
      }

      const debtRefs = new Map();
      for (const transfer of result.transfers) {
        const [userA, userB] = [transfer.from, transfer.to].sort();
        const debtId = `${userA}_${userB}`;
        debtRefs.set(debtId, firestore.collection('debts').doc(debtId));
      }
      const debts = new Map();
      for (const [debtId, ref] of debtRefs) debts.set(debtId, await transaction.get(ref));

      for (const obligation of result.obligations) {
        const obligationRef = sessionRef.collection('guestObligations').doc(obligation.id);
        transaction.set(obligationRef, {
          ...obligation,
          sessionId,
          createdAt: FieldValue.serverTimestamp(),
          collectedAt: null,
          collectedBy: null,
        });
      }
      for (const transfer of result.transfers) {
        const [userA, userB] = [transfer.from, transfer.to].sort();
        const debtId = `${userA}_${userB}`;
        const debtRef = debtRefs.get(debtId);
        const old = debts.get(debtId).data();
        const delta = transfer.from === userA ? transfer.amount : -transfer.amount;
        const entryRef = debtRef.collection('entries').doc(sessionId);
        transaction.set(entryRef, {
          sessionId,
          fromUserId: transfer.from,
          toUserId: transfer.to,
          amount: transfer.amount,
          createdAt: FieldValue.serverTimestamp(),
        });
        transaction.set(debtRef, {
          userA,
          userB,
          participants: [userA, userB],
          balance: (old?.balance ?? 0) + delta,
          lastEntryId: sessionId,
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      for (const memberDoc of membersSnapshot.docs) {
        const member = memberDoc.data();
        if (member.isGuest === true || !member.userId) continue;
        const memberOwed = result.owedByMember[memberDoc.id] ?? member.amountOwed ?? 0;
        const memberPaid = result.paidByMember[memberDoc.id] ?? member.amountPaid ?? 0;
        transaction.update(memberDoc.ref, {
          amountOwed: memberOwed,
          amountPaid: memberPaid,
          status: member.userId === session.creatorId ? 'paid' : 'ledger',
        });
      }
      transaction.update(sessionRef, {
        status: 'closed',
        closedAt: FieldValue.serverTimestamp(),
        totalAmount: result.totalAmount,
        closeResult: result,
      });
      return result;
    });
  });
}
