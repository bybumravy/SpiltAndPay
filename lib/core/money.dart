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
