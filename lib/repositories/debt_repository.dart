import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/firebase_providers.dart';
import '../models/debt.dart';
import '../models/payment.dart';

class DebtRepository {
  final FirebaseFirestore _db;
  DebtRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _debts =>
      _db.collection('debts');

  /// Stream tất cả khoản nợ liên quan [uid] có balance != 0.
  Stream<List<Debt>> watchUserDebts(String uid) {
    return _debts
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((s) => s.docs
            .map((d) => Debt.fromMap(d.data()))
            .where((d) => d.balance != 0)
            .toList());
  }

  /// Stream payments (sub-collection) của cặp nợ [debtId].
  Stream<List<Payment>> watchPayments(String debtId) {
    return _debts
        .doc(debtId)
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList());
  }

  /// Con nợ bấm "Tôi đã chuyển": tạo payment pending.
  Future<void> markTransferred({
    required String debtId,
    required String fromUid,
    required String toUid,
    required int amount,
    required String paymentId,
  }) {
    return _debts.doc(debtId).collection('payments').doc(paymentId).set({
      'fromUserId': fromUid,
      'toUserId': toUid,
      'amount': amount,
      'status': PaymentStatus.pending.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Chủ nợ bấm "Đã nhận": xác nhận payment + trừ balance trong transaction.
  Future<void> confirmPayment({
    required String debtId,
    required String paymentId,
    required int amount,
    required bool debtorIsUserA, // true → balance giảm, false → balance tăng
  }) async {
    await _db.runTransaction((tx) async {
      final paymentRef = _debts
          .doc(debtId)
          .collection('payments')
          .doc(paymentId);
      final debtRef = _debts.doc(debtId);

      tx.update(paymentRef, {
        'status': PaymentStatus.confirmed.name,
        'confirmedAt': FieldValue.serverTimestamp(),
      });

      // Trừ balance: nếu debtorIsUserA thì balance -= amount, ngược lại += amount.
      final delta = debtorIsUserA ? -amount : amount;
      tx.update(debtRef, {
        'balance': FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

final debtRepositoryProvider = Provider<DebtRepository>((ref) {
  return DebtRepository(ref.watch(firestoreProvider));
});

final userDebtsProvider =
    StreamProvider.family<List<Debt>, String>((ref, uid) {
  return ref.watch(debtRepositoryProvider).watchUserDebts(uid);
});

final paymentsProvider =
    StreamProvider.family<List<Payment>, String>((ref, debtId) {
  return ref.watch(debtRepositoryProvider).watchPayments(debtId);
});
