import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/models/session.dart';

void main() {
  group('Session Model & Sorting Tests', () {
    test('Session.fromMap parses valid timestamp correctly', () {
      final now = DateTime(2026, 10, 14, 12, 0);
      final map = {
        'creatorId': 'user_1',
        'title': 'Tiền ăn trưa',
        'totalAmount': 150000,
        'splitMode': 'equal',
        'status': 'open',
        'memberUserIds': ['user_1', 'user_2'],
        'createdAt': Timestamp.fromDate(now),
      };

      final session = Session.fromMap('session_1', map);

      expect(session.sessionId, 'session_1');
      expect(session.creatorId, 'user_1');
      expect(session.title, 'Tiền ăn trưa');
      expect(session.totalAmount, 150000);
      expect(session.splitMode, SessionSplitMode.equal);
      expect(session.status, SessionStatus.open);
      expect(session.memberUserIds, ['user_1', 'user_2']);
      expect(session.createdAt, now);
      expect(session.closedAt, isNull);
    });

    test('Session.fromMap falls back gracefully when createdAt is null', () {
      final map = {
        'creatorId': 'user_1',
        'title': 'Test không có timestamp',
        'totalAmount': 50000,
        'splitMode': 'custom',
        'status': 'closed',
        'memberUserIds': ['user_1'],
        'createdAt': null,
      };

      final session = Session.fromMap('session_2', map);

      expect(session.sessionId, 'session_2');
      expect(session.createdAt, isA<DateTime>());
      expect(session.splitMode, SessionSplitMode.custom);
      expect(session.status, SessionStatus.closed);
    });

    test('In-memory sorting orders sessions newest first', () {
      final t1 = DateTime(2026, 10, 10);
      final t2 = DateTime(2026, 10, 12);
      final t3 = DateTime(2026, 10, 14);

      final s1 = Session(
        sessionId: 's1',
        creatorId: 'u1',
        title: 'Phiên 1',
        totalAmount: 100,
        splitMode: SessionSplitMode.equal,
        status: SessionStatus.open,
        memberUserIds: ['u1'],
        createdAt: t1,
      );

      final s2 = Session(
        sessionId: 's2',
        creatorId: 'u1',
        title: 'Phiên 2',
        totalAmount: 200,
        splitMode: SessionSplitMode.equal,
        status: SessionStatus.open,
        memberUserIds: ['u1'],
        createdAt: t2,
      );

      final s3 = Session(
        sessionId: 's3',
        creatorId: 'u1',
        title: 'Phiên 3',
        totalAmount: 300,
        splitMode: SessionSplitMode.equal,
        status: SessionStatus.open,
        memberUserIds: ['u1'],
        createdAt: t3,
      );

      final sessions = [s1, s3, s2];
      sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      expect(sessions.map((s) => s.sessionId).toList(), ['s3', 's2', 's1']);
    });
  });
}
