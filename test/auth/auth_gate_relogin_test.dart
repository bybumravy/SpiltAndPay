import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/app.dart';
import 'package:splitpay/core/firebase_providers.dart';
import 'package:splitpay/repositories/user_repository.dart';
import 'package:splitpay/repositories/session_repository.dart';
import 'package:splitpay/screens/auth/qr_onboarding_screen.dart';

class _User implements User {
  @override
  String get uid => 'same-account';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'relogin recreates cached permission failures for the same account',
    (tester) async {
      final auth = StreamController<User?>();
      var denied = true;
      var profileSubscriptions = 0;
      var sessionSubscriptions = 0;
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => auth.stream),
          currentUserProvider('same-account').overrideWith((ref) {
            profileSubscriptions++;
            return denied
                ? Stream.error(StateError('permission-denied'))
                : Stream.value(null);
          }),
          userSessionsProvider('same-account').overrideWith((ref) {
            sessionSubscriptions++;
            return denied
                ? Stream.error(StateError('permission-denied'))
                : Stream.value([]);
          }),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(auth.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SplitPayApp(),
        ),
      );
      auth.add(_User());
      await tester.pumpAndSettle();
      expect(find.textContaining('Lỗi tải profile'), findsOneWidget);
      await expectLater(
        container.read(userSessionsProvider('same-account').future),
        throwsStateError,
      );
      final oldProfileCount = profileSubscriptions;
      auth.add(null);
      await tester.pumpAndSettle();
      denied = false;
      auth.add(_User());
      await tester.pumpAndSettle();
      expect(find.byType(QrOnboardingScreen), findsOneWidget);
      expect(find.textContaining('Lỗi tải profile'), findsNothing);
      expect(profileSubscriptions, greaterThan(oldProfileCount));
      expect(
        await container.read(userSessionsProvider('same-account').future),
        isEmpty,
      );
      expect(sessionSubscriptions, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
