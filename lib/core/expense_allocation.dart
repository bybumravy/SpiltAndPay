int _validateAndAllocate(
  int amount,
  List<String> participantIds,
  void Function(String, int) add,
) {
  if (amount <= 0) {
    throw ArgumentError.value(amount, 'amount', 'Must be positive');
  }
  if (participantIds.isEmpty) {
    throw ArgumentError.value(
      participantIds,
      'participantIds',
      'Must not be empty',
    );
  }
  if (participantIds.any((id) => id.trim().isEmpty) ||
      participantIds.toSet().length != participantIds.length) {
    throw ArgumentError.value(
      participantIds,
      'participantIds',
      'Must contain unique nonempty ids',
    );
  }

  final base = amount ~/ participantIds.length;
  final remainder = amount % participantIds.length;
  for (var i = 0; i < participantIds.length; i++) {
    add(participantIds[i], base + (i < remainder ? 1 : 0));
  }
  return amount;
}

Map<String, int> allocateExpenseShares({
  required int amount,
  required List<String> participantIds,
}) {
  final shares = <String, int>{};
  _validateAndAllocate(amount, participantIds, shares.addAllEntry);
  return shares;
}

extension on Map<String, int> {
  void addAllEntry(String key, int value) => this[key] = value;
}

class ExpenseDraft {
  final int amount;
  final String payerId;
  final List<String> participantIds;

  const ExpenseDraft({
    required this.amount,
    required this.payerId,
    required this.participantIds,
  });
}

class SessionExpensePreview {
  final int totalAmount;
  final Map<String, int> paidByMember;
  final Map<String, int> owedByMember;
  final Map<String, int> guestClaimsByPayer;
  final Map<String, int> accountNetPositions;

  const SessionExpensePreview({
    required this.totalAmount,
    required this.paidByMember,
    required this.owedByMember,
    required this.guestClaimsByPayer,
    required this.accountNetPositions,
  });
}

SessionExpensePreview previewSessionExpenses(
  List<ExpenseDraft> expenses, {
  Set<String> guestMemberIds = const {},
}) {
  final paidByMember = <String, int>{};
  final owedByMember = <String, int>{};
  final guestClaimsByPayer = <String, int>{};
  final accountNetPositions = <String, int>{};
  var totalAmount = 0;

  for (final expense in expenses) {
    _validateAndAllocate(expense.amount, expense.participantIds, (
      memberId,
      share,
    ) {
      owedByMember.update(
        memberId,
        (value) => value + share,
        ifAbsent: () => share,
      );
      if (guestMemberIds.contains(memberId)) {
        guestClaimsByPayer.update(
          expense.payerId,
          (value) => value + share,
          ifAbsent: () => share,
        );
      } else {
        accountNetPositions.update(
          memberId,
          (value) => value - share,
          ifAbsent: () => -share,
        );
      }
    });
    paidByMember.update(
      expense.payerId,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
    accountNetPositions.update(
      expense.payerId,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
    totalAmount += expense.amount;
  }

  for (final entry in guestClaimsByPayer.entries) {
    accountNetPositions.update(
      entry.key,
      (value) => value - entry.value,
      ifAbsent: () => -entry.value,
    );
  }
  return SessionExpensePreview(
    totalAmount: totalAmount,
    paidByMember: paidByMember,
    owedByMember: owedByMember,
    guestClaimsByPayer: guestClaimsByPayer,
    accountNetPositions: accountNetPositions,
  );
}
