import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/firebase_providers.dart';
import '../core/settlement.dart';
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
      final sessionRef = _sessions.doc(sessionId);

      // Chặn đóng 2 lần (sẽ ghi nợ trùng).
      final snap = await tx.get(sessionRef);
      final sessionData = snap.data();
      if (sessionData?['status'] == 'closed') {
        throw StateError('Phiên đã được đóng trước đó.');
      }

      // Tổng phần phải trả của mọi thành viên phải khớp tổng bill đã lưu,
      // nếu không thì dữ liệu phiên bị sai → không ghi nợ.
      final totalAmount = (sessionData?['totalAmount'] as num?)?.toInt();
      final totalOwed = members.fold<int>(0, (s, m) => s + m.amountOwed);
      if (totalAmount != null && totalOwed != totalAmount) {
        throw StateError(
            'Tổng phần chia ($totalOwed) không khớp tổng bill ($totalAmount).');
      }

      tx.update(sessionRef, {
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
      });

      // Ghi nợ theo danh sách chuyển tiền ít nhất giữa các thành viên.
      // Mỗi khoản gồm 1 bản ghi bất biến (entries) + cộng dồn vào balance;
      // rules bắt buộc balance đổi đúng bằng số tiền của entry.
      for (final t in settleSession(creatorId: creatorId, members: members)) {
        final sorted = [t.from, t.to]..sort();
        final debtRef = _db.collection('debts').doc(Debt.docId(t.from, t.to));
        tx.set(debtRef.collection('entries').doc(sessionId), {
          'sessionId': sessionId,
          'fromUserId': t.from, // con nợ
          'toUserId': t.to, // chủ nợ
          'amount': t.amount,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          debtRef,
          {
            'userA': sorted[0],
            'userB': sorted[1],
            'participants': sorted,
            'balance': FieldValue.increment(Debt.balanceDelta(
              debtorUid: t.from,
              creditorUid: t.to,
              amount: t.amount,
            )),
            'lastEntryId': sessionId,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      for (final m in members) {
        final memberRef = sessionRef.collection('members').doc(m.memberId);
        if (m.isGuest) continue; // guest giữ nguyên pending, creator tự đánh dấu đã thu
        tx.update(
          memberRef,
          {
            'status': (m.userId == null || m.userId == creatorId)
                ? MemberStatus.paid.name
                : MemberStatus.ledger.name,
          },
        );
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
