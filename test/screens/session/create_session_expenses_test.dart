import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:splitpay/app.dart';
import 'package:splitpay/core/firebase_providers.dart';
import 'package:splitpay/models/app_user.dart';
import 'package:splitpay/models/session.dart';
import 'package:splitpay/models/expense.dart';
import 'package:splitpay/models/session_member.dart';
import 'package:splitpay/repositories/session_repository.dart';
import 'package:splitpay/repositories/user_repository.dart';
import 'package:splitpay/screens/session/create_session_screen.dart';

class _FakeSessionRepository implements SessionRepository {
  Session? createdSession;
  List<SessionMember>? createdMembers;
  List<ExpenseInput>? createdExpenses;
  String? savedTitle;
  Session? originalSession;

  @override
  Future<void> saveOpenSession({
    required Session originalSession,
    required List<SessionMember> originalMembers,
    required List<Expense> originalExpenses,
    required String title,
    required List<SessionMember> members,
    required List<ExpenseInput> expenses,
  }) async {
    this.originalSession = originalSession;
    savedTitle = title;
    createdMembers = members;
    createdExpenses = expenses;
  }

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
  CreateSessionScreen screen = const CreateSessionScreen(creatorUid: 'creator'),
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        if (repository != null)
          sessionRepositoryProvider.overrideWithValue(repository),
        userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
      ],
      child: const SplitPayApp(),
    ),
  );
  await tester.pumpAndSettle();
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .push(MaterialPageRoute<void>(builder: (_) => screen));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'legacy migration preserves known advances and warns before save',
    (tester) async {
      final repo = _FakeSessionRepository();
      final session = Session(
        sessionId: 'legacy',
        creatorId: 'creator',
        title: 'Old',
        totalAmount: 300,
        splitMode: SessionSplitMode.custom,
        status: SessionStatus.open,
        memberUserIds: ['creator', 'friend'],
        createdAt: DateTime(2026),
      );
      const creator = SessionMember(
        memberId: 'creator',
        userId: 'creator',
        displayName: 'Creator',
        isGuest: false,
        amountOwed: 100,
        amountPaid: 200,
        status: MemberStatus.self,
      );
      const friend = SessionMember(
        memberId: 'friend',
        userId: 'friend',
        displayName: 'Friend',
        isGuest: false,
        amountOwed: 200,
        amountPaid: 100,
        status: MemberStatus.ledger,
      );
      await _pumpEditor(
        tester,
        repository: repo,
        screen: CreateSessionScreen(
          creatorUid: 'creator',
          initialSession: session,
          initialMembers: const [creator, friend],
        ),
      );
      expect(find.textContaining('Phiên cũ sẽ chuyển'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Lưu thay đổi'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Lưu thay đổi'));
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(repo.createdExpenses!.map((e) => (e.payerId, e.amount)), [
        ('creator', 200),
        ('friend', 100),
      ]);
    },
  );

  testWidgets(
    'full editor preserves item ids and saves updated title amount and members',
    (tester) async {
      final repo = _FakeSessionRepository();
      final session = Session(
        sessionId: 'existing',
        creatorId: 'creator',
        title: 'Old title',
        totalAmount: 12000,
        splitMode: SessionSplitMode.equal,
        status: SessionStatus.open,
        memberUserIds: ['creator'],
        createdAt: DateTime(2026),
      );
      const creator = SessionMember(
        memberId: 'creator',
        userId: 'creator',
        displayName: 'Creator',
        isGuest: false,
        amountOwed: 6000,
        status: MemberStatus.self,
      );
      const guest = SessionMember(
        memberId: 'guest',
        userId: null,
        displayName: 'Alex',
        isGuest: true,
        amountOwed: 6000,
        status: MemberStatus.pending,
      );
      const expense = Expense(
        expenseId: 'keep-id',
        description: 'Meal',
        amount: 12000,
        payerId: 'creator',
        participantIds: ['creator', 'guest'],
        shares: {'creator': 6000, 'guest': 6000},
      );
      await _pumpEditor(
        tester,
        repository: repo,
        screen: CreateSessionScreen(
          creatorUid: 'creator',
          initialSession: session,
          initialMembers: const [creator, guest],
          initialExpenses: const [expense],
        ),
      );
      expect(find.text('12.000'), findsOneWidget);
      await tester.enterText(find.byType(FTextField).at(0), 'New title');
      await tester.enterText(find.byType(FTextField).at(1), 'Meal edited');
      await tester.enterText(find.byType(FTextField).at(2), '24000');
      await tester.tap(find.byTooltip('Sửa thành viên'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá khỏi phiên'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lưu thay đổi'));
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(repo.originalSession?.sessionId, 'existing');
      expect(repo.savedTitle, 'New title');
      expect(repo.createdMembers!.map((m) => m.memberId), ['creator']);
      expect(repo.createdExpenses!.single.expenseId, 'keep-id');
      expect(repo.createdExpenses!.single.amount, 24000);
      expect(repo.createdExpenses!.single.description, 'Meal edited');
      expect(repo.createdExpenses!.single.participantIds, ['creator']);
      expect(repo.createdSession, isNull);
    },
  );

  testWidgets(
    'starts with one Forui expense and adds another with the same action',
    (tester) async {
      await _pumpEditor(tester);

      expect(find.text('Khoản chi 1'), findsOneWidget);
      expect(find.text('Thêm khoản chi'), findsOneWidget);
      expect(find.byType(FCard), findsNWidgets(3));
      expect(find.byType(FTextField), findsAtLeastNWidgets(2));

      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();

      expect(find.text('Khoản chi 1'), findsOneWidget);
      expect(find.text('Khoản chi 2'), findsOneWidget);
      expect(find.byType(FCard), findsNWidgets(4));
    },
  );

  testWidgets('submits the complete item list through the atomic create call', (
    tester,
  ) async {
    final repository = _FakeSessionRepository();
    await _pumpEditor(tester, repository: repository);
    await tester.enterText(find.byType(FTextField).at(0), 'Dinner');
    await tester.enterText(find.byType(FTextField).at(1), 'Bữa tối');
    await tester.enterText(find.byType(FTextField).at(2), '12000');
    expect(find.text('12.000'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tạo phiên'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Tạo phiên'));
    await tester.tap(find.text('Tạo phiên'));
    await tester.pumpAndSettle();

    expect(repository.createdSession?.totalAmount, 12000);
    expect(repository.createdExpenses, hasLength(1));
    expect(repository.createdExpenses!.single.amount, 12000);
    expect(repository.createdExpenses!.single.description, 'Bữa tối');
    expect(repository.createdExpenses!.single.payerId, 'creator');
    expect(repository.createdExpenses!.single.participantIds, ['creator']);
  });

  testWidgets(
    'submits multiple expense items with their summed session total',
    (tester) async {
      final repository = _FakeSessionRepository();
      await _pumpEditor(tester, repository: repository);
      await tester.enterText(find.byType(FTextField).at(0), 'Trip');
      await tester.enterText(find.byType(FTextField).at(2), '12000');
      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(FTextField).at(4), '8000');
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

    await tester.enterText(find.byType(FTextField).at(1), 'Bữa tối');
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);

    expect(find.text('Bữa tối'), findsOneWidget);
  });

  testWidgets(
    'new items include current members and allow payer and participant edits',
    (tester) async {
      final repository = _FakeSessionRepository();
      await _pumpEditor(tester, repository: repository);
      await tester.enterText(find.byType(FTextField).at(0), 'Dinner');
      await tester.enterText(find.byType(FTextField).at(2), '9000');
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
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Alex'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Bạn (người tạo)').last);
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
      expect(repository.createdExpenses![1].payerId, 'creator');
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
