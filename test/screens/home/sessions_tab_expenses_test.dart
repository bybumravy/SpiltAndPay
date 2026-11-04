import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/firebase_providers.dart';
import 'package:splitpay/models/session.dart';
import 'package:splitpay/models/session_member.dart';
import 'package:splitpay/repositories/session_repository.dart';
import 'package:splitpay/screens/home/sessions_tab.dart';

class _FakeUser implements User {
  @override
  String get uid => 'account-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  @override
  User? get currentUser => _FakeUser();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessionRepository implements SessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _sessions = [
  Session(
    sessionId: 'open-1',
    creatorId: 'account-1',
    title: 'Open dinner',
    totalAmount: 12000,
    splitMode: SessionSplitMode.equal,
    status: SessionStatus.open,
    memberUserIds: const ['account-1', 'account-2'],
    createdAt: DateTime(2026, 11, 3),
  ),
  Session(
    sessionId: 'closed-1',
    creatorId: 'account-1',
    title: 'Closed lunch',
    totalAmount: 8000,
    splitMode: SessionSplitMode.equal,
    status: SessionStatus.closed,
    memberUserIds: const ['account-1'],
    createdAt: DateTime(2026, 11, 2),
  ),
];

void main() {
  testWidgets(
    'filters actual user sessions and displays stored totals/counts',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWithValue(_FakeAuth()),
            sessionRepositoryProvider.overrideWithValue(
              _FakeSessionRepository(),
            ),
            userSessionsProvider('account-1')
                .overrideWith((ref) => Stream.value(_sessions)),
            sessionMembersProvider('open-1').overrideWith(
              (ref) => Stream.value(const [
                SessionMember(
                  memberId: 'account-1',
                  userId: 'account-1',
                  displayName: 'Creator',
                  isGuest: false,
                  amountOwed: 0,
                  status: MemberStatus.self,
                ),
                SessionMember(
                  memberId: 'guest-1',
                  userId: null,
                  displayName: 'Guest',
                  isGuest: true,
                  amountOwed: 0,
                  status: MemberStatus.pending,
                ),
              ]),
            ),
            sessionMembersProvider('closed-1').overrideWith(
              (ref) => Stream.value(const [
                SessionMember(
                  memberId: 'account-1',
                  userId: 'account-1',
                  displayName: 'Creator',
                  isGuest: false,
                  amountOwed: 0,
                  status: MemberStatus.self,
                ),
              ]),
            ),
          ],
          child: const MaterialApp(home: SessionsTab()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open dinner'), findsOneWidget);
      expect(find.text('Closed lunch'), findsOneWidget);
      expect(find.textContaining('12'), findsOneWidget);
      expect(find.textContaining('8'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Đang mở'));
      await tester.pumpAndSettle();
      expect(find.text('Open dinner'), findsOneWidget);
      expect(find.text('Closed lunch'), findsNothing);

      await tester.tap(find.widgetWithText(Tab, 'Đã đóng'));
      await tester.pumpAndSettle();
      expect(find.text('Open dinner'), findsNothing);
      expect(find.text('Closed lunch'), findsOneWidget);
      await tester.drag(find.byType(TabBarView), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Open dinner'), findsOneWidget);
      expect(find.text('Closed lunch'), findsNothing);
    },
  );
}
