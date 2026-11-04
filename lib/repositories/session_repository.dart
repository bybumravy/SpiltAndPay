import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/firebase_providers.dart';
import '../core/expense_allocation.dart';
import '../core/session_close_accounting.dart';
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
    if (uid == null) throw StateError('Bạn cần đăng nhập để thực hiện thao tác này.');
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

  void _assertCreatorOpen(
    Map<String, dynamic>? data,
    String actorUid,
  ) {
    if (data == null) throw StateError('Không tìm thấy phiên.');
    if (data['creatorId'] != actorUid) throw StateError('Chỉ người tạo phiên được thao tác.');
    if (data['status'] != SessionStatus.open.name) {
      throw StateError('Chỉ phiên đang mở mới được sửa hoặc chốt.');
    }
  }

  void _ensureBatchWithinFirestoreLimit(int writes) {
    if (writes > 500) throw ArgumentError('Phiên có quá nhiều bản ghi để chốt trong một lần.');
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
          userA: parts[0], userB: parts[1], balance: 0, updatedAt: DateTime.now(),
        );
      }
    }
    final debtRefs = {
      for (final id in debtIds.keys) id: _db.collection('debts').doc(id),
    };
    final debtSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final entry in debtRefs.entries) {
      debtSnapshots[entry.key] = await transaction.get(entry.value);
    }

    for (final obligation in result.guestObligations) {
      final obligationRef = sessionRef.collection('guestObligations').doc(obligation.obligationId);
      transaction.set(obligationRef, GuestObligation(
        obligationId: obligation.obligationId,
        sessionId: sessionId,
        expenseId: obligation.expenseId,
        payerId: obligation.payerId,
        guestMemberId: obligation.guestMemberId,
        amount: obligation.amount,
        createdAt: DateTime.now(),
      ).toMap());
    }

    for (final transfer in result.transfers) {
      final debtId = Debt.docId(transfer.from, transfer.to);
      final debtRef = debtRefs[debtId]!;
      final existing = debtSnapshots[debtId]!.data();
      final debt = debtIds[debtId]!;
      final delta = Debt.balanceDelta(
        debtorUid: transfer.from,
        creditorUid: transfer.to,
        amount: transfer.amount,
      );
      transaction.set(debtRef.collection('entries').doc(sessionId), DebtEntry(
        sessionId: sessionId,
        fromUserId: transfer.from,
        toUserId: transfer.to,
        amount: transfer.amount,
        createdAt: DateTime.now(),
      ).toMap());
      transaction.set(debtRef, {
        ...debt.toMap(),
        'balance': ((existing?['balance'] as num?)?.toInt() ?? 0) + delta,
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
          for (final t in result.transfers) {'from': t.from, 'to': t.to, 'amount': t.amount},
        ],
        'guestObligationIds': result.guestObligations.map((o) => o.obligationId).toList(),
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
    if (expenses.isEmpty) throw ArgumentError('At least one expense is required.');
    _ensureBatchWithinFirestoreLimit(1 + members.length + expenses.length);
    final byId = {for (final member in members) member.memberId: member};
    if (byId.length != members.length || !byId.values.any((m) => m.userId == uid && !m.isGuest)) {
      throw ArgumentError('Session members must be unique and include the creator.');
    }
    for (final expense in expenses) {
      _validateExpense(expense, byId);
    }
    final previews = [
      for (var i = 0; i < expenses.length; i++)
        _expenseFromInput(expenses[i], sequence: i),
    ];
    final total = previews.fold<int>(0, (sum, expense) => sum + expense.amount);
    if (total <= 0) throw ArgumentError('Session total must be positive.');
    final sessionRef = _sessions.doc(session.sessionId);
    final batch = _db.batch();
    batch.set(sessionRef, {...session.toMap(), 'totalAmount': total});
    for (final member in members) {
      batch.set(sessionRef.collection('members').doc(member.memberId), member.toMap());
    }
    for (final expense in previews) {
      batch.set(sessionRef.collection('expenses').doc(expense.expenseId), expense.toMap());
    }
    await batch.commit();
    return session.sessionId;
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

  /// Adds an expense and updates the derived session total atomically.
  Future<String> addExpense({required String sessionId, required ExpenseInput expense}) async {
    final uid = _currentUid;
    final sessionRef = _sessions.doc(sessionId);
    await _db.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      final data = sessionSnapshot.data();
      _assertCreatorOpen(data, uid);
      final memberDocuments = await _readQueryInTransaction(
        transaction: transaction,
        query: _membersQuery(sessionId),
      );
      final members = _membersFromDocuments(memberDocuments);
      _validateExpense(expense, {for (final member in members) member.memberId: member});
      final existingExpenses = await _readQueryInTransaction(
        transaction: transaction,
        query: _expensesQuery(sessionId),
      );
      if (existingExpenses.any((document) => document.id == expense.expenseId)) {
        throw ArgumentError('Expense IDs must be unique.');
      }
      final nextSequence = existingExpenses.length;
      transaction.set(sessionRef.collection('expenses').doc(expense.expenseId),
        _expenseFromInput(expense, sequence: nextSequence).toMap());
      transaction.update(sessionRef, {
        'totalAmount': ((data!['totalAmount'] as num?)?.toInt() ?? 0) + expense.amount,
        'lastExpenseMutationId': expense.expenseId,
      });
    });
    return expense.expenseId;
  }

  /// Updates an existing item and its derived total in a transaction.
  Future<void> updateExpense({required String sessionId, required String expenseId, required ExpenseInput expense}) async {
    final uid = _currentUid;
    final sessionRef = _sessions.doc(sessionId);
    await _db.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      final data = sessionSnapshot.data();
      _assertCreatorOpen(data, uid);
      final expenseRef = sessionRef.collection('expenses').doc(expenseId);
      final oldSnapshot = await transaction.get(expenseRef);
      if (!oldSnapshot.exists) throw StateError('Không tìm thấy khoản chi.');
      final memberDocuments = await _readQueryInTransaction(
        transaction: transaction,
        query: _membersQuery(sessionId),
      );
      final members = _membersFromDocuments(memberDocuments);
      _validateExpense(expense, {for (final member in members) member.memberId: member});
      final oldAmount = (oldSnapshot.data()!['amount'] as num).toInt();
      transaction.set(expenseRef, _expenseFromInput(expense, sequence: (oldSnapshot.data()!['sequence'] as num?)?.toInt() ?? 0).toMap());
      transaction.update(sessionRef, {
        'totalAmount': ((data!['totalAmount'] as num).toInt() - oldAmount) + expense.amount,
        'lastExpenseMutationId': expenseId,
      });
    });
  }

  /// Deletes an expense unless it is the final item.
  Future<void> deleteExpense({required String sessionId, required String expenseId}) async {
    final uid = _currentUid;
    final sessionRef = _sessions.doc(sessionId);
    await _db.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      final data = sessionSnapshot.data();
      _assertCreatorOpen(data, uid);
      final expenseRef = sessionRef.collection('expenses').doc(expenseId);
      final oldSnapshot = await transaction.get(expenseRef);
      if (!oldSnapshot.exists) throw StateError('Không tìm thấy khoản chi.');
      final expenses = await _readQueryInTransaction(
        transaction: transaction,
        query: _expensesQuery(sessionId),
      );
      if (expenses.length <= 1) throw StateError('Không thể xóa khoản chi cuối cùng.');
      final amount = (oldSnapshot.data()!['amount'] as num).toInt();
      transaction.delete(expenseRef);
      transaction.update(sessionRef, {
        'totalAmount': (data!['totalAmount'] as num).toInt() - amount,
        'lastExpenseMutationId': expenseId,
      });
    });
  }

  /// Adds a set of expenses in one atomic Firestore transaction.
  Future<void> addExpenses({required String sessionId, required List<ExpenseInput> expenses}) async {
    if (expenses.isEmpty) throw ArgumentError('At least one expense is required.');
    final uid = _currentUid;
    final sessionRef = _sessions.doc(sessionId);
    await _db.runTransaction((transaction) async {
      final sessionSnapshot = await transaction.get(sessionRef);
      final data = sessionSnapshot.data();
      _assertCreatorOpen(data, uid);
      final memberDocuments = await _readQueryInTransaction(
        transaction: transaction,
        query: _membersQuery(sessionId),
      );
      final members = _membersFromDocuments(memberDocuments);
      final byId = {for (final member in members) member.memberId: member};
      final existing = await _readQueryInTransaction(
        transaction: transaction,
        query: _expensesQuery(sessionId),
      );
      final existingIds = existing.map((doc) => doc.id).toSet();
      for (var index = 0; index < expenses.length; index++) {
        final expense = expenses[index];
        if (existingIds.contains(expense.expenseId) || expenses.take(index).any((e) => e.expenseId == expense.expenseId)) {
          throw ArgumentError('Expense IDs must be unique.');
        }
        _validateExpense(expense, byId);
        transaction.set(sessionRef.collection('expenses').doc(expense.expenseId),
          _expenseFromInput(expense, sequence: existing.length + index).toMap());
      }
      transaction.update(sessionRef, {
        'totalAmount': (data!['totalAmount'] as num).toInt() + expenses.fold<int>(0, (sum, expense) => sum + expense.amount),
        'lastExpenseMutationId': expenses.last.expenseId,
      });
    });
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
      final writeCount = result.guestObligations.length + result.transfers.length * 2 +
          sessionMembers.where((member) => !member.isGuest && member.userId != null).length + 1;
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
