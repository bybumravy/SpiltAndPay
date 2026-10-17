import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/bill_ocr.dart';

void main() {
  group('parseAmount', () {
    test('định dạng VND', () {
      expect(parseAmount('350.000'), 350000);
      expect(parseAmount('350,000'), 350000);
      expect(parseAmount('1.250.000'), 1250000);
      expect(parseAmount('350.000,00'), 350000);
      expect(parseAmount('350000'), 350000);
    });
    test('loại số không phải tiền', () {
      expect(parseAmount('0901234567'), isNull); // số điện thoại
      expect(parseAmount('12.50'), isNull);
      expect(parseAmount('500'), isNull);
    });
  });

  group('findBillTotal', () {
    test('lấy số cạnh "Tổng cộng", không phải số lớn nhất', () {
      final r = findBillTotal([
        'QUÁN LẨU ABC',
        'ĐT: 0901234567',
        'Lẩu thái   2   200.000',
        'Bia   6   120.000',
        'Tạm tính: 320.000',
        'Tổng cộng: 350.000',
        'Tiền khách đưa: 500.000',
      ]);
      expect(r.total, 350000);
      expect(r.confident, isTrue);
    });

    test('nhãn và số nằm ở 2 dòng khác nhau', () {
      final r = findBillTotal(['Món A 50.000', 'TỔNG TIỀN', '1.250.000đ']);
      expect(r.total, 1250000);
    });

    test('không có từ khóa → lấy số lớn nhất, không tự tin', () {
      final r = findBillTotal(['Món A 50.000', 'Món B 120.000']);
      expect(r.total, 120000);
      expect(r.confident, isFalse);
    });

    test('không có số nào', () {
      expect(findBillTotal(['Xin cảm ơn']).total, isNull);
    });
  });
}
