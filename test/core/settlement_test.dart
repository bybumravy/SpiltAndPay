import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/debt_simplify.dart';
import 'package:splitpay/core/settlement.dart';
import 'package:splitpay/models/session_member.dart';

SessionMember _m(String uid, int owed, {int paid = 0, bool guest = false}) =>
    SessionMember(
      memberId: uid,
      userId: guest ? null : uid,
      displayName: uid,
      isGuest: guest,
      amountOwed: owed,
      amountPaid: paid,
      status: MemberStatus.ledger,
    );

/// Số dư mỗi người sau khi áp các lần chuyển (dương = còn được nhận).
Map<String, int> _apply(Map<String, int> net, List<Transfer> ts) {
  final left = Map<String, int>.from(net);
  for (final t in ts) {
    left[t.from] = (left[t.from] ?? 0) + t.amount;
    left[t.to] = (left[t.to] ?? 0) - t.amount;
  }
  return left;
}

void main() {
  test('phiên cũ (không có amountPaid): mọi người nợ creator', () {
    final ts = settleSession(creatorId: 'A', members: [
      _m('A', 250000),
      _m('B', 250000),
      _m('C', 250000),
      _m('D', 250000),
    ]);
    expect(ts.length, 3);
    expect(ts.every((t) => t.to == 'A' && t.amount == 250000), isTrue);
  });

  test('A ứng 1200k, B ứng 200k, C ứng 600k, chia đều 500k/4 người', () {
    final members = [
      _m('A', 500000, paid: 1200000),
      _m('B', 500000, paid: 200000),
      _m('C', 500000, paid: 600000),
      _m('D', 500000),
    ];
    final ts = settleSession(creatorId: 'A', members: members);
    // net: A +700, B -300, C +100, D -500 → tối thiểu 3 lần.
    expect(ts.length, 3);
    final net = {'A': 700000, 'B': -300000, 'C': 100000, 'D': -500000};
    expect(_apply(net, ts).values.every((v) => v == 0), isTrue);
  });

  test('2 cặp tách biệt chỉ cần 2 lần chuyển', () {
    final ts = settleSession(creatorId: 'A', members: [
      _m('A', 0, paid: 100000),
      _m('B', 0, paid: 100000),
      _m('C', 100000),
      _m('D', 100000),
    ]);
    expect(ts.length, 2);
  });

  test('guest: creator gánh phần của khách, khách không vào sổ nợ', () {
    final ts = settleSession(creatorId: 'A', members: [
      _m('A', 100000, paid: 300000),
      _m('B', 100000),
      _m('G', 100000, guest: true),
    ]);
    expect(ts.length, 1);
    expect(ts.first.from, 'B');
    expect(ts.first.to, 'A');
    expect(ts.first.amount, 100000);
  });

  test('ai ứng đúng phần mình thì không sinh nợ', () {
    final ts = settleSession(creatorId: 'A', members: [
      _m('A', 100000, paid: 100000),
      _m('B', 100000, paid: 100000),
    ]);
    expect(ts, isEmpty);
  });

  test('tổng ứng khác tổng phải trả → báo lỗi, không ghi bậy', () {
    expect(
      () => settleSession(creatorId: 'A', members: [
        _m('A', 100000, paid: 150000),
        _m('B', 100000),
      ]),
      throwsStateError,
    );
  });
}
