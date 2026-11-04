import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  final List<ExpenseInput> addedExpenses = [];
  final List<String> deletedExpenses = [];
  final List<({String expenseId, ExpenseInput expense})> updatedExpenses = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<String> addExpense({
    required String sessionId,
    required ExpenseInput expense,
  }) async {
    addedExpenses.add(expense);
    return expense.expenseId;
  }

  @override
  Future<void> updateExpense({
    required String sessionId,
    required String expenseId,
    required ExpenseInput expense,
  }) async {
    updatedExpenses.add((expenseId: expenseId, expense: expense));
  }

  @override
  Future<void> deleteExpense({
    required String sessionId,
    required String expenseId,
  }) async {
    deletedExpenses.add(expenseId);
  }
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
      await tester.tap(find.text('Các khoản chi'));
      await tester.pumpAndSettle();
      expect(find.text('Chia cho 12 người'), findsOneWidget);
      expect(find.text(expense.description), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );


  testWidgets(
    'adding an expense defaults payer to creator and participants to all members',
    (tester) async {
      final repository = _FakeSessionRepository();
      const otherMember = SessionMember(
        memberId: 'member-2',
        userId: 'member-2',
        displayName: 'Member Two',
        isGuest: false,
        amountOwed: 0,
        status: MemberStatus.pending,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(repository),
            sessionMembersProvider('session-1')
                .overrideWith((ref) => Stream.value([_creator, otherMember])),
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
      await tester.tap(find.text('Các khoản chi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Drinks');
      await tester.enterText(find.byType(TextField).at(1), '500');
      await tester.tap(find.text('Thêm').last);
      await tester.pumpAndSettle();

      expect(repository.addedExpenses, hasLength(1));
      expect(repository.addedExpenses.single.payerId, 'creator');
      expect(repository.addedExpenses.single.participantIds, [
        'creator',
        'member-2',
      ]);
      expect(repository.addedExpenses.single.amount, 500);
    },
  );

  testWidgets(
    'adding an expense allows payer selection and participant deselection',
    (tester) async {
      final repository = _FakeSessionRepository();
      const otherMember = SessionMember(
        memberId: 'member-2',
        userId: 'member-2',
        displayName: 'Member Two',
        isGuest: false,
        amountOwed: 0,
        status: MemberStatus.pending,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(repository),
            sessionMembersProvider('session-1')
                .overrideWith((ref) => Stream.value([_creator, otherMember])),
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
      await tester.tap(find.text('Các khoản chi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm khoản chi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Drinks');
      await tester.enterText(find.byType(TextField).at(1), '500');
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member Two').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm').last);
      await tester.pumpAndSettle();

      expect(repository.addedExpenses.single.payerId, 'member-2');
      expect(repository.addedExpenses.single.participantIds, ['member-2']);
    },
  );

  testWidgets('editing an expense saves payer, participants and amount', (
    tester,
  ) async {
    final repository = _FakeSessionRepository();
    const otherMember = SessionMember(
      memberId: 'member-2',
      userId: 'member-2',
      displayName: 'Member Two',
      isGuest: false,
      amountOwed: 0,
      status: MemberStatus.pending,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repository),
          sessionMembersProvider('session-1')
              .overrideWith((ref) => Stream.value([_creator, otherMember])),
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
    await tester.tap(find.text('Các khoản chi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sửa khoản chi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Updated meal');
    await tester.enterText(find.byType(TextField).at(1), '1500');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(repository.updatedExpenses, hasLength(1));
    final input = repository.updatedExpenses.single.expense;
    expect(input.description, 'Updated meal');
    expect(input.amount, 1500);
    expect(input.payerId, 'creator');
    expect(input.participantIds, ['creator']);
  });

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
      expect(find.text('Khoản khách nợ'), findsOneWidget);
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
      await tester.tap(find.text('Khoản khách nợ'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Đã thu'), findsOneWidget);
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

  testWidgets('creator can manage expenses only while session is open', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(_FakeSessionRepository()),
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
    await tester.tap(find.text('Các khoản chi'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sửa khoản chi'), findsOneWidget);
    expect(find.byTooltip('Xoá khoản chi'), findsOneWidget);
    expect(find.text('Thêm khoản chi'), findsOneWidget);
  });
}
