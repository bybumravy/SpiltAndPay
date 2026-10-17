import 'package:intl/intl.dart';

/// Format số nguyên VND thành chuỗi "350.000đ".
String formatVnd(int amount) {
  final formatter = NumberFormat('#,###', 'vi_VN');
  return '${formatter.format(amount)}đ';
}

/// Chia [total] đều cho [count] người.
/// Phần dư (modulo) được cộng vào phần của người đầu tiên (người tạo phiên).
/// Trả về danh sách [count] phần tiền (int).
List<int> splitEqual(int total, int count) {
  assert(count > 0, 'Phải có ít nhất 1 người');
  final base = total ~/ count;
  final remainder = total % count;
  return List.generate(count, (i) => i == 0 ? base + remainder : base);
}

/// Tính phần phải trả của từng người trong phiên: `[người tạo, ...các thành viên]`.
///
/// [customAmounts]: số tiền nhập tay của từng thành viên khác (null = chưa nhập),
/// chỉ dùng khi [custom] = true. Người đã nhập giữ nguyên số đó; phần còn lại của
/// bill chia đều cho những ai chưa nhập (gồm cả người tạo), phần dư về người tạo.
/// Luôn có tổng đúng bằng [total]. Throw [ArgumentError] nếu số nhập tay vượt bill.
List<int> computeShares({
  required int total,
  required List<int?> customAmounts,
  required bool custom,
}) {
  if (!custom) return splitEqual(total, customAmounts.length + 1);

  final customSum = customAmounts.fold<int>(0, (s, v) => s + (v ?? 0));
  if (customSum > total) {
    throw ArgumentError('Tổng tuỳ chỉnh vượt tổng bill.');
  }
  final uncustomized = customAmounts.where((v) => v == null).length + 1; // +creator
  final rest = splitEqual(total - customSum, uncustomized);
  var next = 0;
  return [
    rest[next++], // người tạo
    for (final v in customAmounts) v ?? rest[next++],
  ];
}
