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
