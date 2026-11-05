import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/models/expense.dart';

void main() {
  test('guest collection is idempotent for the actual payer only', () {
    const pending = GuestObligation(
      obligationId: 'e1_guest',
      sessionId: 'session',
      expenseId: 'e1',
      payerId: 'payer',
      guestMemberId: 'guest',
      amount: 10,
    );

    expect(collectGuestObligation(pending, actorUid: 'payer'), isNotNull);
    expect(collectGuestObligation(pending, actorUid: 'someone-else'), isNull);
    final collected = pending.copyWith(
      status: GuestObligationStatus.collected,
      collectedBy: 'payer',
    );
    expect(collectGuestObligation(collected, actorUid: 'payer'), collected);
  });
}
