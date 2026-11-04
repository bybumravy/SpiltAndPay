import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/session_close_accounting.dart';
import 'package:splitpay/models/session_member.dart';

void main() {
  test('zero guest shares do not create collectible obligations', () {
    final result = calculateSessionClose(
      creatorId: 'A',
      members: const [
        SessionMember(
          memberId: 'A',
          userId: 'A',
          displayName: 'A',
          isGuest: false,
          amountOwed: 0,
          status: MemberStatus.self,
        ),
        SessionMember(
          memberId: 'G',
          userId: null,
          displayName: 'Guest',
          isGuest: true,
          amountOwed: 0,
          status: MemberStatus.pending,
        ),
      ],
      expenses: const [
        CloseExpense(
          expenseId: 'tiny',
          amount: 1,
          payerId: 'A',
          participantIds: ['A', 'G'],
        ),
      ],
    );
    expect(result.memberAmounts['G']!.owed, 0);
    expect(result.guestObligations, isEmpty);
  });
}
