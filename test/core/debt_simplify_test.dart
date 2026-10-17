import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/debt_simplify.dart';
import 'package:splitpay/models/debt.dart';

Debt _debt(String a, String b, int balance) =>
    Debt(userA: a, userB: b, balance: balance, updatedAt: DateTime(2026));

/// Áp các lần chuyển lên số dư, kiểm tra mọi người về 0.
void _expectSettles(Map<String, int> net, List<Transfer> ts) {
  final left = Map<String, int>.from(net);
  for (final t in ts) {
    left[t.from] = (left[t.from] ?? 0) + t.amount;
    left[t.to] = (left[t.to] ?? 0) - t.amount;
    expect(t.amount, greaterThan(0));
  }
  expect(left.values.every((v) => v == 0), isTrue, reason: '$left');
}

void main() {
  test('chuỗi nợ B→A 300k, C→B 300k, A→C 100k gộp thành C trả A 200k', () {
    // Tên đặt theo thứ tự chữ cái: userA < userB.
    // B nợ A 300k: A<B → userA=A, balance âm.
    final net = netBalancesFromDebts([
      _debt('A', 'B', -300000), // B nợ A 300k
      _debt('B', 'C', -300000), // C nợ B 300k
      _debt('A', 'C', 100000), // A nợ C 100k
    ]);
    expect(net, {'A': 200000, 'B': 0, 'C': -200000});
    final ts = simplifyDebts(net);
    expect(ts.length, 1);
    expect(ts.first.from, 'C');
    expect(ts.first.to, 'A');
    expect(ts.first.amount, 200000);
  });

  test('ví dụ 4 người đi chơi: mọi người về 0', () {
    final net = {'A': 700000, 'B': -300000, 'C': 100000, 'D': -500000};
    final ts = simplifyDebts(net);
    _expectSettles(net, ts);
    expect(ts.length, lessThanOrEqualTo(3));
  });

  test('không ai nợ ai → không có lần chuyển nào', () {
    expect(simplifyDebts({'A': 0, 'B': 0}), isEmpty);
    expect(simplifyDebts({}), isEmpty);
  });

  test('tối đa n-1 lần chuyển và luôn cân bằng (6 người)', () {
    final net = {
      'A': 120000, 'B': 80000, 'C': -50000, 'D': -70000,
      'E': 30000, 'F': -110000,
    };
    final ts = simplifyDebts(net);
    _expectSettles(net, ts);
    expect(ts.length, lessThanOrEqualTo(net.length - 1));
  });

  test('tổng khác 0 → báo lỗi', () {
    expect(() => simplifyDebts({'A': 100, 'B': -50}), throwsArgumentError);
  });

  test('kết quả ổn định (cùng input → cùng output)', () {
    final net = {'A': 100, 'B': 100, 'C': -100, 'D': -100};
    expect(simplifyDebts(net).toString(), simplifyDebts(net).toString());
  });

  test('không tách được nhóm → n-1 lần; tách được 2 cặp → 2 lần', () {
    final net = {'A': 100, 'B': 50, 'C': -70, 'D': -80};
    final ts = simplifyDebts(net);
    _expectSettles(net, ts);
    expect(ts.length, 3);

    final net2 = {'A': 100, 'B': 100, 'C': -100, 'D': -100};
    final ts2 = simplifyDebts(net2);
    _expectSettles(net2, ts2);
    expect(ts2.length, 2);
  });

  test('số lần chuyển = n - k, khớp vét cạn trên 300 bộ số ngẫu nhiên', () {
    var seed = 12345;
    int rnd(int n) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed % n;
    }

    for (var trial = 0; trial < 300; trial++) {
      final n = 2 + rnd(6); // 2..7 người
      final values = List<int>.generate(n - 1, (_) => (rnd(7) - 3) * 10000);
      values.add(-values.fold<int>(0, (s, v) => s + v));
      final net = {for (var i = 0; i < n; i++) 'U$i': values[i]};

      final ts = simplifyDebts(net);
      _expectSettles(net, ts);

      final nonZero = values.where((v) => v != 0).toList();
      final expected = nonZero.isEmpty ? 0 : nonZero.length - _bruteMaxGroups(nonZero);
      expect(ts.length, expected, reason: 'net=$net got=$ts');
    }
  });

  test('nhóm lớn (> 18 người) vẫn đúng tiền nhờ phương án dự phòng', () {
    final net = {
      for (var i = 0; i < 20; i++) 'U${i.toString().padLeft(2, '0')}': i.isEven ? 10000 : -10000,
    };
    final ts = simplifyDebts(net);
    _expectSettles(net, ts);
  });
}

// ── Kiểm tra tối ưu bằng vét cạn ────────────────────────────────────────────

/// Số nhóm tổng-bằng-0 lớn nhất, tìm bằng cách thử mọi cách chia tập (độc lập
/// với quy hoạch động trong code chính).
int _bruteMaxGroups(List<int> v) {
  if (v.isEmpty) return 0;
  final first = v.first;
  final rest = v.sublist(1);
  var best = -1;
  for (var mask = 0; mask < (1 << rest.length); mask++) {
    var sum = first;
    final remaining = <int>[];
    for (var i = 0; i < rest.length; i++) {
      if (mask & (1 << i) != 0) {
        sum += rest[i];
      } else {
        remaining.add(rest[i]);
      }
    }
    if (sum != 0) continue;
    final sub = _bruteMaxGroups(remaining);
    if (sub >= 0 && sub + 1 > best) best = sub + 1;
  }
  return best;
}
