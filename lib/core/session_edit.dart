import 'dart:convert';

import '../models/expense.dart';
import '../models/session.dart';
import '../models/session_member.dart';
import 'session_close_accounting.dart';

/// Compare editable values rather than snapshot arrival order or timestamps.
String sessionEditFingerprint(
  Session session,
  List<SessionMember> members,
  List<Expense> expenses,
) {
  final orderedMembers = [...members]
    ..sort((a, b) => a.memberId.compareTo(b.memberId));
  final orderedExpenses = [...expenses]
    ..sort((a, b) => a.expenseId.compareTo(b.expenseId));
  return jsonEncode([
    session.title,
    session.totalAmount,
    session.splitMode.name,
    [...session.memberUserIds]..sort(),
    for (final m in orderedMembers)
      [
        m.memberId,
        m.userId,
        m.displayName,
        m.isGuest,
        m.amountOwed,
        m.amountPaid,
        m.status.name,
      ],
    for (final e in orderedExpenses)
      [
        e.expenseId,
        e.description,
        e.amount,
        e.payerId,
        e.participantIds,
        e.sequence,
      ],
  ]);
}

/// Rebuild all accounting from the final draft. No debt/payment is written here.
SessionCloseResult validateSessionEdit({
  required String title,
  required String creatorId,
  required List<SessionMember> members,
  required List<Expense> expenses,
}) {
  if (title.trim().isEmpty) throw ArgumentError('Nhập tên phiên.');
  if (expenses.isEmpty) throw ArgumentError('Phiên cần ít nhất một khoản chi.');
  final accountIds = <String>{};
  for (final member in members) {
    if (member.isGuest != (member.userId == null) ||
        (!member.isGuest &&
            (member.userId!.isEmpty || !accountIds.add(member.userId!)))) {
      throw ArgumentError('Thành viên tài khoản không hợp lệ hoặc bị trùng.');
    }
    if (member.displayName.trim().isEmpty) {
      throw ArgumentError('Tên thành viên không được để trống.');
    }
  }
  if (!members.any(
    (m) => m.memberId == creatorId && m.userId == creatorId && !m.isGuest,
  )) {
    throw ArgumentError('Không được xoá hoặc thay đổi người tạo phiên.');
  }
  final expenseIds = <String>{};
  for (final expense in expenses) {
    if (expense.expenseId.isEmpty ||
        !expenseIds.add(expense.expenseId) ||
        expense.description.trim().isEmpty) {
      throw ArgumentError('Khoản chi phải có mã duy nhất và mô tả.');
    }
  }
  return calculateSessionClose(
    creatorId: creatorId,
    members: members,
    expenses: [
      for (final e in expenses)
        CloseExpense(
          expenseId: e.expenseId,
          amount: e.amount,
          payerId: e.payerId,
          participantIds: e.participantIds,
        ),
    ],
  );
}
