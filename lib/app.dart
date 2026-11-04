import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'core/firebase_providers.dart';
import 'ui/app_theme.dart';
import 'repositories/user_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/debt_repository.dart';
import 'repositories/guest_obligation_repository.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/qr_onboarding_screen.dart';
import 'screens/home/home_screen.dart';

/// Root widget của ứng dụng.
class SplitPayApp extends StatelessWidget {
  const SplitPayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Split & Pay',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      builder: (context, child) => FTheme(data: AppTheme.forui, child: child!),
      theme: AppTheme.material,
      home: const AuthGate(),
    );
  }
}

/// Điều phối màn hình dựa theo trạng thái đăng nhập và onboarding QR.
///
/// Luồng:
///   chưa đăng nhập → LoginScreen
///   đã đăng nhập nhưng chưa có QR → QrOnboardingScreen
///   đã đăng nhập và có QR → HomeScreen
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authStateProvider, (previous, next) {
      // Firestore listeners terminated on sign-out retain their last error.
      // Recreate every account-scoped stream after a new authenticated session.
      if (next.valueOrNull != null &&
          previous?.valueOrNull?.uid != next.valueOrNull?.uid) {
        ref.invalidate(currentUserProvider);
        ref.invalidate(contactsProvider);
        ref.invalidate(userSessionsProvider);
        ref.invalidate(sessionMembersProvider);
        ref.invalidate(sessionExpensesProvider);
        ref.invalidate(sessionGuestObligationsProvider);
        ref.invalidate(userDebtsProvider);
        ref.invalidate(paymentsProvider);
      }
    });
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Lỗi: $e'))),
      data: (user) {
        if (user == null) {
          // Chưa đăng nhập.
          return const LoginScreen();
        }

        // Đã đăng nhập — kiểm tra xem đã upload QR chưa.
        final userAsync = ref.watch(currentUserProvider(user.uid));
        return userAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) =>
              Scaffold(body: Center(child: Text('Lỗi tải profile: $e'))),
          data: (appUser) {
            if (appUser == null || !appUser.hasQr) {
              // Chưa upload ảnh QR thanh toán.
              return QrOnboardingScreen(uid: user.uid);
            }
            // Đủ điều kiện vào app.
            return const HomeScreen();
          },
        );
      },
    );
  }
}
