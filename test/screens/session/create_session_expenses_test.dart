import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:splitpay/models/app_user.dart';
import 'package:splitpay/models/session.dart';
import 'package:splitpay/models/session_member.dart';
import 'package:splitpay/repositories/session_repository.dart';
import 'package:splitpay/repositories/user_repository.dart';
import 'package:splitpay/screens/session/create_session_screen.dart';

class _FakeSessionRepository implements SessionRepository {
  Session? createdSession;
  List<SessionMember>? createdMembers;
  List<ExpenseInput>? createdExpenses;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<String> createSessionWithExpenses({
    required Session session,
    required List<SessionMember> members,
    required List<ExpenseInput> expenses,
  }) async {
    createdSession = session;
    createdMembers = members;
    createdExpenses = expenses;
    return session.sessionId;
  }
}

class _FakeUserRepository implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<AppUser?> findByUid(String uid) async => null;
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  _FakeSessionRepository? repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null)
          sessionRepositoryProvider.overrideWithValue(repository),
        userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: FLocalizations.localizationsDelegates,
        supportedLocales: FLocalizations.supportedLocales,
        builder: (context, child) =>
            FTheme(data: FTheme.neutral.light.touch, child: child!),
        home: const CreateSessionScreen(creatorUid: 'creator'),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'starts with one Forui expense and adds another with the same action',
    (tester) async {
      await _pumpEditor(tester);

      expect(find.text('Khoản chi 1'), findsOneWidget);
      expect(find.text('Tổng phiên'), findsOneWidget);
      expect(find.text('Thêm khoản chi'), findsOneWidget);
      expect(find.byType(FCard), findsNWidgets(3));
      expect(find.byType(FTextField), findsAtLeastNWidgets(2));

      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();

      expect(find.text('Khoản chi 1'), findsOneWidget);
      expect(find.text('Khoản chi 2'), findsOneWidget);
      expect(find.byType(FCard), findsNWidgets(3));
    },
  );

  testWidgets('submits the complete item list through the atomic create call', (
    tester,
  ) async {
    final repository = _FakeSessionRepository();
    await _pumpEditor(tester, repository: repository);
    await tester.enterText(find.byType(FTextField).at(0), 'Dinner');
    await tester.enterText(find.byType(FTextField).at(1), '12000');
    await tester.scrollUntilVisible(
      find.text('Tạo phiên'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Tạo phiên'));
    await tester.pumpAndSettle();

    expect(repository.createdSession?.totalAmount, 12000);
    expect(repository.createdExpenses, hasLength(1));
    expect(repository.createdExpenses!.single.amount, 12000);
    expect(repository.createdExpenses!.single.payerId, 'creator');
    expect(repository.createdExpenses!.single.participantIds, ['creator']);
  });

  testWidgets(
    'submits multiple expense items with their summed session total',
    (tester) async {
      final repository = _FakeSessionRepository();
      await _pumpEditor(tester, repository: repository);
      await tester.enterText(find.byType(FTextField).at(0), 'Trip');
      await tester.enterText(find.byType(FTextField).at(1), '12000');
      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(FTextField).at(2), '8000');
      await tester.scrollUntilVisible(
        find.text('Tạo phiên'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Tạo phiên'));
      await tester.pumpAndSettle();

      expect(repository.createdSession?.totalAmount, 20000);
      expect(repository.createdExpenses, hasLength(2));
      expect(repository.createdExpenses!.map((expense) => expense.amount), [
        12000,
        8000,
      ]);
    },
  );

  testWidgets('can edit an item description and remove an added item', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await tester.tap(find.text('Thêm khoản chi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Xoá khoản chi').last);
    await tester.pumpAndSettle();
    expect(find.text('Khoản chi 1'), findsOneWidget);
    expect(find.text('Khoản chi 2'), findsNothing);

    await tester.tap(find.text('Chạm để thêm mô tả').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FTextField).last, 'Bữa tối');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Bữa tối'), findsOneWidget);
  });

  testWidgets(
    'new items include current members and allow payer and participant edits',
    (tester) async {
      final repository = _FakeSessionRepository();
      await _pumpEditor(tester, repository: repository);
      await tester.enterText(find.byType(FTextField).at(0), 'Dinner');
      await tester.enterText(find.byType(FTextField).at(1), '9000');
      await tester.scrollUntilVisible(
        find.text('Thành viên (1)'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byIcon(Icons.person_add_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(FTextField).last, 'Alex');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Thêm'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Thêm khoản chi'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(FTextField).last, '3000');
      await tester.scrollUntilVisible(
        find.text('Người trả').last,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Người trả').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Người tham gia').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FSelectTile<String>, 'Alex'));
      await tester.tap(find.text('Lưu người tham gia'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Tạo phiên'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Tạo phiên'));
      await tester.pumpAndSettle();

      expect(repository.createdExpenses, hasLength(2));
      expect(repository.createdExpenses![1].payerId, isNot('creator'));
      expect(repository.createdExpenses![1].participantIds, ['creator']);
    },
  );

  testWidgets('new item snapshots include members added before that item', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await tester.scrollUntilVisible(
      find.text('Thành viên (1)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byIcon(Icons.person_add_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FTextField).last, 'Guest later');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Thêm'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Thêm khoản chi'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Thêm khoản chi'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Người tham gia').last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Người tham gia').last);
    await tester.pumpAndSettle();

    final guestTile = find.widgetWithText(FSelectTile<String>, 'Guest later');
    expect(guestTile, findsOneWidget);
  });
}
