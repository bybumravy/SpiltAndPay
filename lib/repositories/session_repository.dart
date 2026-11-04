import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/firebase_providers.dart';
import '../core/expense_allocation.dart';
import '../core/session_close_accounting.dart';
import '../core/session_edit.dart';
import '../models/debt.dart';
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
  final FirebaseAuth _auth;

  SessionRepository(this._db, [FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  String get _currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Bạn cần đăng nhập để thực hiện thao tác này.');
    }
    return uid;
  }

  Map<String, int> _allocate(ExpenseInput input) => allocateExpenseShares(
    amount: input.amount,
    participantIds: input.participantIds,
  );

  List<SessionMember> _membersFromDocuments(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> documents,
  ) => [
    for (final doc in documents)
      if (doc.exists) SessionMember.fromMap(doc.id, doc.data()!),
  ];

  List<Expense> _expensesFromDocuments(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> documents,
  ) => [
    for (final doc in documents)
      if (doc.exists) Expense.fromMap(doc.id, doc.data()!),
  ];

  /// Query results identify candidate paths only. Read their current values via
  /// the transaction; every session mutation writes the parent session, so its
  /// transactional read detects concurrent mutations that add/remove children.
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _readQueryInTransaction({
    required Transaction transaction,
    required Query<Map<String, dynamic>> query,
  }) async {
    final discovered = await query.get();
    final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final document in discovered.docs) {
      snapshots.add(await transaction.get(document.reference));
    }
    return snapshots.where((snapshot) => snapshot.exists).toList();
  }

  Query<Map<String, dynamic>> _membersQuery(String sessionId) =>
      _sessions.doc(sessionId).collection('members');

  Query<Map<String, dynamic>> _expensesQuery(String sessionId) =>
      _sessions.doc(sessionId).collection('expenses');

  void _validateExpense(
    ExpenseInput input,
    Map<String, SessionMember> membersById,
  ) {
    if (input.description.trim().isEmpty) {
      throw ArgumentError('Mô tả khoản chi không được để trống.');
    }
    _allocate(input);
    final payer = membersById[input.payerId];
    if (payer == null || payer.isGuest || payer.userId == null) {
      throw ArgumentError('Người trả phải là thành viên có tài khoản.');
    }
    if (input.participantIds.any((id) => !membersById.containsKey(id))) {
      throw ArgumentError('Người tham gia phải thuộc phiên hiện tại.');
    }
  }

  Expense _expenseFromInput(ExpenseInput input, {required int sequence}) {
    return Expense(
      expenseId: input.expenseId,
      description: input.description.trim(),
      amount: input.amount,
      payerId: input.payerId,
      participantIds: List.unmodifiable(input.participantIds),
      shares: _allocate(input),
      sequence: sequence,
    );
  }

  void _assertCreatorOpen(Map<String, dynamic>? data, String actorUid) {
    if (data == null) throw StateError('Không tìm thấy phiên.');
    if (data['creatorId'] != actorUid) {
      throw StateError('Chỉ người tạo phiên được thao tác.');
    }
    if (data['status'] != SessionStatus.open.name) {
      throw StateError('Chỉ phiên đang mở mới được sửa hoặc chốt.');
    }
  }

  void _ensureBatchWithinFirestoreLimit(int writes) {
    if (writes > 500) {
      throw ArgumentError('Phiên có quá nhiều bản ghi để chốt trong một lần.');
    }
  }

  Future<void> _commitCloseResult({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> sessionRef,
    required List<DocumentSnapshot<Map<String, dynamic>>> memberSnapshots,
    required SessionCloseResult result,
    required String sessionId,
    required String creatorId,
  }) async {
    final debtIds = <String, Debt>{};
    for (final transfer in result.transfers) {
      final debtId = Debt.docId(transfer.from, transfer.to);
      if (!debtIds.containsKey(debtId)) {
        final parts = [transfer.from, transfer.to]..sort();
        debtIds[debtId] = Debt(
          userA: parts[0],
          userB: parts[1],
          balance: 0,
          updatedAt: DateTime.now(),
        );
      }
    }
    final debtRefs = {
      for (final id in debtIds.keys) id: _db.collection('debts').doc(id),
    };
    for (final obligation in result.guestObligations) {
      final obligationRef = sessionRef
          .collection('guestObligations')
          .doc(obligation.obligationId);
      transaction.set(
        obligationRef,
        GuestObligation(
          obligationId: obligation.obligationId,
          sessionId: sessionId,
          expenseId: obligation.expenseId,
          payerId: obligation.payerId,
          guestMemberId: obligation.guestMemberId,
          amount: obligation.amount,
          createdAt: DateTime.now(),
        ).toMap(),
      );
    }

    for (final transfer in result.transfers) {
      final debtId = Debt.docId(transfer.from, transfer.to);
      final debtRef = debtRefs[debtId]!;
      final debt = debtIds[debtId]!;
      final delta = Debt.balanceDelta(
        debtorUid: transfer.from,
        creditorUid: transfer.to,
        amount: transfer.amount,
      );
      transaction.set(
        debtRef.collection('entries').doc(sessionId),
        DebtEntry(
          sessionId: sessionId,
          fromUserId: transfer.from,
          toUserId: transfer.to,
          amount: transfer.amount,
          createdAt: DateTime.now(),
        ).toMap(),
      );
      transaction.set(debtRef, {
        ...debt.toMap(),
        'balance': FieldValue.increment(delta),
        'lastEntryId': sessionId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    for (final memberDoc in memberSnapshots) {
      final data = memberDoc.data()!;
      final member = SessionMember.fromMap(memberDoc.id, data);
      if (member.isGuest || member.userId == null) continue;
      final amounts = result.memberAmounts[member.memberId];
      transaction.update(memberDoc.reference, {
        'amountOwed': amounts?.owed ?? member.amountOwed,
        'amountPaid': amounts?.paid ?? member.amountPaid,
        'status': member.userId == creatorId
            ? MemberStatus.paid.name
            : MemberStatus.ledger.name,
      });
    }
    transaction.update(sessionRef, {
      'status': SessionStatus.closed.name,
      'closedAt': FieldValue.serverTimestamp(),
      'totalAmount': result.totalAmount,
      'closeResult': {
        'totalAmount': result.totalAmount,
        'transfers': [
          for (final t in result.transfers)
            {'from': t.from, 'to': t.to, 'amount': t.amount},
        ],
        'guestObligationIds': result.guestObligations
            .map((o) => o.obligationId)
            .toList(),
      },
    });
  }

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('sessions');

  /// Creates a session, its members, and its expense items atomically.
  Future<String> createSessionWithExpenses({
    required Session session,
    required List<SessionMember> members,
    required List<ExpenseInput> expenses,
  }) async {
    final uid = _currentUid;
    if (session.creatorId != uid) {
      throw StateError('Creator must match the signed-in user.');
    }
    if (expenses.isEmpty) {
      throw ArgumentError('At least one expense is required.');
    }
    _ensureBatchWithinFirestoreLimit(1 + members.length + expenses.length);
    final byId = {for (final member in members) member.memberId: member};
    if (byId.length != members.length ||
        !byId.values.any((m) => m.userId == uid && !m.isGuest)) {
      throw ArgumentError(
        'Session members must be unique and include the creator.',
      );
    }
    for (final expense in expenses) {
      _validateExpense(expense, byId);
    }
    final previews = [
      for (var i = 0; i < expenses.length; i++)
        _expenseFromInput(expenses[i], sequence: i),
    ];
    final total = previews.fold<int>(
      0,
      (subtotal, expense) => subtotal + expense.amount,
    );
    if (total <= 0) throw ArgumentError('Session total must be positive.');
    final accounting = calculateSessionClose(
      creatorId: uid,
      members: members,
      expenses: [
        for (final e in previews)
          CloseExpense(
            expenseId: e.expenseId,
            amount: e.amount,
            payerId: e.payerId,
            participantIds: e.participantIds,
          ),
      ],
    );
    final sessionRef = _sessions.doc(session.sessionId);
    final batch = _db.batch();
    batch.set(sessionRef, {...session.toMap(), 'totalAmount': total});
    for (final member in members) {
      final amounts = accounting.memberAmounts[member.memberId]!;
      batch.set(sessionRef.collection('members').doc(member.memberId), {
        ...member.toMap(),
        'amountOwed': amounts.owed,
        'amountPaid': amounts.paid,
      });
    }
    for (final expense in previews) {
      batch.set(
        sessionRef.collection('expenses').doc(expense.expenseId),
        expense.toMap(),
      );
    }
    await batch.commit();
    return session.sessionId;
  }

  /// Replace the open draft atomically. Reject stale editors and closed sessions.
  Future<void> saveOpenSession({
    required Session originalSession,
    required List<SessionMember> originalMembers,
    required List<Expense> originalExpenses,
    required String title,
    required List<SessionMember> members,
    required List<ExpenseInput> expenses,
  }) async {
    final uid = _currentUid;
    final items = [
      for (var i = 0; i < expenses.length; i++)
        _expenseFromInput(expenses[i], sequence: i),
    ];
    final accounting = validateSessionEdit(
      title: title,
      creatorId: uid,
      members: members,
      expenses: items,
    );
    final expected = sessionEditFingerprint(
      originalSession,
      originalMembers,
      originalExpenses,
    );
    final sessionRef = _sessions.doc(originalSession.sessionId);
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(sessionRef);
      _assertCreatorOpen(snapshot.data(), uid);
      final oldMembers = await _readQueryInTransaction(
        transaction: tx,
        query: _membersQuery(originalSession.sessionId),
      );
      final oldExpenses = await _readQueryInTransaction(
        transaction: tx,
        query: _expensesQuery(originalSession.sessionId),
      );
      final actual = sessionEditFingerprint(
        Session.fromMap(snapshot.id, snapshot.data()!),
        _membersFromDocuments(oldMembers),
        _expensesFromDocuments(oldExpenses),
      );
      if (actual != expected) {
        throw StateError(
          'Phiên đã được thay đổi ở nơi khác. Hãy quay lại và mở lại màn sửa.',
        );
      }
      final memberIds = members.map((m) => m.memberId).toSet();
      final expenseIds = items.map((e) => e.expenseId).toSet();
      final removedMembers = oldMembers.where((d) => !memberIds.contains(d.id));
      final removedExpenses = oldExpenses.where(
        (d) => !expenseIds.contains(d.id),
      );
      _ensureBatchWithinFirestoreLimit(
        1 +
            members.length +
            items.length +
            removedMembers.length +
            removedExpenses.length,
      );
      for (final doc in removedMembers) {
        tx.delete(doc.reference);
      }
      for (final doc in removedExpenses) {
        tx.delete(doc.reference);
      }
      for (final member in members) {
        final amounts = accounting.memberAmounts[member.memberId]!;
        tx.set(sessionRef.collection('members').doc(member.memberId), {
          ...member.toMap(),
          'displayName': member.displayName.trim(),
          'amountOwed': amounts.owed,
          'amountPaid': amounts.paid,
          'status': member.isGuest
              ? MemberStatus.pending.name
              : member.userId == uid
              ? MemberStatus.self.name
              : MemberStatus.ledger.name,
        });
      }
      for (final item in items) {
        tx.set(sessionRef.collection('expenses').doc(item.expenseId), {
          ...item.toMap(),
          if (originalExpenses.any(
            (e) => e.expenseId == item.expenseId && e.createdAt != null,
          ))
            'createdAt': Timestamp.fromDate(
              originalExpenses
                  .firstWhere((e) => e.expenseId == item.expenseId)
                  .createdAt!,
            ),
        });
      }
      tx.update(sessionRef, {
        'title': title.trim(),
        'totalAmount': accounting.totalAmount,
        'memberUserIds': members
            .where((m) => !m.isGuest)
            .map((m) => m.userId!)
            .toList(),
        'splitMode': SessionSplitMode.equal.name,
        'lastExpenseMutationId': newUuid(),
      });
    });
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

  /// All item mutations update member previews and the parent together.
  Future<void> _mutateOpenExpenses(
    String sessionId,
    List<Expense> Function(List<Expense>) mutate,
  ) async {
    final uid = _currentUid;
    final parent = _sessions.doc(sessionId);
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(parent);
      _assertCreatorOpen(snapshot.data(), uid);
      final memberDocs = await _readQueryInTransaction(
        transaction: tx,
        query: _membersQuery(sessionId),
      );
      final expenseDocs = await _readQueryInTransaction(
        transaction: tx,
        query: _expensesQuery(sessionId),
      );
      final members = _membersFromDocuments(memberDocs);
      final current = sortExpensesBySequence(
        _expensesFromDocuments(expenseDocs),
      );
      if (current.isEmpty) {
        throw StateError(
          'Phiên cũ cần mở Chỉnh sửa toàn bộ phiên để chuyển sang khoản chi trước.',
        );
      }
      final next = mutate(current);
      if (next.isEmpty) throw StateError('Không thể xóa khoản chi cuối cùng.');
      final ids = <String>{};
      final byMember = {for (final m in members) m.memberId: m};
      for (final e in next) {
        if (!ids.add(e.expenseId)) {
          throw ArgumentError('Expense IDs must be unique.');
        }
        _validateExpense(
          ExpenseInput(
            expenseId: e.expenseId,
            description: e.description,
            amount: e.amount,
            payerId: e.payerId,
            participantIds: e.participantIds,
          ),
          byMember,
        );
      }
      final accounting = calculateSessionClose(
        creatorId: uid,
        members: members,
        expenses: [
          for (final e in next)
            CloseExpense(
              expenseId: e.expenseId,
              amount: e.amount,
              payerId: e.payerId,
              participantIds: e.participantIds,
            ),
        ],
      );
      final removed = expenseDocs.where((d) => !ids.contains(d.id));
      _ensureBatchWithinFirestoreLimit(
        1 + memberDocs.length + next.length + removed.length,
      );
      for (final doc in removed) {
        tx.delete(doc.reference);
      }
      for (var i = 0; i < next.length; i++) {
        final e = next[i];
        tx.set(parent.collection('expenses').doc(e.expenseId), {
          ...e.toMap(),
          'sequence': i,
          'shares': allocateExpenseShares(
            amount: e.amount,
            participantIds: e.participantIds,
          ),
        });
      }
      for (final doc in memberDocs) {
        final amounts = accounting.memberAmounts[doc.id]!;
        tx.update(doc.reference, {
          'amountOwed': amounts.owed,
          'amountPaid': amounts.paid,
        });
      }
      tx.update(parent, {
        'totalAmount': accounting.totalAmount,
        'lastExpenseMutationId': newUuid(),
      });
    });
  }

  Future<String> addExpense({
    required String sessionId,
    required ExpenseInput expense,
  }) async {
    await addExpenses(sessionId: sessionId, expenses: [expense]);
    return expense.expenseId;
  }

  Future<void> updateExpense({
    required String sessionId,
    required String expenseId,
    required ExpenseInput expense,
  }) => _mutateOpenExpenses(sessionId, (current) {
    final index = current.indexWhere((e) => e.expenseId == expenseId);
    if (index < 0) throw StateError('Không tìm thấy khoản chi.');
    if (expense.expenseId != expenseId) {
      throw ArgumentError('Không được đổi mã khoản chi.');
    }
    final before = current[index];
    final updated = _expenseFromInput(expense, sequence: before.sequence);
    current[index] = Expense(
      expenseId: updated.expenseId,
      description: updated.description,
      amount: updated.amount,
      payerId: updated.payerId,
      participantIds: updated.participantIds,
      shares: updated.shares,
      sequence: before.sequence,
      createdAt: before.createdAt,
    );
    return current;
  });

  Future<void> deleteExpense({
    required String sessionId,
    required String expenseId,
  }) => _mutateOpenExpenses(sessionId, (current) {
    if (!current.any((e) => e.expenseId == expenseId)) {
      throw StateError('Không tìm thấy khoản chi.');
    }
    return current.where((e) => e.expenseId != expenseId).toList();
  });

  Future<void> addExpenses({
    required String sessionId,
    required List<ExpenseInput> expenses,
  }) {
    if (expenses.isEmpty) {
      throw ArgumentError('At least one expense is required.');
    }
    return _mutateOpenExpenses(
      sessionId,
      (current) => [
        ...current,
        for (var i = 0; i < expenses.length; i++)
          _expenseFromInput(expenses[i], sequence: current.length + i),
      ],
    );
  }

  static List<Expense> sortExpensesBySequence(List<Expense> expenses) {
    final sorted = [...expenses];
    sorted.sort((a, b) => a.sequence.compareTo(b.sequence));
    return sorted;
  }

  /// Stream các khoản chi của [sessionId], sắp xếp theo sequence.
  /// Bổ sung cơ chế auto-retry khi gặp độ trễ đồng bộ Auth token (permission-denied thoáng qua).
  Stream<List<Expense>> watchSessionExpenses(String sessionId) async* {
    var retryCount = 0;
    while (true) {
      try {
        await for (final snapshot
            in _sessions.doc(sessionId).collection('expenses').snapshots()) {
          retryCount = 0;
          yield sortExpensesBySequence(
            snapshot.docs
                .map((doc) => Expense.fromMap(doc.id, doc.data()))
                .toList(),
          );
        }
        break;
      } catch (e) {
        if (e.toString().toLowerCase().contains('permission-denied') &&
            retryCount < 4) {
          retryCount++;
          debugPrint(
            'watchSessionExpenses: transient permission-denied, retrying ($retryCount/4)...',
          );
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Stream phiên của [uid], mới nhất trước.
  /// Bổ sung cơ chế auto-retry khi gặp độ trễ đồng bộ Auth token (permission-denied thoáng qua).
  Stream<List<Session>> watchUserSessions(String uid) async* {
    var retryCount = 0;
    while (true) {
      try {
        await for (final s
            in _sessions
                .where('memberUserIds', arrayContains: uid)
                .snapshots()) {
          retryCount = 0;
          final sessions = s.docs
              .map((d) => Session.fromMap(d.id, d.data()))
              .toList();
          sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          yield sessions;
        }
        break;
      } catch (e) {
        if (e.toString().toLowerCase().contains('permission-denied') &&
            retryCount < 4) {
          retryCount++;
          debugPrint(
            'watchUserSessions: transient permission-denied, retrying ($retryCount/4)...',
          );
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Stream danh sách thành viên của [sessionId].
  /// Bổ sung cơ chế auto-retry khi gặp độ trễ đồng bộ Auth token (permission-denied thoáng qua).
  Stream<List<SessionMember>> watchSessionMembers(String sessionId) async* {
    var retryCount = 0;
    while (true) {
      try {
        await for (final s
            in _sessions.doc(sessionId).collection('members').snapshots()) {
          retryCount = 0;
          yield s.docs
              .map((d) => SessionMember.fromMap(d.id, d.data()))
              .toList();
        }
        break;
      } catch (e) {
        if (e.toString().toLowerCase().contains('permission-denied') &&
            retryCount < 4) {
          retryCount++;
          debugPrint(
            'watchSessionMembers: transient permission-denied, retrying ($retryCount/4)...',
          );
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Computes and writes the close result from client-side accounting.
  /// This is trusted-client behavior for the Firebase Spark plan, not a
  /// server-authoritative settlement boundary.
  Future<void> closeSession({
    required String sessionId,
    required String creatorId,
    required List<SessionMember> members,
  }) async {
    final uid = _currentUid;
    if (uid != creatorId) throw StateError('Chỉ người tạo phiên được chốt.');
    final sessionRef = _sessions.doc(sessionId);
    await _db.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      final sessionData = sessionSnapshot.data();
      _assertCreatorOpen(sessionData, uid);
      final memberDocuments = await _readQueryInTransaction(
        transaction: transaction,
        query: _membersQuery(sessionId),
      );
      final expenseDocuments = await _readQueryInTransaction(
        transaction: transaction,
        query: _expensesQuery(sessionId),
      );
      final sessionMembers = _membersFromDocuments(memberDocuments);
      final expenses = _expensesFromDocuments(expenseDocuments).map((expense) {
        return CloseExpense(
          expenseId: expense.expenseId,
          amount: expense.amount,
          payerId: expense.payerId,
          participantIds: expense.participantIds,
        );
      }).toList();
      final result = calculateSessionClose(
        expenses: expenses,
        members: sessionMembers,
        creatorId: creatorId,
        expectedTotal: (sessionData!['totalAmount'] as num).toInt(),
      );
      final writeCount =
          result.guestObligations.length +
          result.transfers.length * 2 +
          sessionMembers
              .where((member) => !member.isGuest && member.userId != null)
              .length +
          1;
      _ensureBatchWithinFirestoreLimit(writeCount);
      await _commitCloseResult(
        transaction: transaction,
        sessionRef: sessionRef,
        memberSnapshots: memberDocuments,
        result: result,
        sessionId: sessionId,
        creatorId: creatorId,
      );
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
