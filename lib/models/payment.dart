import 'package:cloud_firestore/cloud_firestore.dart';

/// Trạng thái một lần thanh toán.
enum PaymentStatus {
  /// Con nợ đã bấm "Tôi đã chuyển", chờ chủ nợ xác nhận.
  pending,

  /// Chủ nợ đã bấm "Đã nhận" — số tiền này được trừ khỏi balance.
  confirmed,

  /// Chủ nợ từ chối (chưa dùng trong MVP, dự phòng mở rộng).
  rejected,
}

/// Một lần thanh toán trong cặp nợ (sub-collection của `debts`).
class Payment {
  final String paymentId;
  final String fromUserId;
  final String toUserId;

  /// Số tiền snapshot lúc bấm "Tôi đã chuyển" (VND).
  final int amount;

  final PaymentStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;

  const Payment({
    required this.paymentId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
  });

  factory Payment.fromMap(String id, Map<String, dynamic> map) {
    return Payment(
      paymentId: id,
      fromUserId: map['fromUserId'] as String,
      toUserId: map['toUserId'] as String,
      amount: (map['amount'] as num).toInt(),
      status: PaymentStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => PaymentStatus.pending,
      ),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      confirmedAt: map['confirmedAt'] != null
          ? (map['confirmedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'amount': amount,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      if (confirmedAt != null) 'confirmedAt': Timestamp.fromDate(confirmedAt!),
    };
  }
}
