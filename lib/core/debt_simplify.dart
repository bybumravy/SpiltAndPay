import '../models/debt.dart';

/// Một lần chuyển tiền gợi ý: [from] chuyển [amount] cho [to].
class Transfer {
  final String from;
  final String to;
  final int amount;

  const Transfer({required this.from, required this.to, required this.amount});

  @override
  String toString() => '$from → $to: $amount';
}

/// Số dư ròng của từng người từ danh sách nợ từng cặp.
/// Dương = đang được nhận, âm = đang phải trả.
Map<String, int> netBalancesFromDebts(Iterable<Debt> debts) {
  final net = <String, int>{};
  for (final d in debts) {
    // balance > 0: userA nợ userB.
    net[d.userA] = (net[d.userA] ?? 0) - d.balance;
    net[d.userB] = (net[d.userB] ?? 0) + d.balance;
  }
  return net;
}

/// Nhóm lớn nhất vẫn giải đúng được bằng quy hoạch động (2^n trạng thái).
const _maxExactSize = 18;

/// Rút gọn nợ với **số lần chuyển ít nhất**.
///
/// Số lần chuyển nhỏ nhất = n - k, với k là số nhóm lớn nhất tách được sao cho
/// mỗi nhóm có tổng số dư bằng 0 (mỗi nhóm m người cần đúng m-1 lần chuyển).
/// Tìm k bằng quy hoạch động theo tập con (n ≤ 18); lớn hơn thì dùng tham lam
/// (không tối ưu nhưng luôn đúng tiền, tối đa n-1 lần).
///
/// [net]: uid → số dư ròng (dương = được nhận, âm = phải trả).
/// Tổng số dư phải bằng 0, nếu không throw [ArgumentError].
List<Transfer> simplifyDebts(Map<String, int> net) {
  if (net.values.fold<int>(0, (s, v) => s + v) != 0) {
    throw ArgumentError('Tổng số dư ròng phải bằng 0.');
  }

  // Bỏ người đã hòa, sắp theo uid để kết quả ổn định.
  final entries = [
    for (final e in net.entries)
      if (e.value != 0) e,
  ]..sort((a, b) => a.key.compareTo(b.key));
  if (entries.isEmpty) return [];

  if (entries.length > _maxExactSize) {
    return _greedy({for (final e in entries) e.key: e.value});
  }

  final groups = _maxZeroSumGroups(entries);
  return [
    for (final g in groups) ..._greedy({for (final e in g) e.key: e.value}),
  ];
}

/// Tách [entries] thành số nhóm tổng-bằng-0 nhiều nhất.
List<List<MapEntry<String, int>>> _maxZeroSumGroups(
    List<MapEntry<String, int>> entries) {
  final n = entries.length;
  final size = 1 << n;

  final sum = List<int>.filled(size, 0);
  for (var mask = 1; mask < size; mask++) {
    final low = mask & -mask;
    sum[mask] = sum[mask ^ low] + entries[low.bitLength - 1].value;
  }

  // dp[mask] = số tiền tố có tổng 0 nhiều nhất khi thêm dần các phần tử của mask.
  final dp = List<int>.filled(size, 0);
  for (var mask = 1; mask < size; mask++) {
    var best = 0;
    for (var i = 0; i < n; i++) {
      if (mask & (1 << i) != 0) {
        final v = dp[mask ^ (1 << i)];
        if (v > best) best = v;
      }
    }
    dp[mask] = best + (sum[mask] == 0 ? 1 : 0);
  }

  // Lần ngược để lấy thứ tự thêm phần tử.
  final removed = <int>[];
  var mask = size - 1;
  while (mask != 0) {
    final target = dp[mask] - (sum[mask] == 0 ? 1 : 0);
    for (var i = 0; i < n; i++) {
      if (mask & (1 << i) != 0 && dp[mask ^ (1 << i)] == target) {
        removed.add(i);
        mask ^= 1 << i;
        break;
      }
    }
  }

  // Đọc theo chiều thuận; mỗi lần tiền tố tổng 0 thì kết thúc một nhóm.
  final groups = <List<MapEntry<String, int>>>[];
  var current = <MapEntry<String, int>>[];
  var running = 0;
  for (final i in removed.reversed) {
    current.add(entries[i]);
    running += entries[i].value;
    if (running == 0) {
      groups.add(current);
      current = [];
    }
  }
  return groups;
}

/// Tham lam: ghép người nợ nhiều nhất với người được nhận nhiều nhất.
List<Transfer> _greedy(Map<String, int> net) {
  final debtors = [
    for (final e in net.entries)
      if (e.value < 0) _Entry(e.key, -e.value),
  ]..sort(_byAmountThenUid);
  final creditors = [
    for (final e in net.entries)
      if (e.value > 0) _Entry(e.key, e.value),
  ]..sort(_byAmountThenUid);

  final result = <Transfer>[];
  while (debtors.isNotEmpty && creditors.isNotEmpty) {
    final d = debtors.first;
    final c = creditors.first;
    final pay = d.amount < c.amount ? d.amount : c.amount;
    result.add(Transfer(from: d.uid, to: c.uid, amount: pay));
    d.amount -= pay;
    c.amount -= pay;
    if (d.amount == 0) debtors.removeAt(0);
    if (c.amount == 0) creditors.removeAt(0);
    debtors.sort(_byAmountThenUid);
    creditors.sort(_byAmountThenUid);
  }
  return result;
}

class _Entry {
  final String uid;
  int amount;
  _Entry(this.uid, this.amount);
}

int _byAmountThenUid(_Entry a, _Entry b) {
  final c = b.amount.compareTo(a.amount); // lớn trước
  return c != 0 ? c : a.uid.compareTo(b.uid);
}
