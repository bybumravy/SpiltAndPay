import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/firebase_providers.dart';
import '../models/expense.dart';

class GuestObligationRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  GuestObligationRepository(this._db, this._functions);

  Stream<List<GuestObligation>> watchSessionObligations(String sessionId) {
    return _db
        .collection('sessions')
        .doc(sessionId)
        .collection('guestObligations')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GuestObligation.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> markCollected({
    required String sessionId,
    required String obligationId,
  }) async {
    await _functions.httpsCallable('markGuestObligationCollected').call({
      'sessionId': sessionId,
      'obligationId': obligationId,
    });
  }
}

final guestObligationRepositoryProvider = Provider<GuestObligationRepository>((
  ref,
) {
  return GuestObligationRepository(
    ref.watch(firestoreProvider),
    FirebaseFunctions.instance,
  );
});

final sessionGuestObligationsProvider =
    StreamProvider.family<List<GuestObligation>, String>((ref, sessionId) {
      return ref
          .watch(guestObligationRepositoryProvider)
          .watchSessionObligations(sessionId);
    });
