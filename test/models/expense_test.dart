import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/models/expense.dart';

void main() {
  test('legacy expenses derive equal shares from ordered participants', () {
    final expense = Expense.fromMap('legacy-expense', {
      'description': 'Snack',
      'amount': 10,
      'payerId': 'payer',
      'participantIds': ['first', 'second', 'third'],
    });

    expect(expense.effectiveShares, {'first': 4, 'second': 3, 'third': 3});
  });

  test(
    'Expense round-trips payer, description, ordered participants and shares',
    () {
      final createdAt = DateTime(2026, 11, 2, 12);
      final expense = Expense(
        expenseId: 'expense-1',
        description: 'Lunch',
        amount: 1000,
        payerId: 'account-a',
        participantIds: const ['account-a', 'guest-x'],
        shares: const {'account-a': 500, 'guest-x': 500},
        sequence: 2,
        createdAt: createdAt,
      );

      final map = expense.toMap();
      final decoded = Expense.fromMap('expense-1', map);

      expect(decoded.expenseId, 'expense-1');
      expect(decoded.description, 'Lunch');
      expect(decoded.amount, 1000);
      expect(decoded.payerId, 'account-a');
      expect(decoded.participantIds, ['account-a', 'guest-x']);
      expect(decoded.shares, {'account-a': 500, 'guest-x': 500});
      expect(decoded.sequence, 2);
      expect(decoded.createdAt, createdAt);
      expect(map['createdAt'], isA<Timestamp>());
    },
  );

  test(
    'GuestObligation round-trips payer, guest, amount, status and audit fields',
    () {
      final createdAt = DateTime(2026, 11, 2, 12);
      final collectedAt = DateTime(2026, 11, 2, 13);
      final obligation = GuestObligation(
        obligationId: 'obligation-1',
        sessionId: 'session-1',
        expenseId: 'expense-1',
        payerId: 'account-b',
        guestMemberId: 'guest-x',
        amount: 500,
        status: GuestObligationStatus.collected,
        createdAt: createdAt,
        collectedAt: collectedAt,
        collectedBy: 'account-b',
      );

      final decoded = GuestObligation.fromMap(
        'obligation-1',
        obligation.toMap(),
      );

      expect(decoded.obligationId, 'obligation-1');
      expect(decoded.payerId, 'account-b');
      expect(decoded.guestMemberId, 'guest-x');
      expect(decoded.expenseId, 'expense-1');
      expect(decoded.amount, 500);
      expect(decoded.status, GuestObligationStatus.collected);
      expect(decoded.createdAt, createdAt);
      expect(decoded.collectedAt, collectedAt);
      expect(decoded.collectedBy, 'account-b');
    },
  );

  test(
    'GuestObligation safely defaults absent legacy status and audit fields',
    () {
      final decoded = GuestObligation.fromMap('old-obligation', {
        'sessionId': 'session-1',
        'payerId': 'account-a',
        'guestMemberId': 'guest-y',
        'amount': 100,
      });

      expect(decoded.status, GuestObligationStatus.pending);
      expect(decoded.createdAt, isNull);
      expect(decoded.collectedAt, isNull);
      expect(decoded.collectedBy, isNull);
    },
  );
}
