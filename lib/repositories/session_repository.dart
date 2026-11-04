import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/firebase_providers.dart';
import '../models/expense.dart';
import '../models/session.dart';
import '../models/session_member.dart';

class ExpenseInput {
  final String expenseId;
  final String description;
  final int amount;
  final String payerId;
  final List<String> participantIds;

  const ExpenseInput({
    required this.expenseId,
    required this.description,
    required this.amount,
    required this.payerId,
    required this.participantIds,
  });

  Map<String, dynamic> toMap() => {
    'description': description.trim(),
    'amount': amount,
    'payerId': payerId,
    'participantIds': participantIds,
  };
}

class SessionRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  SessionRepository(this._db, [FirebaseFunctions? functions])
    : _functions = functions ?? FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('sessions');

  /// Creates a session, its members, and expense items atomically via callable.
  Future<String> createSessionWithExpenses({
    required Session session,
    required List<SessionMember> members,
    required List<ExpenseInput> expenses,
  }) async {
    final result = await _functions
        .httpsCallable('createSessionWithExpenses')
        .call({
          'sessionId': session.sessionId,
          'creatorId': session.creatorId,
          'session': session.toMap(),
          'members': [
            for (final member in members)
              {'memberId': member.memberId, ...member.toMap()},
          ],
          'expenses': expenses.map((expense) => expense.toMap()).toList(),
        });
    return result.data['sessionId'] as String;
  }

  /// Tạo phiên legacy không có expense-item, cùng members trong batch.
  Future<String> createSession(
    Session session,
    List<SessionMember> members,
  ) async {
    final batch = _db.batch();
    final sessionRef = _sessions.doc(session.sessionId);
    batch.set(sessionRef, session.toMap());
    for (final m in members) {
      batch.set(sessionRef.collection('members').doc(m.memberId), m.toMap());
    }
    await batch.commit();
    return session.sessionId;
  }

  /// Adds a validated expense through the trusted mutation callable.
  Future<String> addExpense({
    required String sessionId,
    required ExpenseInput expense,
  }) async {
    await _functions.httpsCallable('mutateExpense').call({
      'sessionId': sessionId,
      'expenseId': expense.expenseId,
      'operation': 'add',
      'expense': expense.toMap(),
    });
    return expense.expenseId;
  }

  /// Updates a validated expense through the trusted mutation callable.
  Future<void> updateExpense({
    required String sessionId,
    required String expenseId,
    required ExpenseInput expense,
  }) async {
    await _functions.httpsCallable('mutateExpense').call({
      'sessionId': sessionId,
      'expenseId': expenseId,
      'operation': 'update',
      'expense': expense.toMap(),
    });
  }

  /// Deletes an expense through the trusted mutation callable.
  Future<void> deleteExpense({
    required String sessionId,
    required String expenseId,
  }) async {
    await _functions.httpsCallable('mutateExpense').call({
      'sessionId': sessionId,
      'expenseId': expenseId,
      'operation': 'delete',
    });
  }

  /// Adds validated expense items through the trusted mutation callable.
  Future<void> addExpenses({
    required String sessionId,
    required List<ExpenseInput> expenses,
  }) async {
    if (expenses.isEmpty) {
      throw ArgumentError('At least one expense is required');
    }
    for (final expense in expenses) {
      await _functions.httpsCallable('mutateExpense').call({
        'sessionId': sessionId,
        'expenseId': expense.expenseId,
        'operation': 'add',
        'expense': expense.toMap(),
      });
    }
  }

  static List<Expense> sortExpensesBySequence(List<Expense> expenses) {
    final sorted = [...expenses];
    sorted.sort((a, b) => a.sequence.compareTo(b.sequence));
    return sorted;
  }

  Stream<List<Expense>> watchSessionExpenses(String sessionId) {
    return _sessions.doc(sessionId).collection('expenses').snapshots().map((
      snapshot,
    ) {
      return sortExpensesBySequence(
        snapshot.docs
            .map((doc) => Expense.fromMap(doc.id, doc.data()))
            .toList(),
      );
    });
  }

  /// Stream phiên của [uid], mới nhất trước.
  Stream<List<Session>> watchUserSessions(String uid) {
    return _sessions.where('memberUserIds', arrayContains: uid).snapshots().map(
      (s) {
        final sessions = s.docs
            .map((d) => Session.fromMap(d.id, d.data()))
            .toList();
        sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return sessions;
      },
    );
  }

  /// Stream danh sách thành viên của [sessionId].
  Stream<List<SessionMember>> watchSessionMembers(String sessionId) {
    return _sessions
        .doc(sessionId)
        .collection('members')
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => SessionMember.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Đóng phiên thông qua Cloud Function tin cậy; client không tự ghi debt.
  Future<void> closeSession({
    required String sessionId,
    required String creatorId,
    required List<SessionMember> members,
  }) async {
    await _functions.httpsCallable('closeSession').call({
      'sessionId': sessionId,
    });
  }

  /// Xoá phiên (xoá sub-collection members và document session).
  Future<void> deleteSession(String sessionId) async {
    final membersSnap = await _sessions
        .doc(sessionId)
        .collection('members')
        .get();
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

final userSessionsProvider = StreamProvider.family<List<Session>, String>((
  ref,
  uid,
) {
  return ref.watch(sessionRepositoryProvider).watchUserSessions(uid);
});

final sessionExpensesProvider = StreamProvider.family<List<Expense>, String>((
  ref,
  sessionId,
) {
  return ref.watch(sessionRepositoryProvider).watchSessionExpenses(sessionId);
});

final sessionMembersProvider =
    StreamProvider.family<List<SessionMember>, String>((ref, sessionId) {
      return ref
          .watch(sessionRepositoryProvider)
          .watchSessionMembers(sessionId);
    });

/// Singleton UUID generator.
const _uuid = Uuid();
String newUuid() => _uuid.v4();
