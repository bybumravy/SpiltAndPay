import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase_providers.dart';
import '../../repositories/debt_repository.dart';
import '../../ui/app_theme.dart';

import 'dashboard/dashboard_tab.dart';
import 'debts_tab.dart';
import 'profile_tab.dart';
import 'sessions_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onNavigateToTab(int index) {
    if (index >= 0 && index < 4) {
      setState(() => _currentIndex = index);
    }
  }

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
        children: [
          DashboardTab(onNavigateToTab: _onNavigateToTab),
          const SessionsTab(),
          const DebtsTab(),
          const ProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: AppTheme.purple,
        unselectedItemColor: AppTheme.muted,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (i) => setState(() => _currentIndex = i),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Tổng quan',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Phiên',
          ),
          BottomNavigationBarItem(
            icon: debtIcon(Icons.account_balance_wallet_outlined),
            activeIcon: debtIcon(Icons.account_balance_wallet),
            label: 'Công nợ',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Hồ sơ',
          ),
        ],
      ),
    );
  }
}
