import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'core/firebase_providers.dart';
import 'repositories/auth_repository.dart';
import 'repositories/debt_repository.dart';
import 'repositories/guest_obligation_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/user_repository.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/qr_onboarding_screen.dart';
import 'screens/home/home_screen.dart';
import 'ui/app_theme.dart';

/// Root widget của ứng dụng.
class SplitPayApp extends StatelessWidget {
  const SplitPayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Split & Pay',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        ...FLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
        ref.invalidate(friendRequestsProvider);
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
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Lỗi tải profile: $e',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        ref.invalidate(currentUserProvider(user.uid));
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          ref.read(authRepositoryProvider).signOut(),
                      child: const Text('Đăng xuất'),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
