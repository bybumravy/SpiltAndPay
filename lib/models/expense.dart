import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/expense_allocation.dart';

class Expense {
  final String expenseId;
  final String description;
  final int amount;
  final String payerId;
  final List<String> participantIds;
  final Map<String, int> shares;
  final int sequence;
  final DateTime? createdAt;

  const Expense({
    required this.expenseId,
    required this.description,
    required this.amount,
    required this.payerId,
    required this.participantIds,
    required this.shares,
    this.sequence = 0,
    this.createdAt,
  });

  Map<String, int> get effectiveShares => shares.isNotEmpty
      ? shares
      : allocateExpenseShares(amount: amount, participantIds: participantIds);

  factory Expense.fromMap(String id, Map<String, dynamic> map) {
    final rawShares = map['shares'] as Map? ?? const {};
    return Expense(
      expenseId: id,
      description: map['description'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      payerId: map['payerId'] as String? ?? '',
      participantIds: List<String>.from(
        map['participantIds'] as List? ?? const [],
      ),
      shares: rawShares.map(
        (key, value) => MapEntry(key as String, (value as num).toInt()),
      ),
      sequence: (map['sequence'] as num?)?.toInt() ?? 0,
      createdAt: _dateFrom(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'description': description,
    'amount': amount,
    'payerId': payerId,
    'participantIds': participantIds,
    'shares': shares,
    'sequence': sequence,
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
  };
}

DateTime? _dateFrom(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

enum GuestObligationStatus { pending, collected }

class GuestObligation {
  final String obligationId;
  final String sessionId;
  final String? expenseId;
  final String payerId;
  final String guestMemberId;
  final int amount;
  final GuestObligationStatus status;
  final DateTime? createdAt;
  final DateTime? collectedAt;
  final String? collectedBy;

  const GuestObligation({
    required this.obligationId,
    required this.sessionId,
    this.expenseId,
    required this.payerId,
    required this.guestMemberId,
    required this.amount,
    this.status = GuestObligationStatus.pending,
    this.createdAt,
    this.collectedAt,
    this.collectedBy,
  });

  factory GuestObligation.fromMap(String id, Map<String, dynamic> map) {
    return GuestObligation(
      obligationId: id,
      sessionId: map['sessionId'] as String? ?? '',
      expenseId: map['expenseId'] as String?,
      payerId: map['payerId'] as String? ?? '',
      guestMemberId: map['guestMemberId'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      status: GuestObligationStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => GuestObligationStatus.pending,
      ),
      createdAt: _dateFrom(map['createdAt']),
      collectedAt: _dateFrom(map['collectedAt']),
      collectedBy: map['collectedBy'] as String?,
    );
  }

  GuestObligation copyWith({
    GuestObligationStatus? status,
    DateTime? collectedAt,
    String? collectedBy,
  }) => GuestObligation(
    obligationId: obligationId,
    sessionId: sessionId,
    expenseId: expenseId,
    payerId: payerId,
    guestMemberId: guestMemberId,
    amount: amount,
    status: status ?? this.status,
    createdAt: createdAt,
    collectedAt: collectedAt ?? this.collectedAt,
    collectedBy: collectedBy ?? this.collectedBy,
  );

  Map<String, dynamic> toMap() => {
    'sessionId': sessionId,
    if (expenseId != null) 'expenseId': expenseId,
    'payerId': payerId,
    'guestMemberId': guestMemberId,
    'amount': amount,
    'status': status.name,
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    if (collectedAt != null) 'collectedAt': Timestamp.fromDate(collectedAt!),
    if (collectedBy != null) 'collectedBy': collectedBy,
  };

  @override
  bool operator ==(Object other) =>
      other is GuestObligation &&
      other.obligationId == obligationId &&
      other.sessionId == sessionId &&
      other.expenseId == expenseId &&
      other.payerId == payerId &&
      other.guestMemberId == guestMemberId &&
      other.amount == amount &&
      other.status == status &&
      other.collectedBy == collectedBy;

  @override
  int get hashCode => Object.hash(
    obligationId,
    sessionId,
    expenseId,
    payerId,
    guestMemberId,
    amount,
    status,
    collectedBy,
  );
}

/// Local policy helper. Firestore Rules and app checks do not make client-side
/// collection verification server-authoritative.
GuestObligation? collectGuestObligation(
  GuestObligation obligation, {
  required String actorUid,
}) {
  if (obligation.payerId != actorUid) return null;
  if (obligation.status == GuestObligationStatus.collected) return obligation;
  return obligation.copyWith(
    status: GuestObligationStatus.collected,
    collectedAt: DateTime.now(),
    collectedBy: actorUid,
  );
}
