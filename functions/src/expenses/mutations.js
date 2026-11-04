import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';

export function assertExpenseSessionAccess(session, actorId) {
  if (!session || session.creatorId !== actorId) {
    throw new TypeError('Only the session creator can edit expenses');
  }
  if (session.status !== 'open') {
    throw new TypeError('Only open sessions can be edited');
  }
}

export function validateExpenseForMembers(expense, membersById) {
  const payer = membersById.get(expense.payerId);
  if (!payer || payer.isGuest === true || !payer.userId) {
    throw new TypeError('Expense payer must be an account member');
  }
  if (expense.participantIds.some((id) => !membersById.has(id))) {
    throw new TypeError('Expense participants must be current session members');
  }
}

export function calculateExpenseTotal(expenses) {
  if (!Array.isArray(expenses)) throw new TypeError('Expenses must be a list');
  return expenses.reduce((total, expense) => {
    if (!Number.isSafeInteger(expense?.amount) || expense.amount <= 0) {
      throw new TypeError('Expense amount must be a positive safe integer');
    }
    const nextTotal = total + expense.amount;
    if (!Number.isSafeInteger(nextTotal)) throw new TypeError('Expense total must be a safe integer');
    return nextTotal;
  }, 0);
}

export function validateExpenseInput(input) {
  if (!input || !Number.isSafeInteger(input.amount) || input.amount <= 0) {
    throw new TypeError('Expense amount must be a positive safe integer');
  }
  if (typeof input.payerId !== 'string' || input.payerId.trim() === '') {
    throw new TypeError('Expense payer must be a nonempty member id');
  }
  if (!Array.isArray(input.participantIds) || input.participantIds.length === 0 ||
      input.participantIds.some((id) => typeof id !== 'string' || id.trim() === '') ||
      new Set(input.participantIds).size !== input.participantIds.length) {
    throw new TypeError('Expense participants must be unique nonempty member ids');
  }
  return {
    description: typeof input.description === 'string' ? input.description.trim() : '',
    amount: input.amount,
    payerId: input.payerId,
    participantIds: [...input.participantIds],
  };
}

export function createExpenseMutation({ firestore = getFirestore() } = {}) {
  return onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign-in is required.');
    const { sessionId, expenseId, operation = 'add', expense } = request.data ?? {};
    if (typeof sessionId !== 'string' || sessionId.trim() === '') {
      throw new HttpsError('invalid-argument', 'sessionId is required.');
    }
    if (!['add', 'update', 'delete'].includes(operation)) {
      throw new HttpsError('invalid-argument', 'Unsupported expense operation.');
    }

    const sessionRef = firestore.collection('sessions').doc(sessionId);
    const sessionSnapshot = await sessionRef.get();
    if (!sessionSnapshot.exists) throw new HttpsError('not-found', 'Session not found.');
    const session = sessionSnapshot.data();
    try {
      assertExpenseSessionAccess(session, request.auth.uid);
    } catch (error) {
      throw new HttpsError(session.status === 'open' ? 'permission-denied' : 'failed-precondition', error.message);
    }

    if (operation === 'delete' && (typeof expenseId !== 'string' || expenseId.trim() === '')) {
      throw new HttpsError('invalid-argument', 'expenseId is required.');
    }
    if (operation === 'delete') {
      const expensesRef = sessionRef.collection('expenses');
      const itemRef = expensesRef.doc(expenseId);
      await firestore.runTransaction(async (transaction) => {
        const [currentSession, currentItem, currentExpenses] = await Promise.all([
          transaction.get(sessionRef),
          transaction.get(itemRef),
          transaction.get(expensesRef),
        ]);
        if (!currentSession.exists || currentSession.data().creatorId !== request.auth.uid) {
          throw new HttpsError('permission-denied', 'Only the session creator can edit expenses.');
        }
        if (currentSession.data().status !== 'open') {
          throw new HttpsError('failed-precondition', 'Only open sessions can be edited.');
        }
        if (!currentItem.exists) throw new HttpsError('not-found', 'Expense not found.');
        if (currentExpenses.empty) {
          throw new HttpsError('failed-precondition', 'Legacy sessions without expense items cannot be edited as itemized sessions.');
        }
        if (currentExpenses.size <= 1) {
          throw new HttpsError('failed-precondition', 'A session must retain at least one expense item.');
        }
        const remainingTotal = calculateExpenseTotal(
          currentExpenses.docs.filter((doc) => doc.id !== expenseId).map((doc) => doc.data()),
        );
        transaction.delete(itemRef);
        transaction.update(sessionRef, { totalAmount: remainingTotal });
      });
      return { expenseId, deleted: true };
    }

    let validated;
    try {
      validated = validateExpenseInput(expense);
    } catch (error) {
      throw new HttpsError('invalid-argument', error.message);
    }
    const id = operation === 'add'
      ? (typeof expenseId === 'string' && expenseId.trim() ? expenseId : sessionRef.collection('expenses').doc().id)
      : expenseId;
    if (operation === 'update' && (typeof id !== 'string' || id.trim() === '')) {
      throw new HttpsError('invalid-argument', 'expenseId is required for updates.');
    }
    if (typeof id !== 'string' || id.trim() === '') {
      throw new HttpsError('invalid-argument', 'expenseId is required for updates.');
    }
    const itemRef = sessionRef.collection('expenses').doc(id);
    await firestore.runTransaction(async (transaction) => {
      const expensesRef = sessionRef.collection('expenses');
      const [currentSession, currentMembers, currentItem, currentExpenses] = await Promise.all([
        transaction.get(sessionRef),
        transaction.get(sessionRef.collection('members')),
        transaction.get(itemRef),
        transaction.get(expensesRef),
      ]);
      if (!currentSession.exists || currentSession.data().creatorId !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'Only the session creator can edit expenses.');
      }
      if (currentSession.data().status !== 'open') {
        throw new HttpsError('failed-precondition', 'Only open sessions can be edited.');
      }
      if (operation === 'update' && !currentItem.exists) {
        throw new HttpsError('not-found', 'Expense not found.');
      }
      if (currentExpenses.empty && currentSession.data().totalAmount > 0) {
        throw new HttpsError('failed-precondition', 'Legacy sessions without expense items cannot be edited as itemized sessions.');
      }
      if (operation === 'add' && currentItem.exists) {
        throw new HttpsError('already-exists', 'Expense already exists.');
      }
      const currentMemberById = new Map(currentMembers.docs.map((doc) => [doc.id, doc.data()]));
      try {
        validateExpenseForMembers(validated, currentMemberById);
      } catch (error) {
        throw new HttpsError('invalid-argument', error.message);
      }
      const existingExpenses = currentExpenses.docs
        .filter((doc) => doc.id !== id)
        .map((doc) => doc.data());
      const nextTotal = calculateExpenseTotal([...existingExpenses, validated]);
      transaction.set(itemRef, {
        ...validated,
        updatedAt: FieldValue.serverTimestamp(),
        ...(operation === 'add' ? { createdAt: FieldValue.serverTimestamp() } : {}),
      }, { merge: false });
      transaction.update(sessionRef, { totalAmount: nextTotal });
    });
    return { expenseId: id, deleted: false };
  });
}
