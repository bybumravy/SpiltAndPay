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

  const Debt({
    required this.userA,
    required this.userB,
    required this.balance,
    required this.updatedAt,
  });

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
      userA: map['userA'] as String,
      userB: map['userB'] as String,
      balance: (map['balance'] as num).toInt(),
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userA': userA,
      'userB': userB,
      'participants': [userA, userB],
      'balance': balance,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
