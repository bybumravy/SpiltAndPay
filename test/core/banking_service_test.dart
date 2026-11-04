import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/banking_service.dart';

void main() {
  group('BankingAppService Tests', () {
    test(
      'danh sách kSupportedBanks đầy đủ các ngân hàng phổ biến tại Việt Nam',
      () {
        expect(kSupportedBanks.isNotEmpty, true);
        expect(kSupportedBanks.length, greaterThanOrEqualTo(8));

        final bankIds = kSupportedBanks.map((b) => b.id).toSet();
        expect(bankIds.contains('mbbank'), true);
        expect(bankIds.contains('vcb'), true);
        expect(bankIds.contains('techcombank'), true);
        expect(bankIds.contains('momo'), true);
        expect(bankIds.contains('bidv'), true);
      },
    );

    test('mỗi ứng dụng ngân hàng có cấu hình URI Scheme và Package hợp lệ', () {
      for (final bank in kSupportedBanks) {
        expect(
          bank.packageName.isNotEmpty,
          true,
          reason: '${bank.id} thiếu packageName',
        );
        expect(
          bank.scheme.endsWith('://'),
          true,
          reason: '${bank.id} scheme không hợp lệ: ${bank.scheme}',
        );
        expect(bank.shortName.isNotEmpty, true);
        expect(bank.brandColor.toARGB32() != 0, true);
      }
    });
  });
}
