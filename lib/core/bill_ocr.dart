import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Kết quả tìm tổng tiền trên hóa đơn.
class BillScanResult {
  /// Tổng tiền (VND), null nếu không tìm thấy.
  final int? total;

  /// true nếu số này nằm cạnh từ khóa như "Tổng cộng"; false nếu chỉ là
  /// số lớn nhất đoán được → nên nhắc user kiểm tra lại.
  final bool confident;

  /// Các số tiền khác tìm thấy (giảm dần), để gợi ý nếu user muốn đổi.
  final List<int> candidates;

  const BillScanResult({
    required this.total,
    required this.confident,
    required this.candidates,
  });
}

/// Đọc ảnh hóa đơn bằng ML Kit (chạy trên máy) rồi tìm tổng tiền.
Future<BillScanResult> scanBill(File image) async {
  final recognizer = TextRecognizer();
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(image.path),
    );
    final lines = groupBillLines([
      for (final block in result.blocks)
        for (final line in block.lines)
          BillTextLine(
            line.text,
            line.boundingBox.left,
            line.boundingBox.top,
            line.boundingBox.width,
            line.boundingBox.height,
          ),
    ]);
    return findBillTotal(lines);
  } finally {
    await recognizer.close();
  }
}

/// Reconstruct visual rows: ML Kit returns blocks by column, not receipt order.
class BillTextLine {
  final String text;
  final double left, top, width, height;
  const BillTextLine(this.text, this.left, this.top, this.width, this.height);
  double get centerY => top + height / 2;
}

List<String> groupBillLines(List<BillTextLine> input) {
  final sorted = [...input]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<BillTextLine>>[];
  for (final line in sorted) {
    List<BillTextLine>? target;
    var distance = double.infinity;
    for (final row in rows) {
      final anchor = row.first;
      final delta = (anchor.centerY - line.centerY).abs();
      final tolerance =
          (anchor.height < line.height ? anchor.height : line.height) * .65;
      final overlaps = row.any(
        (other) =>
            line.left < other.left + other.width &&
            line.left + line.width > other.left,
      );
      if (delta <= tolerance && delta < distance && !overlaps) {
        target = row;
        distance = delta;
      }
    }
    if (target == null) {
      rows.add([line]);
    } else {
      target.add(line);
    }
  }
  return [
    for (final row in rows)
      (row..sort((a, b) => a.left.compareTo(b.left)))
          .map((l) => l.text)
          .join(' '),
  ];
}

// Dòng chứa các từ này là tổng tiền thật.
const _totalKeywords = [
  'tổng cộng',
  'tổng tiền',
  'tổng thanh toán',
  'tổng số tiền',
  'cần thanh toán',
  'phải trả',
  'tong cong',
  'tong tien',
  'grand total',
  'total due',
  'amount due',
  'total',
];

// Dòng chứa các từ này KHÔNG phải tổng cuối (tạm tính, tiền khách đưa...).
const _excludeKeywords = [
  'noi dung',
  'cong ty',
  'tạm tính',
  'tam tinh',
  'subtotal',
  'sub total',
  'khách đưa',
  'khách trả',
  'tiền thừa',
  'trả lại',
  'tien thua',
  'change',
  'cash',
  'giảm',
  'discount',
  'điểm',
  'vat',
  'thuế',
];

final _amountToken = RegExp(
  r'(?<![0-9])(?:[1-9][0-9]{0,2}(?:[ \u00a0\u202f][0-9]{3})+(?![0-9])|[0-9][0-9.,]*[0-9]|[0-9])',
);

String _normalize(String text) {
  var result = text.toLowerCase();
  const groups = {
    'a': 'àáảãạăằắẳẵặâầấẩẫậ',
    'e': 'èéẻẽẹêềếểễệ',
    'i': 'ìíỉĩị',
    'o': 'òóỏõọôồốổỗộơờớởỡợ',
    'u': 'ùúủũụưừứửữự',
    'y': 'ỳýỷỹỵ',
    'd': 'đ',
  };
  for (final entry in groups.entries) {
    for (final rune in entry.value.runes) {
      result = result.replaceAll(String.fromCharCode(rune), entry.key);
    }
  }
  return result
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Tìm tổng tiền từ các dòng chữ của hóa đơn (theo thứ tự trên xuống dưới).
BillScanResult findBillTotal(List<String> lines) {
  final all = <int>{};
  final keyed = <int>[];

  for (var i = 0; i < lines.length; i++) {
    final text = _normalize(lines[i]);
    final amounts = _amountsIn(lines[i]);
    all.addAll(amounts);

    final isTotalLine =
        _totalKeywords.any((k) => text.contains(_normalize(k))) &&
        !_excludeKeywords.any((k) => text.contains(_normalize(k)));
    if (!isTotalLine) continue;

    if (amounts.isNotEmpty) {
      keyed.add(amounts.reduce((a, b) => a > b ? a : b));
    } else {
      // ML Kit hay tách nhãn và số thành 2 dòng: nhìn 2 dòng kế tiếp.
      for (var j = i + 1; j <= i + 2 && j < lines.length; j++) {
        final next = _amountsIn(lines[j]);
        if (next.isNotEmpty) {
          keyed.add(next.reduce((a, b) => a > b ? a : b));
          break;
        }
      }
    }
  }

  final candidates = all.toList()..sort((a, b) => b.compareTo(a));
  if (keyed.isNotEmpty) {
    final total = keyed.reduce((a, b) => a > b ? a : b);
    return BillScanResult(
      total: total,
      confident: true,
      candidates: candidates,
    );
  }
  return BillScanResult(
    total: candidates.isEmpty ? null : candidates.first,
    confident: false,
    candidates: candidates,
  );
}

List<int> _amountsIn(String line) {
  return [
    for (final m in _amountToken.allMatches(line))
      ?parseAmount(m.group(0)!),
  ];
}

/// Đổi chuỗi số trên hóa đơn thành VND nguyên. Trả null nếu không giống tiền.
/// Hỗ trợ "350.000", "350,000", "1.250.000", "350.000,00", "12.50".
int? parseAmount(String token) {
  var t = token.replaceAll(RegExp(r'[ \u00a0\u202f]'), '');
  // Bỏ phần lẻ ở cuối khi đã có nhóm nghìn: "350.000,00" → "350.000".
  final withDecimal = RegExp(r'^(\d{1,3}([.,]\d{3})+)[.,]\d{1,2}$')
      .firstMatch(t);
  if (withDecimal != null) t = withDecimal.group(1)!;

  final hasSeparator = t.contains('.') || t.contains(',');
  if (hasSeparator && !RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(t)) {
    // Dạng lạ (VD "12.5", "1,2,3") → không phải tiền VND.
    return null;
  }
  final digits = t.replaceAll(RegExp(r'[.,]'), '');

  // Số điện thoại / mã số: bắt đầu bằng 0 và dài.
  if (digits.startsWith('0') && digits.length >= 9) return null;
  if (digits.length > 9) {
    return null; // > 999 triệu: gần như chắc không phải bill.
  }

  final value = int.tryParse(digits);
  if (value == null || value < 1000) return null;
  return value;
}
