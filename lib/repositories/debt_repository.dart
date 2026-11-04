import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
  /// Bổ sung cơ chế auto-retry khi gặp độ trễ đồng bộ Auth token (permission-denied thoáng qua).
  Stream<List<Debt>> watchUserDebts(String uid) async* {
    var retryCount = 0;
    while (true) {
      try {
        await for (final s
            in _debts.where('participants', arrayContains: uid).snapshots()) {
          retryCount = 0;
          yield s.docs
              .map((d) => Debt.fromMap(d.data()))
              .where((d) => d.balance != 0)
              .toList();
        }
        break;
      } catch (e) {
        if (e.toString().contains('permission-denied') && retryCount < 3) {
          retryCount++;
          debugPrint(
            'watchUserDebts: permission-denied transient, retrying ($retryCount/3)...',
          );
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Stream payments (sub-collection) của cặp nợ [debtId].
  /// Khởi tạo danh sách rỗng và bắt lỗi (tránh crash khi cloud rules từ chối).
  Stream<List<Payment>> watchPayments(String debtId) async* {
    yield <Payment>[];
    try {
      await for (final s
          in _debts
              .doc(debtId)
              .collection('payments')
              .orderBy('createdAt', descending: true)
              .snapshots()) {
        yield s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList();
      }
    } catch (e) {
      debugPrint('watchPayments error (cloud permission): $e');
    }
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

final userDebtsProvider = StreamProvider.family<List<Debt>, String>((ref, uid) {
  return ref.watch(debtRepositoryProvider).watchUserDebts(uid);
});

final paymentsProvider = StreamProvider.autoDispose
    .family<List<Payment>, String>((ref, debtId) {
      return ref.watch(debtRepositoryProvider).watchPayments(debtId);
    });
