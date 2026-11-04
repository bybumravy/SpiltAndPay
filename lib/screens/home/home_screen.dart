import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase_providers.dart';
import '../../repositories/debt_repository.dart';
import '../../ui/app_theme.dart';

import 'sessions_tab.dart';
import 'debts_tab.dart';
import 'profile_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authProvider).currentUser?.uid;
    final count = uid == null
        ? 0
        : (ref.watch(userDebtsProvider(uid)).valueOrNull ?? [])
              .where((debt) => debt.amountOwedBy(uid) > 0)
              .map((debt) => debt.userA == uid ? debt.userB : debt.userA)
              .toSet()
              .length;
    Widget debtIcon(IconData icon) => Badge.count(
      count: count,
      maxCount: 99,
      isLabelVisible: count > 0,
      backgroundColor: AppTheme.red,
      textColor: Colors.white,
      child: Icon(icon),
    );
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [SessionsTab(), DebtsTab(), ProfileTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Phiên',
          ),
          NavigationDestination(
            icon: debtIcon(Icons.account_balance_wallet_outlined),
            selectedIcon: debtIcon(Icons.account_balance_wallet),
            label: 'Công nợ',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Hồ sơ',
          ),
        ],
      ),
    );
  }
}
