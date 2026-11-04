import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/bill_ocr.dart';
import 'package:splitpay/core/gemini_bill_scanner.dart';
import 'package:splitpay/screens/session/batch_bill_screen.dart';

const known = BillScanResult(
  total: 120000,
  confident: true,
  candidates: [],
  description: 'Ăn tối',
);
const unknown = BillScanResult(total: null, confident: false, candidates: []);
Future<void> pumpFlow(
  WidgetTester tester, {
  required Future<String?> Function() capture,
  required Future<BillBatchResult> Function(List<File>) scan,
  void Function(List<ScannedExpense>?)? onResult,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.push<List<ScannedExpense>>(
                context,
                MaterialPageRoute(
                  builder: (_) => BatchBillScreen(
                    members: const {'a': 'An', 'b': 'Bình'},
                    payerIds: const {'a', 'b'},
                    initialPayerId: 'a',
                    capture: capture,
                    scan: scan,
                  ),
                ),
              );
              onResult?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'capture a whole batch locally; one explicit request returns editable expenses',
    (tester) async {
      var photos = 0;
      var requests = 0;
      List<ScannedExpense>? saved;
      await pumpFlow(
        tester,
        capture: () async => '/bill-${++photos}.jpg',
        scan: (images) async {
          requests++;
          expect(images.map((f) => f.path), ['/bill-1.jpg', '/bill-2.jpg']);
          return const BillBatchResult(
            receipts: [BillReceipt(0, known), BillReceipt(1, unknown)],
          );
        },
        onResult: (r) => saved = r,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Chụp hoá đơn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chụp tiếp'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Đọc 2 ảnh'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Thêm 2 khoản chi'),
            )
            .onPressed,
        isNull,
      );
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bình').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'An'));
      await tester.pumpAndSettle();
      final amount = find.widgetWithText(TextField, 'Số tiền (VND)').last;
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '80000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem 2 ảnh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem kết quả'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      await tester.tap(find.text('Thêm 2 khoản chi'));
      await tester.pumpAndSettle();
      expect(saved!.map((r) => r.amount), [120000, 80000]);
      expect(
        saved!.every(
          (r) => r.payerId == 'b' && r.participantIds.join(',') == 'b',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('one photo can produce several separate receipts', (
    tester,
  ) async {
    await pumpFlow(
      tester,
      capture: () async => '/bill.jpg',
      scan: (_) async => const BillBatchResult(
        receipts: [BillReceipt(0, known), BillReceipt(0, known)],
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Chụp hoá đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đọc 1 ảnh'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm 2 khoản chi'), findsOneWidget);
    expect(find.text('Ảnh 1'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'cancel or remove photos sends nothing; failed read preserves photos for explicit retry',
    (tester) async {
      var photos = 0;
      var requests = 0;
      await pumpFlow(
        tester,
        capture: () async => ++photos == 1 ? null : '/bill-$photos.jpg',
        scan: (_) async {
          requests++;
          throw const BillScanFailure('Mất mạng');
        },
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Chụp hoá đơn'));
      await tester.pumpAndSettle();
      expect(find.text('Đọc 1 ảnh'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Chụp hoá đơn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chụp tiếp'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bỏ ảnh').first);
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.tap(find.text('Đọc 1 ảnh'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Mất mạng'), findsOneWidget);
      expect(find.text('Ảnh 1'), findsOneWidget);
      await tester.tap(find.text('Đọc 1 ảnh'));
      await tester.pumpAndSettle();
      expect(requests, 2);
      await tester.tap(find.text('Nhập tay'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm 1 khoản chi'), findsOneWidget);
      expect(requests, 2);
    },
  );
  testWidgets(
    'busy read blocks duplicate requests and changing photos requires a new explicit read',
    (tester) async {
      var photos = 0;
      var requests = 0;
      final response = Completer<BillBatchResult>();
      await pumpFlow(
        tester,
        capture: () async => '/bill-${++photos}.jpg',
        scan: (_) {
          requests++;
          return response.future;
        },
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Chụp hoá đơn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đọc 1 ảnh'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Đang đọc hoá đơn…'),
            )
            .onPressed,
        isNull,
      );
      expect(requests, 1);
      response.complete(
        const BillBatchResult(receipts: [BillReceipt(0, known)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem 1 ảnh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chụp tiếp'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      await tester.tap(find.text('Đọc 2 ảnh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Đọc 2 ảnh'), findsOneWidget);
    },
  );
}
