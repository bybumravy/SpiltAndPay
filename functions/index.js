import { initializeApp } from 'firebase-admin/app';
import { onRequest } from 'firebase-functions/v2/https';
import { createExpenseMutation } from './src/expenses/mutations.js';
import { createCloseSession } from './src/expenses/close-session.js';
import { createGuestCollection } from './src/expenses/guest-collection.js';
import { createSessionWithExpenses as createSessionWithExpensesHandler } from './src/expenses/create-session.js';

initializeApp();

export const health = onRequest((_request, response) => {
  response.status(200).send('ok');
});

export const mutateExpense = createExpenseMutation();
export const closeSession = createCloseSession();
export const markGuestObligationCollected = createGuestCollection();
export const createSessionWithExpenses = createSessionWithExpensesHandler().callable;
