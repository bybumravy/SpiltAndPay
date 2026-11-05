import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/models/debt.dart';

void main() {
  group('Dashboard Net Balance & Action Required Logic', () {
    const currentUid = 'user_truong';
    const otherUid1 = 'user_vy';
    const otherUid2 = 'user_hoang';

    test('tính đúng tổng nợ, tổng được nợ và số dư ròng', () {
      final debts = [
        // Trường nợ Vy 150.000đ (balance > 0 khi userA nợ userB)
        Debt(
          userA: currentUid,
          userB: otherUid1,
          balance: 150000,
          updatedAt: DateTime.now(),
        ),
        // Hoàng nợ Trường 300.000đ (Trường là userB, balance > 0 nghĩa là Hoàng nợ Trường)
        Debt(
          userA: otherUid2,
          userB: currentUid,
          balance: 300000,
          updatedAt: DateTime.now(),
        ),
      ];

      var totalOwed = 0;
      var totalReceivable = 0;

      for (final d in debts) {
        final amount = d.amountOwedBy(currentUid);
        if (amount > 0) {
          totalOwed += amount;
        } else if (amount < 0) {
          totalReceivable += amount.abs();
        }
      }

      final netBalance = totalReceivable - totalOwed;

      expect(totalOwed, 150000);
      expect(totalReceivable, 300000);
      expect(netBalance, 150000); // Dương 150k -> Được thu về nhiều hơn
    });

    test('phân loại chính xác các khoản nợ cần thanh toán ngay', () {
      final debts = [
        Debt(
          userA: currentUid,
          userB: otherUid1,
          balance: 200000, // Trường nợ Vy 200k
          updatedAt: DateTime.now(),
        ),
        Debt(
          userA: otherUid2,
          userB: currentUid,
          balance: 50000, // Hoàng nợ Trường 50k
          updatedAt: DateTime.now(),
        ),
        Debt(
          userA: 'other_a',
          userB: currentUid,
          balance: 0, // Đã hoà
          updatedAt: DateTime.now(),
        ),
      ];

      final debtsToPay = debts.where((d) => d.amountOwedBy(currentUid) > 0).toList();

      expect(debtsToPay.length, 1);
      expect(debtsToPay.first.userB, otherUid1);
      expect(debtsToPay.first.amountOwedBy(currentUid), 200000);
    });

    test('chủ nợ KHÔNG có việc cần làm nếu con nợ chưa thanh toán (k hiển thị ở Cần xử lý ngay)', () {
      final debts = [
        Debt(
          userA: otherUid2,
          userB: currentUid,
          balance: 50000, // Hoàng nợ Trường 50k
          updatedAt: DateTime.now(),
          pendingPaymentId: null, // Chưa thanh toán
        ),
      ];

      // Logic mục Cần xử lý ngay
      final pendingConfirmation = debts.where((d) {
        final isCreditor = d.amountOwedBy(currentUid) < 0;
        return isCreditor && d.hasPendingPayment;
      }).toList();

      final debtsToPay = debts.where((d) => d.amountOwedBy(currentUid) > 0).toList();
      final urgentItems = [...pendingConfirmation, ...debtsToPay];

      // Kỳ vọng: Danh sách việc cần làm RỖNG vì con nợ chưa chuyển tiền
      expect(urgentItems.isEmpty, isTrue);
    });

    test('chủ nợ CÓ việc cần làm khi con nợ đã chuyển tiền chờ xác nhận', () {
      final debts = [
        Debt(
          userA: otherUid2,
          userB: currentUid,
          balance: 50000, // Hoàng nợ Trường 50k
          updatedAt: DateTime.now(),
          pendingPaymentId: 'pay_123', // Hoàng đã bấm "Tôi đã chuyển"
        ),
      ];

      // Logic mục Cần xử lý ngay
      final pendingConfirmation = debts.where((d) {
        final isCreditor = d.amountOwedBy(currentUid) < 0;
        return isCreditor && d.hasPendingPayment;
      }).toList();

      final debtsToPay = debts.where((d) => d.amountOwedBy(currentUid) > 0).toList();
      final urgentItems = [...pendingConfirmation, ...debtsToPay];

      // Kỳ vọng: 1 việc cần làm (xác nhận chuyển khoản)
      expect(urgentItems.length, 1);
      expect(urgentItems.first.pendingPaymentId, 'pay_123');
      expect(urgentItems.first.amountOwedBy(currentUid) < 0, isTrue);
    });
  });
}
