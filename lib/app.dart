import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/firebase_providers.dart';
import 'repositories/user_repository.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        useMaterial3: true,
      ),
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
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Lỗi: $e')),
      ),
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
            body: Center(child: Text('Lỗi tải profile: $e')),
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

