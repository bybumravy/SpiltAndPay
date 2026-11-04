import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/session_close_accounting.dart';
import 'package:splitpay/models/session_member.dart';

void main() {
  group('calculateSessionClose', () {
    test('assigns guest claims to each actual payer across all expenses', () {
      final result = calculateSessionClose(
        expenses: const [
          CloseExpense(
            expenseId: 'e1',
            amount: 10,
            payerId: 'a-member',
            participantIds: ['a-member', 'b-member', 'guest'],
          ),
          CloseExpense(
            expenseId: 'e2',
            amount: 8,
            payerId: 'b-member',
            participantIds: ['a-member', 'b-member'],
          ),
        ],
        members: const [
          SessionMember(memberId: 'a-member', userId: 'a', displayName: 'A', isGuest: false, amountOwed: 0, status: MemberStatus.self),
          SessionMember(memberId: 'b-member', userId: 'b', displayName: 'B', isGuest: false, amountOwed: 0, status: MemberStatus.ledger),
          SessionMember(memberId: 'guest', userId: null, displayName: 'Guest', isGuest: true, amountOwed: 0, status: MemberStatus.pending),
        ],
        creatorId: 'a',
      );

      expect(result.totalAmount, 18);
      expect(result.memberAmounts['a-member'], (owed: 8, paid: 10));
      expect(result.memberAmounts['b-member'], (owed: 7, paid: 8));
      expect(result.memberAmounts['guest'], (owed: 3, paid: 0));
      expect(result.guestObligations, [
        const CloseGuestObligation(obligationId: 'e1_guest', expenseId: 'e1', payerId: 'a', guestMemberId: 'guest', amount: 3),
      ]);
      expect(result.transfers.map((t) => (from: t.from, to: t.to, amount: t.amount)), [
        (from: 'a', to: 'b', amount: 1),
      ]);
    });

    test('preserves legacy creator fallback when paid totals are absent', () {
      final result = calculateSessionClose(
        expenses: const [],
        members: const [
          SessionMember(memberId: 'a-member', userId: 'a', displayName: 'A', isGuest: false, amountOwed: 60, amountPaid: 0, status: MemberStatus.self),
          SessionMember(memberId: 'b-member', userId: 'b', displayName: 'B', isGuest: false, amountOwed: 30, status: MemberStatus.ledger),
          SessionMember(memberId: 'guest', userId: null, displayName: 'Guest', isGuest: true, amountOwed: 10, status: MemberStatus.pending),
        ],
        creatorId: 'a',
      );

      expect(result.totalAmount, 100);
      expect(result.transfers, [const CloseTransfer(from: 'b', to: 'a', amount: 30)]);
      expect(result.guestObligations, isEmpty);
    });

    test('rejects item total that differs from session total', () {
      expect(
        () => calculateSessionClose(
          expenses: const [CloseExpense(expenseId: 'e1', amount: 5, payerId: 'a-member', participantIds: ['a-member'])],
          members: const [SessionMember(memberId: 'a-member', userId: 'a', displayName: 'A', isGuest: false, amountOwed: 0, status: MemberStatus.self)],
          creatorId: 'a',
          expectedTotal: 6,
        ),
        throwsArgumentError,
      );
    });
  });
}
