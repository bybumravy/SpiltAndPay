import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'image_tools.dart';
import 'vietqr.dart';

/// Đọc nội dung mã VietQR tĩnh từ ảnh QR của chủ nợ (tải ảnh về rồi quét trên máy).
/// Trả về null nếu không đọc được / không phải VietQR → app dùng ảnh QR gốc.
final staticQrPayloadProvider =
    FutureProvider.family<String?, String>((ref, imageUrl) async {
  try {
    final bytes = await downloadImageBytes(imageUrl);
    final path = await writeTempImage(bytes, 'qr_${imageUrl.hashCode}.png');
    final controller = MobileScannerController();
    try {
      final capture = await controller.analyzeImage(path);
      final payload = capture?.barcodes
          .map((b) => b.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (payload == null) return null;
      parseVietQr(payload); // đảm bảo là VietQR hợp lệ
      return payload;
    } finally {
      await controller.dispose();
    }
  } catch (_) {
    return null;
  }
});
