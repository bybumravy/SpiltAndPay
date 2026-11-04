import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/expense_allocation.dart';

void main() {
  test('keeps an existing item participant snapshot when a member is added later', () {
    const creator = 'creator';
    const guest = 'guest';
    const accountMemberAddedLater = 'later-member';
    final firstItemParticipants = [creator, guest];

    // Model the snapshots submitted by the editor: current IDs are not applied
    // retroactively to an already-created item.
    final laterItemParticipants = [
      ...firstItemParticipants,
      accountMemberAddedLater,
    ];
    final preview = previewSessionExpenses(
      [
        ExpenseDraft(
          amount: 10,
          payerId: creator,
          participantIds: firstItemParticipants,
        ),
        ExpenseDraft(
          amount: 10,
          payerId: creator,
          participantIds: laterItemParticipants,
        ),
      ],
      guestMemberIds: {guest},
    );

    expect(preview.owedByMember[accountMemberAddedLater], 3);
    expect(preview.owedByMember[guest], 8);
  });
}
