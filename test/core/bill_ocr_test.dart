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

  test('space-grouped amounts and imperfect Vietnamese accents', () {
    expect(parseAmount('606 549'), 606549);
    expect(parseAmount('1\u00a0250\u00a0000'), 1250000);
    final r = findBillTotal([
      'Nội dung: thanh toán tiền điện',
      'tháng 09/2015',
      'Thành tiền',
      '551 408',
      'Thuế GTGT 55 141',
      '|Tóng tiền 606 549',
      'Tiền khách đưa 1 000 000',
    ]);
    expect(r.total, 606549);
    expect(r.confident, isTrue);
  });
  test('reconstructs separate OCR column blocks into visual receipt rows', () {
    final rows = groupBillLines(const [
      BillTextLine('Tóng tiền', 0, 100, 100, 20),
      BillTextLine('Thuế GTGT', 0, 60, 100, 20),
      BillTextLine('606 549', 200, 102, 100, 20),
      BillTextLine('55 141', 200, 61, 100, 20),
    ]);
    expect(rows, ['Thuế GTGT 55 141', 'Tóng tiền 606 549']);
    expect(findBillTotal(rows).total, 606549);
  });
  test('table headers and company names cannot identify a final total', () {
    final r = findBillTotal([
      'TỔNG CÔNG TY ĐIỆN LỰC',
      '123456',
      'Đơn giá Thành tiền',
      '700000',
    ]);
    expect(r.confident, isFalse);
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
