/// Trạng thái nợ của một thành viên trong phiên.
enum MemberStatus {
  /// Chính người tạo phiên (người trả bill) — không sinh nợ.
  self,

  /// User có app — nợ đã được đẩy vào collection `debts`.
  ledger,

  /// Guest chưa trả.
  pending,

  /// Guest đã trả, chủ nợ đã bấm "Đã thu".
  paid,
}

/// Một thành viên trong phiên chia tiền.
class SessionMember {
  /// memberId = uid nếu có app, uuid ngẫu nhiên nếu là Guest.
  final String memberId;

  /// null nếu là Guest.
  final String? userId;

  /// Tên hiển thị (snapshot lúc tạo phiên, hoặc tên Guest nhập tay).
  final String displayName;

  final bool isGuest;

  /// Số tiền phải trả (VND).
  final int amountOwed;

  /// Số tiền thành viên này đã ứng trả cho quán (VND). Mặc định 0.
  final int amountPaid;

  final MemberStatus status;
  final DateTime? paidAt;

  const SessionMember({
    required this.memberId,
    required this.userId,
    required this.displayName,
    required this.isGuest,
    required this.amountOwed,
    this.amountPaid = 0,
    required this.status,
    this.paidAt,
  });

  factory SessionMember.fromMap(String id, Map<String, dynamic> map) {
    return SessionMember(
      memberId: id,
      userId: map['userId'] as String?,
      displayName: map['displayName'] as String? ?? '',
      isGuest: map['isGuest'] as bool? ?? false,
      amountOwed: (map['amountOwed'] as num).toInt(),
      amountPaid: (map['amountPaid'] as num?)?.toInt() ?? 0,
      status: MemberStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => MemberStatus.pending,
      ),
      paidAt: map['paidAt'] != null
          ? (map['paidAt'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': displayName,
      'isGuest': isGuest,
      'amountOwed': amountOwed,
      'amountPaid': amountPaid,
      'status': status.name,
      if (paidAt != null) 'paidAt': paidAt,
    };
  }
}
