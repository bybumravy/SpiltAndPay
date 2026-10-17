import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/money.dart';
import 'package:splitpay/models/debt.dart';

Debt _debt(String a, String b, int balance) =>
    Debt(userA: a, userB: b, balance: balance, updatedAt: DateTime(2026));

void main() {
  group('splitEqual', () {
    test('chia hết', () => expect(splitEqual(300000, 3), [100000, 100000, 100000]));
    test('phần dư cộng cho người đầu tiên', () {
      final s = splitEqual(100000, 3);
      expect(s, [33334, 33333, 33333]);
      expect(s.reduce((a, b) => a + b), 100000);
    });
    test('1 người', () => expect(splitEqual(50000, 1), [50000]));
  });

  group('Debt', () {
    test('docId ổn định bất kể thứ tự', () {
      expect(Debt.docId('b', 'a'), Debt.docId('a', 'b'));
    });

    test('B nợ A: lẩu 300k + cafe 50k → cộng dồn 350k', () {
      // A < B  → A là userA. B (userB) nợ A (userA) → balance âm.
      var balance = 0;
      balance += Debt.balanceDelta(debtorUid: 'B', creditorUid: 'A', amount: 300000);
      balance += Debt.balanceDelta(debtorUid: 'B', creditorUid: 'A', amount: 50000);
      final d = _debt('A', 'B', balance);
      expect(d.amountOwedBy('B'), 350000);
      expect(d.amountOwedBy('A'), -350000);
      expect(d.creditorFor('B'), 'A');
      expect(d.creditorFor('A'), isNull);
    });

    test('nợ chéo bù trừ: A nợ B 100k, B nợ A 300k → B còn nợ A 200k', () {
      var balance = 0;
      balance += Debt.balanceDelta(debtorUid: 'B', creditorUid: 'A', amount: 300000);
      balance += Debt.balanceDelta(debtorUid: 'A', creditorUid: 'B', amount: 100000);
      final d = _debt('A', 'B', balance);
      expect(d.amountOwedBy('B'), 200000);
    });

    test('trả đủ thì về 0', () {
      var balance = Debt.balanceDelta(debtorUid: 'A', creditorUid: 'B', amount: 80000);
      expect(_debt('A', 'B', balance).amountOwedBy('A'), 80000);
      balance += -80000; // confirmPayment khi debtorIsUserA
      expect(balance, 0);
      expect(_debt('A', 'B', balance).creditorFor('A'), isNull);
    });
  });
}
