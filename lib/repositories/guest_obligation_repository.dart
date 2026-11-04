import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/firebase_providers.dart';
import '../models/expense.dart';

class GuestObligationRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  GuestObligationRepository(this._db, [FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

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
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn cần đăng nhập để xác nhận đã thu.');
    final reference = _db
        .collection('sessions')
        .doc(sessionId)
        .collection('guestObligations')
        .doc(obligationId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (data == null) throw StateError('Không tìm thấy khoản guest phải thu.');
      final obligation = GuestObligation.fromMap(obligationId, data);
      final updated = collectGuestObligation(obligation, actorUid: uid);
      if (updated == null) throw StateError('Chỉ người trả khoản chi được xác nhận đã thu.');
      if (obligation.status == GuestObligationStatus.collected) return;
      transaction.update(reference, {
        'status': GuestObligationStatus.collected.name,
        'collectedAt': FieldValue.serverTimestamp(),
        'collectedBy': uid,
      });
    });
  }
}

final guestObligationRepositoryProvider = Provider<GuestObligationRepository>((
  ref,
) {
  return GuestObligationRepository(
    ref.watch(firestoreProvider),
    ref.watch(authProvider),
  );
});

final sessionGuestObligationsProvider =
    StreamProvider.family<List<GuestObligation>, String>((ref, sessionId) {
  return ref
      .watch(guestObligationRepositoryProvider)
      .watchSessionObligations(sessionId);
});
