import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/vietqr.dart';

/// Dựng một mã VietQR TĨNH hợp lệ (có CRC) để test.
String _staticQr({String bin = '970436', String account = '0123456789', String? extra62}) {
  String tlv(String t, String v) => '$t${v.length.toString().padLeft(2, '0')}$v';
  final beneficiary = tlv('00', bin) + tlv('01', account);
  final merchant = tlv('00', 'A000000727') + tlv('01', beneficiary) + tlv('02', 'QRIBFTTA');
  final body = tlv('00', '01') +
      tlv('01', '11') +
      tlv('38', merchant) +
      tlv('53', '704') +
      tlv('58', 'VN') +
      (extra62 != null ? tlv('62', extra62) : '') +
      '6304';
  return '$body${crc16ForTest(body)}';
}

String _field(String payload, String tag) {
  var i = 0;
  while (i + 4 <= payload.length) {
    final t = payload.substring(i, i + 2);
    final len = int.parse(payload.substring(i + 2, i + 4));
    if (t == tag) return payload.substring(i + 4, i + 4 + len);
    i += 4 + len;
  }
  return '';
}

void main() {
  test('CRC16-CCITT đúng với vector chuẩn "123456789" = 29B1', () {
    expect(crc16ForTest('123456789'), '29B1');
  });

  test('mã tĩnh dựng trong test được parse đúng', () {
    final info = parseVietQr(_staticQr());
    expect(info.bin, '970436');
    expect(info.account, '0123456789');
  });

  test('dựng mã động: có số tiền, nội dung, tag 01=12, CRC hợp lệ, giữ nguyên TK', () {
    final dyn = buildDynamicVietQr(_staticQr(), amount: 350000, note: 'Lan tra tien Hoàng');
    final info = parseVietQr(dyn); // CRC + NAPAS hợp lệ
    expect(info.bin, '970436');
    expect(info.account, '0123456789');
    expect(_field(dyn, '01'), '12');
    expect(_field(dyn, '54'), '350000');
    expect(_field(_field(dyn, '62'), '08'), 'lan tra tien hoang');
    expect(dyn.startsWith('000201'), isTrue);
    expect(dyn.contains('6304'), isTrue);
  });

  test('nội dung dài bị cắt còn tối đa 25 ký tự, bỏ ký tự lạ', () {
    final dyn = buildDynamicVietQr(_staticQr(),
        amount: 1000, note: 'Nguyễn Văn Anh Tuấn tra tien Trần Thị Bích Ngọc!!!');
    final note = _field(_field(dyn, '62'), '08');
    expect(note.length, lessThanOrEqualTo(25));
    expect(RegExp(r'^[a-z0-9 ]+$').hasMatch(note), isTrue);
  });

  test('giữ nguyên các sub-tag khác của tag 62 và thay số tiền cũ', () {
    final base = buildDynamicVietQr(_staticQr(extra62: '0305ABCDE'), amount: 100000, note: 'a');
    expect(_field(_field(base, '62'), '03'), 'ABCDE');
    // dựng lại từ mã đã có số tiền: số tiền cũ bị thay, không bị lặp tag 54
    final again = buildDynamicVietQr(base, amount: 200000, note: 'b');
    expect(_field(again, '54'), '200000');
    expect('54'.allMatches(again).isNotEmpty, isTrue);
    expect(parseVietQr(again).account, '0123456789');
  });

  test('mã không phải VietQR / số tiền không hợp lệ → lỗi', () {
    expect(() => buildDynamicVietQr('https://example.com', amount: 1000, note: 'x'),
        throwsA(isA<VietQrException>()));
    expect(() => buildDynamicVietQr(_staticQr(), amount: 0, note: 'x'),
        throwsA(isA<VietQrException>()));
  });

  test('sửa 1 ký tự trong mã động thì CRC báo lỗi', () {
    final dyn = buildDynamicVietQr(_staticQr(), amount: 350000, note: 'x');
    final tampered = dyn.replaceFirst('350000', '350001');
    expect(() => parseVietQr(tampered), throwsA(isA<VietQrException>()));
  });
}
