import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:splitpay/models/app_user.dart';
import 'package:splitpay/repositories/user_repository.dart';
import 'package:splitpay/screens/session/create_session_screen.dart';
import 'package:splitpay/models/expense.dart';
import 'package:splitpay/models/session.dart';
import 'package:splitpay/models/session_member.dart';
import 'package:splitpay/repositories/guest_obligation_repository.dart';
import 'package:splitpay/repositories/session_repository.dart';
import 'package:splitpay/screens/session/session_detail_screen.dart';

final _session = Session(
  sessionId: 'session-1',
  creatorId: 'creator',
  title: 'Dinner',
  totalAmount: 1000,
  splitMode: SessionSplitMode.equal,
  status: SessionStatus.open,
  memberUserIds: ['creator'],
  createdAt: DateTime(2026, 11, 3),
);

const _expense = Expense(
  expenseId: 'expense-1',
  description: 'Meal',
  amount: 1000,
  payerId: 'creator',
  participantIds: ['creator'],
  shares: {'creator': 1000},
  sequence: 1,
);

const _creator = SessionMember(
  memberId: 'creator',
  userId: 'creator',
  displayName: 'Creator',
  isGuest: false,
  amountOwed: 1000,
  amountPaid: 0,
  status: MemberStatus.self,
);

class _FakeSessionRepository implements SessionRepository {
  String? savedTitle;
  List<ExpenseInput>? savedExpenses;

