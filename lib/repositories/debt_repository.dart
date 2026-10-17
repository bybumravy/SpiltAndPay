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

  /// Con nợ bấm "Tôi đã chuyển": tạo payment pending cho đúng số đang nợ.
  ///
  /// Chạy trong transaction và kiểm tra trên dữ liệu hiện tại của server:
  ///  - không còn nợ → từ chối (tránh tạo payment sau khi đã trả đủ),
  ///  - đã có payment chờ xác nhận → từ chối (tránh trùng).
  Future<void> markTransferred({
    required String debtId,
    required String fromUid,
    required String toUid,
    required String paymentId,
  }) {
    return _db.runTransaction((tx) async {
      final debtRef = _debts.doc(debtId);
      final snap = await tx.get(debtRef);
      final data = snap.data();
      if (data == null) throw StateError('Không tìm thấy khoản nợ.');

      final balance = (data['balance'] as num).toInt();
      final owed = fromUid == data['userA'] ? balance : -balance;
      if (owed <= 0) throw StateError('Bạn không còn nợ khoản này.');
      if (data['pendingPaymentId'] != null) {
        throw StateError('Đang có giao dịch chờ xác nhận.');
      }

      tx.set(debtRef.collection('payments').doc(paymentId), {
        'fromUserId': fromUid,
        'toUserId': toUid,
        'amount': owed,
        'status': PaymentStatus.pending.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(debtRef, {'pendingPaymentId': paymentId});
    });
  }

  /// Chủ nợ bấm "Đã nhận": xác nhận payment + trừ balance trong transaction.
  /// Số tiền lấy từ payment đã lưu; chỉ xác nhận được payment đang pending.
  Future<void> confirmPayment({
    required String debtId,
    required String paymentId,
    required bool debtorIsUserA, // true → balance giảm, false → balance tăng
  }) async {
    await _db.runTransaction((tx) async {
      final debtRef = _debts.doc(debtId);
      final paymentRef = debtRef.collection('payments').doc(paymentId);

      final snap = await tx.get(paymentRef);
      final data = snap.data();
      if (data == null || data['status'] != PaymentStatus.pending.name) {
        throw StateError('Khoản thanh toán đã được xử lý.');
      }
      final amount = (data['amount'] as num).toInt();

      tx.update(paymentRef, {
        'status': PaymentStatus.confirmed.name,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
      tx.update(debtRef, {
        'balance': FieldValue.increment(debtorIsUserA ? -amount : amount),
        'pendingPaymentId': FieldValue.delete(),
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
