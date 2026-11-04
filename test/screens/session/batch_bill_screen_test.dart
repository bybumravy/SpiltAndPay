import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/bill_ocr.dart';
import 'package:splitpay/screens/session/batch_bill_screen.dart';

void main() {
  testWidgets(
    'sequential photos stay drafts until reviewed and added together',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var captures = 0;
      var scans = 0;
      List<ScannedExpense>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<List<ScannedExpense>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BatchBillScreen(
                        members: const {'a': 'An', 'b': 'Bình'},
                        payerIds: const {'a', 'b'},
                        initialPayerId: 'a',
                        capture: () async => '/missing-bill-${++captures}.jpg',
                        scan: (_) async => ++scans == 1
                            ? const BillScanResult(
                                total: 120000,
                                confident: true,
                                candidates: [120000],
                              )
                            : const BillScanResult(
                                total: 999999,
                                confident: false,
                                candidates: [999999],
                              ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chụp hoá đơn'));
      await tester.pumpAndSettle();
      expect(find.text('120.000'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text('Chụp tiếp'));
      await tester.pumpAndSettle();
      expect(captures, 2);
      expect(find.text('999.999'), findsNothing);
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
      await tester.tap(find.text('Thêm 2 khoản chi'));
      await tester.pumpAndSettle();
      expect(result!.map((e) => e.amount), [120000, 80000]);
      expect(result!.map((e) => e.description), ['Hoá đơn 1', 'Hoá đơn 2']);
      expect(
        result!.every(
          (e) => e.payerId == 'b' && e.participantIds.join(',') == 'b',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled camera adds nothing; OCR failure permits manual entry and removal',
    (tester) async {
      var captures = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BatchBillScreen(
            members: const {'a': 'An'},
            payerIds: const {'a'},
            initialPayerId: 'a',
            capture: () async => ++captures == 1 ? null : '/missing.jpg',
            scan: (_) async => throw StateError('OCR failed'),
          ),
        ),
      );
      await tester.tap(find.text('Chụp hoá đơn'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm 1 khoản chi'), findsNothing);
      await tester.tap(find.text('Chụp hoá đơn'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Thêm 1 khoản chi'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Bỏ hoá đơn'));
      await tester.pumpAndSettle();
      expect(find.text('Mỗi ảnh một hoá đơn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
