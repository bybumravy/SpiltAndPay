import 'dart:io';

import 'package:mobile_scanner/mobile_scanner.dart';

/// Giới hạn dung lượng ảnh QR (byte).
const _maxImageBytes = 5 * 1024 * 1024;

/// Kết quả đọc mã VietQR (chuẩn EMVCo / NAPAS 247).
class VietQrInfo {
  /// Mã BIN ngân hàng thụ hưởng (VD: 970436 = Vietcombank).
  final String bin;

  /// Số tài khoản hoặc số thẻ nhận tiền.
  final String account;

  const VietQrInfo({required this.bin, required this.account});
}

class VietQrException implements Exception {
  final String message;
  const VietQrException(this.message);

  @override
  String toString() => message;
}

/// Kiểm tra [image] có phải ảnh mã QR ngân hàng (VietQR) hợp lệ không.
/// Trả về thông tin BIN/số tài khoản, hoặc throw [VietQrException] kèm lý do.
Future<VietQrInfo> verifyBankQrImage(File image) async {
  if (await image.length() > _maxImageBytes) {
    throw const VietQrException('Ảnh quá lớn (tối đa 5MB).');
  }

  final controller = MobileScannerController();
  BarcodeCapture? capture;
  try {
    capture = await controller.analyzeImage(image.path);
  } finally {
    await controller.dispose();
  }

  final payload = capture?.barcodes
      .map((b) => b.rawValue)
      .whereType<String>()
      .firstOrNull;
  if (payload == null) {
    throw const VietQrException(
        'Không tìm thấy mã QR trong ảnh. Hãy chọn ảnh QR rõ nét, không bị cắt.');
  }
  return parseVietQr(payload);
}

/// Phân tích chuỗi nội dung VietQR. Throw [VietQrException] nếu không hợp lệ.
VietQrInfo parseVietQr(String payload) {
  const notBank = VietQrException(
      'Đây không phải mã QR ngân hàng (VietQR). Hãy dùng mã tải từ app ngân hàng.');

  if (!payload.startsWith('000201') || payload.length < 12) throw notBank;
  if (!_crcValid(payload)) throw notBank;

  final root = _parseTlv(payload);
  final merchant = root['38']; // Merchant account information (NAPAS)
  if (merchant == null) throw notBank;

  final inner = _parseTlv(merchant);
  if (inner['00'] != 'A000000727') throw notBank; // GUID NAPAS

  final beneficiary = inner['01'];
  if (beneficiary == null) throw notBank;
  final b = _parseTlv(beneficiary);
  final bin = b['00'];
  final account = b['01'];
  if (bin == null || account == null || account.isEmpty) throw notBank;

  return VietQrInfo(bin: bin, account: account);
}

/// Tách chuỗi TLV (tag 2 ký tự, độ dài 2 ký tự, giá trị).
Map<String, String> _parseTlv(String s) {
  final out = <String, String>{};
  var i = 0;
  while (i + 4 <= s.length) {
    final tag = s.substring(i, i + 2);
    final len = int.tryParse(s.substring(i + 2, i + 4));
    if (len == null || i + 4 + len > s.length) {
      throw const VietQrException('Mã QR bị lỗi hoặc không đọc được.');
    }
    out[tag] = s.substring(i + 4, i + 4 + len);
    i += 4 + len;
  }
  return out;
}

