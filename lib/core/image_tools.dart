import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Tải ảnh từ [url], trả về dữ liệu byte. Throw nếu lỗi mạng / HTTP.
Future<Uint8List> downloadImageBytes(String url) async {
  final res = await http.get(Uri.parse(url));
  if (res.statusCode != 200) {
    throw Exception('Tải ảnh thất bại: HTTP ${res.statusCode}');
  }
  return res.bodyBytes;
}

/// Tên album trong thư viện ảnh: ảnh QR lưu riêng vào đây cho dễ tìm.
const kQrAlbum = 'SplitPay';

/// Lưu ảnh vào album [kQrAlbum] của thư viện ảnh (để mở app ngân hàng quét lại).
Future<void> saveImageToGallery(Uint8List bytes, {String name = 'qr'}) async {
  await Gal.putImageBytes(bytes, album: kQrAlbum, name: name);
}

/// Mở ứng dụng thư viện ảnh của máy.
Future<void> openGallery() => Gal.open();

/// Ghi [bytes] ra file tạm (để chia sẻ qua Zalo, Messenger...). Trả về đường dẫn.
Future<String> writeTempImage(Uint8List bytes, String fileName) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Bỏ dấu tiếng Việt: "Nguyễn Văn Đức" → "Nguyen Van Duc".
/// Nội dung chuyển khoản nên không dấu vì nhiều ngân hàng không nhận ký tự có dấu.
String removeDiacritics(String input) {
  const from =
      'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ'
      'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
  const to =
      'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd'
      'AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
  assert(from.length == to.length);
  final map = {for (var i = 0; i < from.length; i++) from[i]: to[i]};
  return input.split('').map((c) => map[c] ?? c).join();
}

/// Nội dung chuyển khoản gợi ý: "[Tên bạn] tra tien [Tên chủ nợ]" (không dấu).
String transferNote({required String debtorName, required String creditorName}) {
  return '${removeDiacritics(debtorName)} tra tien ${removeDiacritics(creditorName)}';
}

/// Ghép ảnh QR của chủ nợ với đoạn chữ thành MỘT tấm ảnh để gửi qua chat
/// (chữ nằm ngay trong ảnh nên không bị mất khi ứng dụng chat bỏ caption).
Future<Uint8List> buildPaymentCard({
  required Uint8List qrPng,
  required String message,
  double width = 900,
}) async {
  const pad = 48.0;
  final qr = await _decode(qrPng);

  final text = TextPainter(
    text: TextSpan(
      text: message,
      style: const TextStyle(
        color: Color(0xFF222222),
        fontSize: 40,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width - pad * 2);

  // QR giữ nguyên tỉ lệ, vừa chiều ngang.
  final qrW = width - pad * 2;
  final qrH = qrW * qr.height / qr.width;
  final height = pad + text.height + 36 + qrH + pad;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xFFFFFFFF));
  text.paint(canvas, Offset(pad, pad));
  canvas.drawImageRect(
    qr,
    Rect.fromLTWH(0, 0, qr.width.toDouble(), qr.height.toDouble()),
    Rect.fromLTWH(pad, pad + text.height + 36, qrW, qrH),
    Paint()..filterQuality = FilterQuality.high,
  );

  final image = await recorder.endRecording().toImage(width.round(), height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

/// Vẽ [data] thành ảnh QR PNG nền trắng, có viền trống (để app ngân hàng quét được).
Future<Uint8List> renderQrPng(String data, {double size = 1024, double margin = 96}) async {
  final qr = await QrPainter(
    data: data,
    version: QrVersions.auto,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  ).toImage(size);

  final total = size + margin * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, total, total), Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawImage(qr, Offset(margin, margin), Paint());
  final image = await recorder.endRecording().toImage(total.round(), total.round());
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}