  @override
  Future<void> saveOpenSession({
    required Session originalSession,
    required List<SessionMember> originalMembers,
    required List<Expense> originalExpenses,
    required String title,
    required List<SessionMember> members,
    required List<ExpenseInput> expenses,
  }) async {
    savedTitle = title;
    savedExpenses = expenses;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUsers implements UserRepository {
  @override
  Future<AppUser?> findByUid(String uid) async =>
      AppUser(uid: uid, name: 'Creator', email: 'creator@example.com');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGuestObligationRepository implements GuestObligationRepository {
  final List<String> collectedIds = [];

  @override
  Future<void> markCollected({
    required String sessionId,
    required String obligationId,
  }) async {
    collectedIds.add(obligationId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'expanded expenses fit narrow screens with long names and many shares',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final members = List.generate(
        12,
        (i) => SessionMember(
          memberId: 'member-$i',
          userId: 'member-$i',
          displayName: 'Thành viên có tên rất dài số $i',
          isGuest: false,
          amountOwed: 100000,
          status: MemberStatus.ledger,
        ),
      );
      final expense = Expense(
        expenseId: 'long',
        description: 'Ăn tối và đồ uống cùng cả nhóm sau chuyến đi',
        amount: 1200000,
        payerId: members.first.memberId,
        participantIds: members.map((m) => m.memberId).toList(),
        shares: {for (final member in members) member.memberId: 100000},
        sequence: 1,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSessionsProvider('creator')
                .overrideWith((ref) => Stream.value([_session])),
            sessionMembersProvider('session-1')
                .overrideWith((ref) => Stream.value(members)),
            sessionExpensesProvider('session-1')
                .overrideWith((ref) => Stream.value([expense])),
            sessionGuestObligationsProvider('session-1')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: SessionDetailScreen(session: _session, currentUid: 'creator'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-section-heading')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chia cho 12 người'), findsOneWidget);
      expect(find.text(expense.description), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'member load errors can be retried without reopening the session',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSessionsProvider('creator')
                .overrideWith((ref) => Stream.value([_session])),
            sessionMembersProvider('session-1').overrideWith((ref) {
              attempts++;
              return attempts == 1
                  ? Stream<List<SessionMember>>.error(
                      StateError('permission-denied'),
                    )
                  : Stream.value([_creator]);
            }),
            sessionExpensesProvider('session-1')
                .overrideWith((ref) => Stream.value([_expense])),
            sessionGuestObligationsProvider('session-1')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: SessionDetailScreen(session: _session, currentUid: 'creator'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Không tải được thành viên'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Creator'), findsWidgets);
      expect(find.textContaining('Không tải được thành viên'), findsNothing);
    },
  );

  testWidgets(
    'guest obligations show status and collect only for actual payer',
    (tester) async {
      final repository = _FakeGuestObligationRepository();
      const otherMember = SessionMember(
        memberId: 'payer-2',
        userId: 'payer-2',
        displayName: 'Payer Two',
        isGuest: false,
        amountOwed: 0,
        status: MemberStatus.pending,
      );
      const guest = SessionMember(
        memberId: 'guest-1',
        userId: null,
        displayName: 'Guest One',
        isGuest: true,
        amountOwed: 0,
        status: MemberStatus.pending,
      );
      const obligation = GuestObligation(
        obligationId: 'claim-1',
        sessionId: 'session-1',
        expenseId: 'expense-1',
        payerId: 'payer-2',
        guestMemberId: 'guest-1',
        amount: 500,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            guestObligationRepositoryProvider.overrideWithValue(repository),
            sessionRepositoryProvider.overrideWithValue(
              _FakeSessionRepository(),
            ),
            sessionMembersProvider('session-1').overrideWith(
              (ref) => Stream.value([_creator, otherMember, guest]),
            ),
            sessionExpensesProvider('session-1')
                .overrideWith((ref) => Stream.value([_expense])),
            sessionGuestObligationsProvider('session-1')
                .overrideWith((ref) => Stream.value([obligation])),
            userSessionsProvider('creator')
                .overrideWith((ref) => Stream.value([_session])),
          ],
          child: MaterialApp(
            home: SessionDetailScreen(session: _session, currentUid: 'creator'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Khoản khách nợ'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Khoản khách nợ'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Khoản khách nợ'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Khoản khách nợ')),
        alignment: 0.1,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khoản khách nợ'));
      await tester.pumpAndSettle();
      expect(
        find.text('Người thu: Payer Two · 500đ · Chưa thu'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Đã thu'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            guestObligationRepositoryProvider.overrideWithValue(repository),
            sessionRepositoryProvider.overrideWithValue(
              _FakeSessionRepository(),
            ),
            sessionMembersProvider('session-1').overrideWith(
              (ref) => Stream.value([_creator, otherMember, guest]),
            ),
            sessionExpensesProvider('session-1')
                .overrideWith((ref) => Stream.value([_expense])),
            sessionGuestObligationsProvider('session-1')
                .overrideWith((ref) => Stream.value([obligation])),
            userSessionsProvider('payer-2')
                .overrideWith((ref) => Stream.value([_session])),
          ],
          child: MaterialApp(
            home: SessionDetailScreen(session: _session, currentUid: 'payer-2'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Khoản khách nợ'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Khoản khách nợ')),
        alignment: 0.1,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khoản khách nợ'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Đã thu'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Đã thu'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Đã thu'));
      await tester.pumpAndSettle();
      expect(repository.collectedIds, ['claim-1']);
    },
  );

  testWidgets(
    'only creator sees close and close requires explicit confirmation',
    (tester) async {
      final repository = _FakeSessionRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(repository),
            sessionMembersProvider('session-1')
                .overrideWith((ref) => Stream.value([_creator])),
            sessionExpensesProvider('session-1')
                .overrideWith((ref) => Stream.value([_expense])),
            sessionGuestObligationsProvider('session-1')
                .overrideWith((ref) => Stream.value(const [])),
            userSessionsProvider('creator')
                .overrideWith((ref) => Stream.value([_session])),
          ],
          child: MaterialApp(
            home: SessionDetailScreen(session: _session, currentUid: 'creator'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đóng phiên'), findsOneWidget);
      await tester.tap(find.text('Đóng phiên'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Không thể hoàn tác.'), findsOneWidget);
      expect(find.text('Đóng'), findsOneWidget);
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(repository),
            sessionMembersProvider('session-1')
                .overrideWith((ref) => Stream.value([_creator])),
            sessionExpensesProvider('session-1')
                .overrideWith((ref) => Stream.value([_expense])),
            sessionGuestObligationsProvider('session-1')
                .overrideWith((ref) => Stream.value(const [])),
            userSessionsProvider('creator')
                .overrideWith((ref) => Stream.value([_session])),
          ],
          child: MaterialApp(
            home: SessionDetailScreen(
              session: _session,
              currentUid: 'not-creator',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đóng phiên'), findsNothing);
    },
  );

  testWidgets('detail has one editor entry and no duplicate mutations', (
    tester,
  ) async {
    final repository = _FakeSessionRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userRepositoryProvider.overrideWithValue(_FakeUsers()),
          sessionRepositoryProvider.overrideWithValue(repository),
          sessionMembersProvider('session-1')
              .overrideWith((ref) => Stream.value([_creator])),
          sessionExpensesProvider('session-1')
              .overrideWith((ref) => Stream.value([_expense])),
          sessionGuestObligationsProvider('session-1')
              .overrideWith((ref) => Stream.value(const [])),
          userSessionsProvider('creator')
              .overrideWith((ref) => Stream.value([_session])),
        ],
        child: MaterialApp(
          localizationsDelegates: FLocalizations.localizationsDelegates,
          supportedLocales: FLocalizations.supportedLocales,
          home: SessionDetailScreen(session: _session, currentUid: 'creator'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('expense-section-heading')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chỉnh sửa phiên'), findsOneWidget);
    expect(find.byTooltip('Sửa khoản chi'), findsNothing);
    expect(find.byTooltip('Xoá khoản chi'), findsNothing);
    expect(find.byTooltip('Thêm khoản chi'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Xoá phiên'), findsOneWidget);
    expect(find.text('Chỉnh sửa toàn bộ phiên'), findsNothing);
    expect(find.text('Sửa tên phiên'), findsNothing);
    await tester.tapAt(const Offset(10, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chỉnh sửa phiên'));
    await tester.pumpAndSettle();
    final editor = tester.widget<CreateSessionScreen>(
      find.byType(CreateSessionScreen),
    );
    expect(editor.initialExpenses.single.expenseId, _expense.expenseId);
    expect(editor.initialMembers.single.memberId, _creator.memberId);
    await tester.enterText(find.byType(FTextField).at(0), 'Renamed dinner');
    await tester.enterText(find.byType(FTextField).at(1), 'Meal changed');
    await tester.enterText(find.byType(FTextField).at(2), '1500');
    // Leaving the editor discards the draft without mutating the session.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repository.savedTitle, isNull);
    expect(
      tester
          .widget<SessionDetailScreen>(find.byType(SessionDetailScreen))
          .session
          .title,
      'Dinner',
    );
    await tester.tap(find.text('Chỉnh sửa phiên'));
    await tester.pumpAndSettle();
    expect(find.text('Meal'), findsOneWidget);
    await tester.enterText(find.byType(FTextField).at(0), 'Renamed dinner');
    await tester.enterText(find.byType(FTextField).at(1), 'Meal changed');
    await tester.enterText(find.byType(FTextField).at(2), '1500');
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(repository.savedTitle, 'Renamed dinner');
    expect(repository.savedExpenses!.single.expenseId, _expense.expenseId);
    expect(repository.savedExpenses!.single.description, 'Meal changed');
    expect(repository.savedExpenses!.single.amount, 1500);
    expect(find.byType(CreateSessionScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('closed sessions and other members have no editing entry', (
    tester,
  ) async {
    for (final state in [SessionStatus.open, SessionStatus.closed]) {
      final currentUid = state == SessionStatus.open ? 'other' : 'creator';
      final session = Session(
        sessionId: 'session-1',
        creatorId: 'creator',
        title: 'Dinner',
        totalAmount: 1000,
        splitMode: SessionSplitMode.equal,
        status: state,
        memberUserIds: ['creator', 'other'],
        createdAt: _session.createdAt,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSessionsProvider(currentUid)
                .overrideWith((ref) => Stream.value([session])),
            sessionMembersProvider('session-1')
                .overrideWith((ref) => Stream.value([_creator])),
            sessionExpensesProvider('session-1')
                .overrideWith((ref) => Stream.value([_expense])),
            sessionGuestObligationsProvider('session-1')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: SessionDetailScreen(session: session, currentUid: currentUid),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chỉnh sửa phiên'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.byTooltip('Thêm khoản chi'), findsNothing);
      expect(find.byTooltip('Sửa khoản chi'), findsNothing);
      expect(find.text('Meal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
