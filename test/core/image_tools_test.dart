import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/image_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('removeDiacritics / transferNote', () {
    test('bỏ dấu tiếng Việt', () {
      expect(removeDiacritics('Nguyễn Văn Đức'), 'Nguyen Van Duc');
      expect(removeDiacritics('Trần Thị Hồng Ánh'), 'Tran Thi Hong Anh');
      expect(removeDiacritics('ĐẶNG Ưu Ơn'), 'DANG Uu On');
      expect(removeDiacritics('abc XYZ 123'), 'abc XYZ 123');
    });

    test('nội dung chuyển khoản', () {
      expect(transferNote(debtorName: 'Lan', creditorName: 'Hoàng'), 'Lan tra tien Hoang');
    });

    test('bảng chuyển đổi đủ ký tự', () {
      const vowels = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
      final out = removeDiacritics(vowels);
      expect(RegExp(r'^[a-z]+$').hasMatch(out), isTrue, reason: out);
    });
  });

  test('ghép thẻ ảnh QR + câu thành PNG hợp lệ', () async {
    // QR giả: ảnh 200x200 đen trắng.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 200), Paint()..color = const Color(0xFF000000));
    final qrImage = await recorder.endRecording().toImage(200, 200);
    final qrPng = (await qrImage.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

    final card = await buildPaymentCard(
      qrPng: Uint8List.fromList(qrPng),
      message: 'Hi Nam, tiền "Lẩu" của bạn là 350.000đ nhé. Quét mã này gửi mình nha!',
    );

    // Là PNG, và cao hơn bề rộng (có chỗ cho chữ phía trên QR).
    expect(card.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(card);
    final img = (await codec.getNextFrame()).image;
    expect(img.width, 900);
    expect(img.height, greaterThan(900));
  });
}
