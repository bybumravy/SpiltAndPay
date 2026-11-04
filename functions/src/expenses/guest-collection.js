import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

export function canCollectGuestObligation(obligation, actorId) {
  return obligation?.status === 'pending' && obligation.payerId === actorId;
}

export function collectGuestObligation({ obligation, actorId, collectedAt }) {
  if (!canCollectGuestObligation(obligation, actorId)) {
    if (obligation?.status === 'collected' && obligation.collectedBy === actorId) return obligation;
    throw new TypeError('Only the actual payer can collect a pending guest obligation');
  }
  return { ...obligation, status: 'collected', collectedAt, collectedBy: actorId };
}

export function createGuestCollection({ firestore = getFirestore() } = {}) {
  return onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign-in is required.');
    const { sessionId, obligationId } = request.data ?? {};
    if (typeof sessionId !== 'string' || !sessionId.trim() || typeof obligationId !== 'string' || !obligationId.trim()) {
      throw new HttpsError('invalid-argument', 'sessionId and obligationId are required.');
    }
    const obligationRef = firestore.collection('sessions').doc(sessionId).collection('guestObligations').doc(obligationId);
    return firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(obligationRef);
      if (!snapshot.exists) throw new HttpsError('not-found', 'Guest obligation not found.');
      const obligation = snapshot.data();
      if (obligation.status === 'collected' && obligation.collectedBy === request.auth.uid) {
        return { obligationId, status: 'collected' };
      }
      if (obligation.payerId !== request.auth.uid) throw new HttpsError('permission-denied', 'Only the actual payer can confirm guest collection.');
      if (obligation.status !== 'pending') throw new HttpsError('failed-precondition', 'Guest obligation is not pending.');
      transaction.update(obligationRef, {
        status: 'collected',
        collectedAt: FieldValue.serverTimestamp(),
        collectedBy: request.auth.uid,
      });
      return { obligationId, status: 'collected' };
    });
  });
}
