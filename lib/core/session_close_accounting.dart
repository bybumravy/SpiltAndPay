import '../models/session_member.dart';
import 'debt_simplify.dart';
import 'expense_allocation.dart';

class CloseExpense {
  final String expenseId;
  final int amount;
  final String payerId;
  final List<String> participantIds;

  const CloseExpense({
    required this.expenseId,
    required this.amount,
    required this.payerId,
    required this.participantIds,
  });
}

class CloseGuestObligation {
  final String obligationId;
  final String expenseId;
  final String payerId;
  final String guestMemberId;
  final int amount;

  const CloseGuestObligation({
    required this.obligationId,
    required this.expenseId,
    required this.payerId,
    required this.guestMemberId,
    required this.amount,
  });

  @override
  bool operator ==(Object other) =>
      other is CloseGuestObligation &&
      other.obligationId == obligationId &&
      other.expenseId == expenseId &&
      other.payerId == payerId &&
      other.guestMemberId == guestMemberId &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(
    obligationId,
    expenseId,
    payerId,
    guestMemberId,
    amount,
  );
}

class CloseTransfer {
  final String from;
  final String to;
  final int amount;

  const CloseTransfer({required this.from, required this.to, required this.amount});

  @override
  bool operator ==(Object other) =>
      other is CloseTransfer &&
      other.from == from &&
      other.to == to &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(from, to, amount);
}

class SessionCloseResult {
  final int totalAmount;
  final Map<String, ({int owed, int paid})> memberAmounts;
  final List<CloseGuestObligation> guestObligations;
  final List<CloseTransfer> transfers;

  const SessionCloseResult({
    required this.totalAmount,
    required this.memberAmounts,
    required this.guestObligations,
    required this.transfers,
  });
}

SessionCloseResult calculateSessionClose({
  required List<CloseExpense> expenses,
  required List<SessionMember> members,
  required String creatorId,
  int? expectedTotal,
}) {
  final byId = <String, SessionMember>{};
  for (final member in members) {
    if (member.memberId.trim().isEmpty || byId.containsKey(member.memberId)) {
      throw ArgumentError('Session members must have unique nonempty ids.');
    }
    byId[member.memberId] = member;
  }

  if (expenses.isEmpty) {
    return _calculateLegacyClose(members, creatorId, expectedTotal);
  }

  var total = 0;
  final paid = <String, int>{};
  final owed = <String, int>{};
  final net = <String, int>{};
  final obligations = <CloseGuestObligation>[];

  for (final expense in expenses) {
    final payer = byId[expense.payerId];
    if (payer == null || payer.isGuest || payer.userId == null) {
      throw ArgumentError('Expense payer must be an account member.');
    }
    if (expense.amount <= 0) {
      throw ArgumentError.value(expense.amount, 'amount', 'Must be positive.');
    }
    final shares = allocateExpenseShares(
      amount: expense.amount,
      participantIds: expense.participantIds,
    );
    if (expense.participantIds.any((id) => !byId.containsKey(id))) {
      throw ArgumentError('Expense participant must be a current session member.');
    }

    total += expense.amount;
    paid.update(payer.memberId, (value) => value + expense.amount,
        ifAbsent: () => expense.amount);
    net.update(payer.userId!, (value) => value + expense.amount,
        ifAbsent: () => expense.amount);

    for (final entry in shares.entries) {
      final member = byId[entry.key]!;
      owed.update(entry.key, (value) => value + entry.value,
          ifAbsent: () => entry.value);
      if (member.isGuest || member.userId == null) {
        if (entry.value > 0) {
          obligations.add(CloseGuestObligation(
            obligationId: '${expense.expenseId}_${member.memberId}',
            expenseId: expense.expenseId,
            payerId: payer.userId!,
            guestMemberId: member.memberId,
            amount: entry.value,
          ));
        }
        net.update(payer.userId!, (value) => value - entry.value);
      } else {
        net.update(member.userId!, (value) => value - entry.value,
            ifAbsent: () => -entry.value);
      }
    }
  }

  if (expectedTotal != null && total != expectedTotal) {
    throw ArgumentError('Expense total does not match session total.');
  }
  if (net.values.fold<int>(0, (sum, value) => sum + value) != 0) {
    throw StateError('Account positions must sum to zero.');
  }

  final memberAmounts = <String, ({int owed, int paid})>{};
  for (final member in members) {
    memberAmounts[member.memberId] = (
      owed: owed[member.memberId] ?? 0,
      paid: paid[member.memberId] ?? 0,
    );
  }
  return SessionCloseResult(
    totalAmount: total,
    memberAmounts: memberAmounts,
    guestObligations: obligations,
    transfers: [
      for (final transfer in simplifyDebts(net))
        CloseTransfer(from: transfer.from, to: transfer.to, amount: transfer.amount),
    ],
  );
}

SessionCloseResult _calculateLegacyClose(
  List<SessionMember> members,
  String creatorId,
  int? expectedTotal,
) {
  final totalOwed = members.fold<int>(0, (total, member) {
    if (member.amountOwed < 0) throw ArgumentError('amountOwed must be nonnegative.');
    return total + member.amountOwed;
  });
  final paidSum = members.fold<int>(0, (total, member) {
    if (member.amountPaid < 0) throw ArgumentError('amountPaid must be nonnegative.');
    return total + member.amountPaid;
  });
  final legacy = paidSum == 0;
  if (!legacy && paidSum != totalOwed) {
    throw ArgumentError('Paid total does not match owed total.');
  }
  if (expectedTotal != null && expectedTotal != totalOwed) {
    throw ArgumentError('Legacy owed total does not match session total.');
  }
  final guestOwed = members
      .where((member) => member.isGuest || member.userId == null)
      .fold<int>(0, (sum, member) => sum + member.amountOwed);
  final net = <String, int>{};
  for (final member in members) {
    if (member.isGuest || member.userId == null) continue;
    final memberPaid = legacy && member.userId == creatorId
        ? totalOwed
        : member.amountPaid;
    net.update(member.userId!, (value) => value + memberPaid - member.amountOwed,
        ifAbsent: () => memberPaid - member.amountOwed);
  }
  net.update(creatorId, (value) => value - guestOwed,
      ifAbsent: () => -guestOwed);
  return SessionCloseResult(
    totalAmount: totalOwed,
    memberAmounts: {
      for (final member in members)
        member.memberId: (owed: member.amountOwed, paid: member.amountPaid),
    },
    guestObligations: const [],
    transfers: [
      for (final transfer in simplifyDebts(net))
        CloseTransfer(from: transfer.from, to: transfer.to, amount: transfer.amount),
    ],
  );
}
