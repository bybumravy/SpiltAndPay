import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { validateExpenseInput as defaultValidateExpenseInput, validateExpenseForMembers } from './mutations.js';

export function createSessionWithExpenses({
  firestore = getFirestore(),
  validateExpenseInput = defaultValidateExpenseInput,
} = {}) {
  const create = async ({ sessionId, creatorId, session, members, expenses }) => {
    if (typeof sessionId !== 'string' || !sessionId.trim() ||
        typeof creatorId !== 'string' || !creatorId.trim() ||
        !session || typeof session !== 'object' ||
        !Array.isArray(members) || members.length === 0 ||
        !Array.isArray(expenses) || expenses.length === 0) {
      throw new HttpsError('invalid-argument', 'Session, members, and expenses are required.');
    }

    const memberById = new Map();
    for (const member of members) {
      if (!member || typeof member.memberId !== 'string' || !member.memberId.trim() || memberById.has(member.memberId)) {
        throw new HttpsError('invalid-argument', 'Session members must have unique ids.');
      }
      memberById.set(member.memberId, member);
    }
    const creator = memberById.get(creatorId);
    if (!creator || creator.userId !== creatorId || creator.isGuest === true) {
      throw new HttpsError('invalid-argument', 'Creator must be an account member.');
    }

    const writeCount = 1 + members.length + expenses.length;
    if (writeCount > 500) {
      throw new HttpsError(
        'resource-exhausted',
        'Session creation exceeds the Firestore atomic batch write limit.',
      );
    }

    const expenseIds = new Set();
    const validatedExpenses = expenses.map((input, index) => {
      if (!input || typeof input.expenseId !== 'string' || !input.expenseId.trim() || expenseIds.has(input.expenseId)) {
        throw new HttpsError('invalid-argument', 'Expenses must have unique ids.');
      }
      expenseIds.add(input.expenseId);
      let validated;
      try {
        validated = validateExpenseInput(input);
        validateExpenseForMembers(validated, memberById);
      } catch (error) {
        throw new HttpsError('invalid-argument', error.message);
      }
      return { id: input.expenseId, data: { ...validated, sequence: index + 1 } };
    });
    const expenseTotal = validatedExpenses.reduce((total, expense) => total + expense.data.amount, 0);
    if (!Number.isSafeInteger(session.totalAmount) || session.totalAmount !== expenseTotal) {
      throw new HttpsError('invalid-argument', 'Session total must match the expense total.');
    }

    const sessionRef = firestore.collection('sessions').doc(sessionId);
    const batch = firestore.batch();
    batch.set(sessionRef, {
      ...session,
      creatorId,
      status: 'open',
      createdAt: FieldValue.serverTimestamp(),
    });
    for (const member of members) {
      const { memberId, ...memberData } = member;
      batch.set(sessionRef.collection('members').doc(memberId), memberData);
    }
    for (const expense of validatedExpenses) {
      batch.set(sessionRef.collection('expenses').doc(expense.id), {
        ...expense.data,
        sequence: expense.data.sequence,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return { sessionId };
  };

  create.callable = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign-in is required.');
    const payload = request.data ?? {};
    if (payload.creatorId !== request.auth.uid) {
      throw new HttpsError('permission-denied', 'Only the authenticated creator can create a session.');
    }
    return create(payload);
  });
  return create;
}