/// CRC16-CCITT (poly 0x1021, init 0xFFFF) của chuỗi trừ 4 ký tự cuối.
bool _crcValid(String payload) {
  if (payload.length < 8 || payload.substring(payload.length - 8, payload.length - 4) != '6304') {
    return false;
  }
  var crc = 0xFFFF;
  for (final unit in payload.substring(0, payload.length - 4).codeUnits) {
    crc ^= unit << 8;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  final expected = payload.substring(payload.length - 4).toUpperCase();
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0') == expected;
}

// ── Tạo mã VietQR động (có sẵn số tiền + nội dung) ─────────────────────────

/// Từ nội dung mã VietQR TĨNH của chủ nợ, dựng mã VietQR ĐỘNG có điền sẵn
/// [amount] (VND) và [note] (nội dung chuyển khoản). Làm hoàn toàn trên máy,
/// không gọi API nào: sửa tag 01 (11→12), thêm tag 54 (số tiền) và tag 62.08
/// (nội dung), rồi tính lại CRC.
///
/// [note] được bỏ dấu và cắt còn tối đa 25 ký tự (giới hạn của VietQR).
/// Throw [VietQrException] nếu [staticPayload] không phải VietQR hợp lệ.
String buildDynamicVietQr(
  String staticPayload, {
  required int amount,
  required String note,
}) {
  parseVietQr(staticPayload); // kiểm tra hợp lệ (CRC, NAPAS...)
  if (amount <= 0) throw const VietQrException('Số tiền phải lớn hơn 0.');

  final fields = _parseTlvList(staticPayload)
      .where((f) => f.key != '63' && f.key != '54') // bỏ CRC và số tiền cũ (nếu có)
      .toList();

  // Tag 01: 11 = mã dùng nhiều lần, 12 = mã có số tiền.
  final i01 = fields.indexWhere((f) => f.key == '01');
  if (i01 >= 0) fields[i01] = const MapEntry('01', '12');
  fields.add(MapEntry('54', amount.toString()));

  // Tag 62 (thông tin bổ sung): đặt sub-tag 08 = nội dung, giữ các sub-tag khác.
  final cleanNote = _cleanNote(note);
  final i62 = fields.indexWhere((f) => f.key == '62');
  final extra = i62 >= 0 ? _parseTlvList(fields[i62].value) : <MapEntry<String, String>>[];
  extra.removeWhere((f) => f.key == '08');
  if (cleanNote.isNotEmpty) extra.add(MapEntry('08', cleanNote));
  extra.sort((a, b) => a.key.compareTo(b.key));
  if (i62 >= 0) fields.removeAt(i62);
  if (extra.isNotEmpty) fields.add(MapEntry('62', extra.map(_tlv).join()));

  fields.sort((a, b) => a.key.compareTo(b.key)); // đúng thứ tự tag tăng dần
  final body = '${fields.map(_tlv).join()}6304';
  return '$body${_crc16(body)}';
}

/// Nội dung chuyển khoản: bỏ dấu, chỉ giữ chữ/số/khoảng trắng, tối đa 25 ký tự.
String _cleanNote(String note) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final noMarks = note.toLowerCase().split('').map((c) {
    final i = from.indexOf(c);
    return i >= 0 ? to[i] : c;
  }).join();
  final cleaned = noMarks.replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r' +'), ' ').trim();
  return cleaned.length > 25 ? cleaned.substring(0, 25).trim() : cleaned;
}

String _tlv(MapEntry<String, String> f) =>
    '${f.key}${f.value.length.toString().padLeft(2, '0')}${f.value}';

/// Tách TLV giữ nguyên thứ tự.
List<MapEntry<String, String>> _parseTlvList(String s) {
  final out = <MapEntry<String, String>>[];
  var i = 0;
  while (i + 4 <= s.length) {
    final tag = s.substring(i, i + 2);
    final len = int.tryParse(s.substring(i + 2, i + 4));
    if (len == null || i + 4 + len > s.length) {
      throw const VietQrException('Mã QR bị lỗi hoặc không đọc được.');
    }
    out.add(MapEntry(tag, s.substring(i + 4, i + 4 + len)));
    i += 4 + len;
  }
  return out;
}

/// CRC16-CCITT (poly 0x1021, init 0xFFFF) dạng 4 ký tự hex in hoa.
String _crc16(String data) {
  var crc = 0xFFFF;
  for (final unit in data.codeUnits) {
    crc ^= unit << 8;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// Chỉ để test: CRC của chuỗi bất kỳ.
String crc16ForTest(String data) => _crc16(data);
