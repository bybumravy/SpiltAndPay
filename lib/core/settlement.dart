import '../models/session_member.dart';
import 'debt_simplify.dart';

/// Chốt nợ của một phiên: trả về danh sách chuyển tiền **ít nhất** giữa các
/// thành viên có app (có thể giữa hai người bất kỳ, không nhất thiết qua creator).
///
/// Mỗi thành viên có app: net = đã ứng - phải trả (dương = được nhận).
/// Khách (guest) không có tài khoản nên không vào sổ nợ: phần của khách do
/// creator gánh và tự thu tiền mặt, nên được cộng vào phần phải trả của creator.
/// Phiên cũ không có `amountPaid` (tổng = 0) → coi creator đã ứng toàn bộ.
///
/// Throw [StateError] nếu tổng đã ứng khác tổng phải trả (dữ liệu hỏng).
List<Transfer> settleSession({
  required String creatorId,
  required List<SessionMember> members,
}) {
  final totalOwed = members.fold<int>(0, (s, m) => s + m.amountOwed);
  final paidSum = members.fold<int>(0, (s, m) => s + m.amountPaid);
  final legacy = paidSum == 0;
  if (!legacy && paidSum != totalOwed) {
    throw StateError('Tổng tiền đã ứng ($paidSum) khác tổng phải trả ($totalOwed).');
  }

  final guestOwed = members
      .where((m) => m.isGuest || m.userId == null)
      .fold<int>(0, (s, m) => s + m.amountOwed);

  final net = <String, int>{};
  for (final m in members) {
    if (m.isGuest || m.userId == null) continue;
    final uid = m.userId!;
    final paid = (legacy && uid == creatorId) ? totalOwed : m.amountPaid;
    net[uid] = (net[uid] ?? 0) + paid - m.amountOwed;
  }
  net[creatorId] = (net[creatorId] ?? 0) - guestOwed;

  return simplifyDebts(net);
}
