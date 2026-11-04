import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  debtReminder,
  sessionClosed,
  paymentPending,
  paymentConfirmed,
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final String? targetDebtId;
  final String? targetSessionId;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.targetDebtId,
    this.targetSessionId,
    this.isRead = false,
    required this.createdAt,
  });

  /// Thông báo này có được phép ẩn khi đã đọc hay không?
  /// - Thông báo nợ chưa trả (`debt_need_pay_`): KHÔNG ĐƯỢC PHÉP ẨN
  ///   (chỉ được ẩn khi đã xác nhận trả nợ thành công, tức nợ về 0).
  /// - Thông báo đã xác nhận trả nợ, cho vay, phiên đóng: ĐƯỢC ẨN khi đã đọc.
  bool get canDismissOnRead => !id.startsWith('debt_need_pay_');

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    NotificationType? type,
    String? targetDebtId,
    String? targetSessionId,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      targetDebtId: targetDebtId ?? this.targetDebtId,
      targetSessionId: targetSessionId ?? this.targetSessionId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      title: map['title'] as String? ?? 'Thông báo',
      body: map['body'] as String? ?? '',
      type: NotificationType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => NotificationType.debtReminder,
      ),
      targetDebtId: map['targetDebtId'] as String?,
      targetSessionId: map['targetSessionId'] as String?,
      isRead: map['isRead'] as bool? ?? false,
      createdAt: _parseDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'type': type.name,
      if (targetDebtId != null) 'targetDebtId': targetDebtId,
      if (targetSessionId != null) 'targetSessionId': targetSessionId,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}
