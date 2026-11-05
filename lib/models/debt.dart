import 'package:cloud_firestore/cloud_firestore.dart';

/// Tổng nợ cộng dồn giữa 2 user có app.
///
/// Document ID = "{uidNhỏ}_{uidLớn}" (sắp xếp lexicographic để tránh trùng chiều).
/// [balance] > 0: userA nợ userB.
/// [balance] < 0: userB nợ userA.
/// [balance] == 0: đã hòa.
class Debt {
  /// ID của user có uid lexicographically nhỏ hơn.
  final String userA;

  /// ID của user có uid lexicographically lớn hơn.
  final String userB;

  /// Số tiền net (VND). Dương → userA nợ userB, âm → userB nợ userA.
  final int balance;

  final DateTime updatedAt;

  /// ID của giao dịch thanh toán đang chờ xác nhận (nếu có).
  final String? pendingPaymentId;

  const Debt({
    required this.userA,
    required this.userB,
    required this.balance,
    required this.updatedAt,
    this.pendingPaymentId,
  });

  /// Kiểm tra khoản nợ có giao dịch thanh toán đang chờ chủ nợ xác nhận hay không
  bool get hasPendingPayment =>
      pendingPaymentId != null && pendingPaymentId!.isNotEmpty;

  Debt copyWith({
    String? userA,
    String? userB,
    int? balance,
    DateTime? updatedAt,
    String? pendingPaymentId,
    bool clearPendingPayment = false,
  }) {
    return Debt(
      userA: userA ?? this.userA,
      userB: userB ?? this.userB,
      balance: balance ?? this.balance,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingPaymentId:
          clearPendingPayment ? null : (pendingPaymentId ?? this.pendingPaymentId),
    );
  }

  /// Tạo document ID ổn định từ 2 uid.
  static String docId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Độ thay đổi của [balance] khi [debtorUid] nợ thêm [creditorUid] [amount].
  /// Dương → balance tăng (userA nợ thêm userB), âm → giảm.
  static int balanceDelta({
    required String debtorUid,
    required String creditorUid,
    required int amount,
  }) {
    return debtorUid.compareTo(creditorUid) < 0 ? amount : -amount;
  }

  /// Trả về số tiền [currentUserId] đang nợ phía bên kia.
  /// Số dương = đang nợ, số âm = người kia đang nợ mình.
  int amountOwedBy(String currentUserId) {
    return currentUserId == userA ? balance : -balance;
  }

  /// uid của chủ nợ từ góc nhìn của [currentUserId].
  /// null nếu không ai nợ ai (balance == 0).
  String? creditorFor(String currentUserId) {
    if (balance == 0) return null;
    if (currentUserId == userA) return balance > 0 ? userB : null;
    return balance < 0 ? userA : null;
  }

  factory Debt.fromMap(Map<String, dynamic> map) {
    return Debt(
      userA: map['userA'] as String? ?? '',
      userB: map['userB'] as String? ?? '',
      balance: (map['balance'] as num?)?.toInt() ?? 0,
      updatedAt: map['updatedAt'] is Timestamp
          ? (map['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      pendingPaymentId: map['pendingPaymentId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{
      'userA': userA,
      'userB': userB,
      'participants': [userA, userB],
      'balance': balance,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
    if (pendingPaymentId != null) {
      data['pendingPaymentId'] = pendingPaymentId;
    }
    return data;
  }
}

/// Immutable settlement generated when a session closes.
class DebtEntry {
  final String sessionId;
  final String fromUserId;
  final String toUserId;
  final int amount;
  final DateTime createdAt;

  const DebtEntry({
    required this.sessionId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'sessionId': sessionId,
    'fromUserId': fromUserId,
    'toUserId': toUserId,
    'amount': amount,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
