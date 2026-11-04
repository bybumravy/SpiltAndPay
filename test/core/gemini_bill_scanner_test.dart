import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/gemini_bill_scanner.dart';

Map<String, Object?> receipt({
  int? amount = 606549,
  String? currency = 'VND',
  String? evidence = '606 549',
  bool review = false,
}) => {
  'description': 'Tiền điện',
  'total_vnd': amount,
  'currency': currency,
  'total_text': evidence,
  'needs_review': review,
};

Map<String, Object?> batch(
  List<Map<String, Object?>> receipts, {
  List<int> unreadable = const [],
}) => {
  'receipts': [
    for (final r in receipts) {'image_index': 1, ...r},
  ],
  'unreadable_images': unreadable,
};

void main() {
  test('extracts a draft only when VND amount matches the quoted digits', () {
    final r = parseGeminiBill(jsonEncode(receipt()));
    expect(r.total, 606549);
    expect(r.description, 'Tiền điện');
    expect(r.confident, isTrue);
    expect(
      parseGeminiBill(
        jsonEncode(receipt(amount: 350000, evidence: '350.000,00')),
      ).total,
      350000,
    );
  });
  test('uncertain amounts, missing proof and foreign currency require manual review', () {
    for (final data in [
      receipt(review: true),
      receipt(amount: null, evidence: null),
      receipt(evidence: '500 000'),
      receipt(currency: 'USD'),
      receipt(currency: null),
      receipt(evidence: '606549 / 999999'),
    ]) {
      final r = parseGeminiBill(jsonEncode(data));
      expect(r.total, isNull);
      expect(r.confident, isFalse);
      expect(r.reviewReason, isNotEmpty);
    }
  });
  test('rejects malformed and incorrectly typed model responses', () {
    for (final data in [
      'not json',
      '[]',
      jsonEncode({...receipt(), 'total_vnd': 606549.5}),
      jsonEncode({...receipt(), 'total_vnd': -1}),
      jsonEncode({...receipt(), 'needs_review': 'false'}),
      jsonEncode({...receipt(), 'description': []}),
    ]) {
      expect(() => parseGeminiBill(data), throwsFormatException);
    }
  });
  test('validates image signatures', () {
    expect(imageMimeType(Uint8List.fromList([255, 216, 255])), 'image/jpeg');
    expect(
      imageMimeType(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
      'image/png',
    );
    expect(
      () => imageMimeType(Uint8List.fromList([0, 1, 2])),
      throwsA(isA<BillScanFailure>()),
    );
  });
  test('one image may yield multiple individual receipts', () {
    final r = parseGeminiBatch(
      jsonEncode(
        batch([receipt(), receipt(amount: 120000, evidence: '120.000')]),
      ),
      1,
    );
    expect(r.receipts.map((r) => r.result.total), [606549, 120000]);
    expect(r.receipts.every((r) => r.imageIndex == 0), isTrue);
  });
  test(
    'every photo is accounted for; bad or conflicting source references fail',
    () {
      for (final data in [
        batch([receipt()]),
        batch(
          [
            {...receipt(), 'image_index': 3},
          ],
          unreadable: [1],
        ),
        batch([receipt()], unreadable: [1, 2]),
      ]) {
        expect(
          () => parseGeminiBatch(jsonEncode(data), 2),
          throwsFormatException,
        );
      }
      final result = parseGeminiBatch(
        jsonEncode(batch([receipt()], unreadable: [2])),
        2,
      );
      expect(result.unreadableImages, {1});
      expect(result.receipts.single.imageIndex, 0);
    },
  );
  test('possible duplicates require review even if the model marks the amount certain', () {
    final r = parseGeminiBatch(
      jsonEncode(
        batch([
          {...receipt(), 'review_reason': 'possible_duplicate'},
        ]),
      ),
      1,
    );
    expect(r.receipts.single.result.total, isNull);
    expect(r.receipts.single.result.reviewReason, contains('trùng'));
  });
  group('scanner transport', () {
    late Directory directory;
    late File image;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('bill-scanner-test');
      image = await File('${directory.path}/bill.jpg')
          .writeAsBytes([255, 216, 255]);
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });
    test('sends captured bytes and parses the response', () async {
      var calls = 0;
      final scanner = GeminiBillScanner(
        generate: (images) async {
          calls++;
          expect(images, hasLength(1));
          expect(images.single.bytes, [255, 216, 255]);
          expect(images.single.mimeType, 'image/jpeg');
          return jsonEncode(batch([receipt()]));
        },
      );
      expect(
        (await scanner.scanBatch([image])).receipts.single.result.total,
        606549,
      );
      expect(calls, 1);
    });
    test('multiple photos are sent in exactly one transport call', () async {
      var calls = 0;
      final scanner = GeminiBillScanner(
        generate: (images) async {
          calls++;
          expect(images, hasLength(2));
          return jsonEncode(
            batch([
              receipt(),
              {
                ...receipt(amount: 120000, evidence: '120.000'),
                'image_index': 2,
              },
            ]),
          );
        },
      );
      final result = await scanner.scanBatch([image, image]);
      expect(calls, 1);
      expect(result.receipts.map((r) => r.imageIndex), [0, 1]);
    });
    test('empty and oversized batches do not make a request', () async {
      var calls = 0;
      final scanner = GeminiBillScanner(
        generate: (_) async {
          calls++;
          return null;
        },
      );
      await expectLater(scanner.scanBatch([]), throwsA(isA<BillScanFailure>()));
      await expectLater(
        scanner.scanBatch(List.filled(7, image)),
        throwsA(isA<BillScanFailure>()),
      );
      await image.writeAsBytes([255, 216, 255, ...Uint8List(7 * 1024 * 1024)]);
      await expectLater(
        scanner.scanBatch([image, image]),
        throwsA(isA<BillScanFailure>()),
      );
      expect(calls, 0);
    });
    test('quota and timeout failures produce actionable errors', () async {
      final quota = GeminiBillScanner(
        generate: (_) async =>
            throw FirebaseAIException('429 RESOURCE_EXHAUSTED quota'),
      );
      await expectLater(
        quota.scanBatch([image]),
        throwsA(
          isA<BillScanFailure>().having(
            (e) => e.message,
            'message',
            contains('hết lượt'),
          ),
        ),
      );
      final timeout = GeminiBillScanner(
        timeout: const Duration(milliseconds: 5),
        generate: (_) => Completer<String?>().future,
      );
      await expectLater(
        timeout.scanBatch([image]),
        throwsA(
          isA<BillScanFailure>().having(
            (e) => e.message,
            'message',
            contains('quá lâu'),
          ),
        ),
      );
    });
    test(
      'unverified applications and malformed responses never yield money',
      () async {
        final scanner = GeminiBillScanner(
          generate: (_) async =>
              throw FirebaseAIException('App Check token rejected 403'),
        );
        await expectLater(
          scanner.scanBatch([image]),
          throwsA(
            isA<BillScanFailure>().having(
              (e) => e.message,
              'message',
              contains('xác thực'),
            ),
          ),
        );
        await expectLater(
          GeminiBillScanner(generate: (_) async => 'garbage')
              .scanBatch([image]),
          throwsA(isA<BillScanFailure>()),
        );
      },
    );
    test('oversize input is rejected before an API call', () async {
      await image.writeAsBytes(Uint8List(8 * 1024 * 1024 + 1));
      var called = false;
      await expectLater(
        GeminiBillScanner(
          generate: (_) async {
            called = true;
            return null;
          },
        ).scanBatch([image]),
        throwsA(isA<BillScanFailure>()),
      );
      expect(called, isFalse);
    });
  });
}
