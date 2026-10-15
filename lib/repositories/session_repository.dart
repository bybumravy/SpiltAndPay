import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/firebase_providers.dart';
import '../models/debt.dart';
import '../models/session.dart';
import '../models/session_member.dart';

class SessionRepository {
  final FirebaseFirestore _db;
  SessionRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('sessions');

  /// Tạo phiên mới + members trong sub-collection (batch write).
  Future<String> createSession(
    Session session,
    List<SessionMember> members,
  ) async {
    final batch = _db.batch();
    final sessionRef = _sessions.doc(session.sessionId);
    batch.set(sessionRef, session.toMap());
    for (final m in members) {
      batch.set(
        sessionRef.collection('members').doc(m.memberId),
        m.toMap(),
      );
    }
    await batch.commit();
    return session.sessionId;
  }

  /// Stream phiên của [uid], mới nhất trước.
  Stream<List<Session>> watchUserSessions(String uid) {
    return _sessions
        .where('memberUserIds', arrayContains: uid)
        .snapshots()
        .map((s) {
      final sessions = s.docs
          .map((d) => Session.fromMap(d.id, d.data()))
          .toList();
      sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sessions;
    });
  }

  /// Stream danh sách thành viên của [sessionId].
  Stream<List<SessionMember>> watchSessionMembers(String sessionId) {
    return _sessions
        .doc(sessionId)
        .collection('members')
        .snapshots()
        .map((s) => s.docs
            .map((d) => SessionMember.fromMap(d.id, d.data()))
            .toList());
  }

  /// Creator đánh dấu guest đã trả tiền mặt.
  Future<void> markGuestPaid({
    required String sessionId,
    required String memberId,
  }) {
    return _sessions
        .doc(sessionId)
        .collection('members')
        .doc(memberId)
        .update({'status': MemberStatus.paid.name});
  }

  /// Đóng phiên: ghi nợ tích lũy + cập nhật status trong một transaction.
  Future<void> closeSession({
    required String sessionId,
    required String creatorId,
    required List<SessionMember> members,
  }) async {
    await _db.runTransaction((tx) async {
      // Cập nhật phiên → closed.
      final sessionRef = _sessions.doc(sessionId);
      tx.update(sessionRef, {
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
      });

      for (final m in members) {
        final memberRef =
            sessionRef.collection('members').doc(m.memberId);

        if (m.isGuest || m.userId == null || m.userId == creatorId) {
          // Guest hoặc chính creator — chỉ đổi status, không ghi debt.
          tx.update(memberRef, {'status': MemberStatus.paid.name});
          continue;
        }

        // App member — ghi nợ tích lũy.
        final memberUid = m.userId!;
        final debtId = Debt.docId(creatorId, memberUid);
        final debtRef = _db.collection('debts').doc(debtId);

        // Delta: dương trong balance có nghĩa userA nợ userB.
        // Ta muốn ghi: memberUid nợ creatorId.
        final delta = memberUid.compareTo(creatorId) < 0
            ? m.amountOwed   // member = userA, creator = userB → balance += δ
            : -m.amountOwed; // member = userB, creator = userA → balance -= δ

        tx.set(
          debtRef,
          {
            'userA': [creatorId, memberUid]..sort()
              ..first, // userA = sorted[0]
            'userB': [creatorId, memberUid]..sort()
              ..last,
            'participants': [creatorId, memberUid],
            'balance': FieldValue.increment(delta),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        tx.update(memberRef, {'status': MemberStatus.ledger.name});
      }
    });
  }

  /// Xoá phiên (xoá sub-collection members và document session).
  Future<void> deleteSession(String sessionId) async {
    final membersSnap =
        await _sessions.doc(sessionId).collection('members').get();
    final batch = _db.batch();
    for (final doc in membersSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_sessions.doc(sessionId));
    await batch.commit();
  }

  /// Cập nhật tên phiên (chỉ creator).
  Future<void> updateSessionTitle({
    required String sessionId,
    required String newTitle,
  }) async {
    await _sessions.doc(sessionId).update({'title': newTitle});
  }
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(ref.watch(firestoreProvider));
});

final userSessionsProvider =
    StreamProvider.family<List<Session>, String>((ref, uid) {
  return ref.watch(sessionRepositoryProvider).watchUserSessions(uid);
});

final sessionMembersProvider =
    StreamProvider.family<List<SessionMember>, String>((ref, sessionId) {
  return ref.watch(sessionRepositoryProvider).watchSessionMembers(sessionId);
});

/// Singleton UUID generator.
const _uuid = Uuid();
String newUuid() => _uuid.v4();
