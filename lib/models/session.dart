import 'package:cloud_firestore/cloud_firestore.dart';

/// Trạng thái của một phiên chia tiền.
enum SessionStatus { open, closed }

/// Model phiên chia tiền.
class Session {
  final String sessionId;
  final String creatorId;
  final String title;

  /// Tổng tiền (VND, đơn vị đồng).
  final int totalAmount;

  final SessionSplitMode splitMode;
  final SessionStatus status;

  /// Danh sách uid của các thành viên có app (phục vụ query array-contains).
  final List<String> memberUserIds;

  final DateTime createdAt;
  final DateTime? closedAt;

  const Session({
    required this.sessionId,
    required this.creatorId,
    required this.title,
    required this.totalAmount,
    required this.splitMode,
    required this.status,
    required this.memberUserIds,
    required this.createdAt,
    this.closedAt,
  });

  factory Session.fromMap(String id, Map<String, dynamic> map) {
    return Session(
      sessionId: id,
      creatorId: map['creatorId'] as String,
      title: map['title'] as String? ?? '',
      totalAmount: (map['totalAmount'] as num).toInt(),
      splitMode: (map['splitMode'] as String?) == 'custom'
          ? SessionSplitMode.custom
          : SessionSplitMode.equal,
      status: (map['status'] as String?) == 'closed'
          ? SessionStatus.closed
          : SessionStatus.open,
      memberUserIds: List<String>.from(map['memberUserIds'] as List? ?? []),
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      closedAt: map['closedAt'] is Timestamp
          ? (map['closedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'creatorId': creatorId,
      'title': title,
      'totalAmount': totalAmount,
      'splitMode': splitMode.name,
      'status': status.name,
      'memberUserIds': memberUserIds,
      'createdAt': Timestamp.fromDate(createdAt),
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
    };
  }
}

enum SessionSplitMode { equal, custom }
