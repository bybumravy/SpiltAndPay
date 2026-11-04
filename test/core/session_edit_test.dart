import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/session_edit.dart';
import 'package:splitpay/models/session.dart';
import 'package:splitpay/models/session_member.dart';
import 'package:splitpay/models/expense.dart';

SessionMember member(String id, {bool guest = false}) => SessionMember(
  memberId: id,
  userId: guest ? null : id,
  displayName: id,
  isGuest: guest,
  amountOwed: 0,
  status: guest ? MemberStatus.pending : MemberStatus.ledger,
);
Expense item(String id, int amount, String payer, List<String> participants) =>
    Expense(
      expenseId: id,
      description: id,
      amount: amount,
      payerId: payer,
      participantIds: participants,
      shares: const {},
    );
Session session({String title = 'Trip'}) => Session(
  sessionId: 'S',
  creatorId: 'A',
  title: title,
  totalAmount: 520000,
  splitMode: SessionSplitMode.equal,
  status: SessionStatus.open,
  memberUserIds: ['A', 'B', 'C'],
  createdAt: DateTime(2026),
);

void main() {
  test('rounding a guest share to zero creates no collectible claim', () {
    final result = validateSessionEdit(
      title: 'Small',
      creatorId: 'A',
      members: [member('A'), member('G', guest: true)],
      expenses: [
        item('tiny', 1, 'A', ['A', 'G']),
      ],
    );
    expect(result.memberAmounts['G']!.owed, 0);
    expect(result.guestObligations, isEmpty);
  });

  test('edited payer, participants and guests feed the same close/payment accounting', () {
    final result = validateSessionEdit(
      title: 'Trip edited',
      creatorId: 'A',
      members: [
        member('A'),
        member('B'),
        member('C'),
        member('G', guest: true),
      ],
      expenses: [
        item('food', 300000, 'A', ['A', 'B', 'C']),
        item('taxi', 120000, 'B', ['A', 'B']),
        item('drink', 100000, 'A', ['B', 'G']),
      ],
    );
    expect(result.totalAmount, 520000);
    expect(result.memberAmounts['A'], (owed: 160000, paid: 400000));
    expect(result.memberAmounts['B'], (owed: 210000, paid: 120000));
    expect(result.guestObligations.single.amount, 50000);
    expect(result.guestObligations.single.payerId, 'A');
    expect(
      result.transfers.map((t) => '${t.from}:${t.to}:${t.amount}').toSet(),
      {'B:A:90000', 'C:A:100000'},
    );
  });
  test('removing a member and reassigning its expenses recomputes debt and rounding', () {
    final result = validateSessionEdit(
      title: 'Trip',
      creatorId: 'A',
      members: [member('A'), member('C')],
      expenses: [
        item('food', 100001, 'C', ['A', 'C']),
      ],
    );
    expect(result.memberAmounts['A']!.owed, 50001);
    expect(result.memberAmounts['C']!.paid, 100001);
    expect(result.transfers.single.from, 'A');
    expect(result.transfers.single.to, 'C');
    expect(result.transfers.single.amount, 50001);
    expect(result.guestObligations, isEmpty);
  });
  test('rejects removing creator, stale participant references, guest payer and last item', () {
    expect(
      () => validateSessionEdit(
        title: 'x',
        creatorId: 'A',
        members: [member('B')],
        expenses: [
          item('x', 1, 'B', ['B']),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => validateSessionEdit(
        title: 'x',
        creatorId: 'A',
        members: [member('A')],
        expenses: [
          item('x', 1, 'A', ['B']),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => validateSessionEdit(
        title: 'x',
        creatorId: 'A',
        members: [member('A'), member('G', guest: true)],
        expenses: [
          item('x', 1, 'G', ['A']),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => validateSessionEdit(
        title: 'x',
        creatorId: 'A',
        members: [member('A')],
        expenses: [],
      ),
      throwsArgumentError,
    );
  });
  test('fingerprints ignore snapshot order but detect changed title and item inputs', () {
    final a = member('A');
    final b = member('B');
    final x = item('x', 100, 'A', ['A', 'B']);
    final y = item('y', 200, 'B', ['B']);
    final baseline = sessionEditFingerprint(session(), [a, b], [x, y]);
    expect(sessionEditFingerprint(session(), [b, a], [y, x]), baseline);
    expect(
      sessionEditFingerprint(session(title: 'other'), [a, b], [x, y]),
      isNot(baseline),
    );
    expect(
      sessionEditFingerprint(
        session(),
        [a, b],
        [
          item('x', 101, 'B', ['B', 'A']),
          y,
        ],
      ),
      isNot(baseline),
    );
  });
}
