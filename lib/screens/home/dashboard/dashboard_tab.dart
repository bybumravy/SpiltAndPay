import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_providers.dart';
import '../../../models/debt.dart';
import '../../../repositories/debt_repository.dart';
import '../../../repositories/session_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../debt/debt_detail_screen.dart';
import '../../friends/add_friend_screen.dart';
import '../../session/create_session_screen.dart';
import '../../session/session_detail_screen.dart';
import 'widgets/action_required_section.dart';
import 'widgets/net_balance_card.dart';
import 'widgets/quick_actions_bar.dart';
import 'widgets/recent_activity_section.dart';

class DashboardTab extends ConsumerWidget {
  final void Function(int tabIndex) onNavigateToTab;

  const DashboardTab({
    super.key,
    required this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    final userProfileAsync = ref.watch(currentUserProvider(user.uid));
    final debtsAsync = ref.watch(userDebtsProvider(user.uid));
    final sessionsAsync = ref.watch(userSessionsProvider(user.uid));

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: userProfileAsync.maybeWhen(
          data: (profile) => Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: profile?.avatarUrl != null
                    ? CachedNetworkImageProvider(profile!.avatarUrl!)
                    : null,
                child: profile?.avatarUrl == null
                    ? Text(
                        (profile?.name.isNotEmpty ?? false)
                            ? profile!.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xin chào, ${profile?.name ?? "Bạn"} 👋',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tổng quan tài chính',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          orElse: () => const Text('Tổng quan tài chính'),
        ),
      ),
      body: debtsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi tải dữ liệu nợ: $e')),
        data: (debts) {
          // Tính tổng nợ và tổng được nợ
          var totalOwed = 0;
          var totalReceivable = 0;

          for (final d in debts) {
            final amount = d.amountOwedBy(user.uid);
            if (amount > 0) {
              totalOwed += amount;
            } else if (amount < 0) {
              totalReceivable += amount.abs();
            }
          }

          return sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Lỗi tải phiên: $e')),
            data: (sessions) {
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // 1. Thẻ Cán cân tài chính ròng
                  NetBalanceCard(
                    totalOwed: totalOwed,
                    totalReceivable: totalReceivable,
                  ),
                  const SizedBox(height: 16),

                  // 2. Thao tác nhanh
                  QuickActionsBar(
                    onNewSession: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateSessionScreen(creatorUid: user.uid),
                      ),
                    ),
                    onAddFriend: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddFriendScreen(currentUid: user.uid),
                      ),
                    ),
                    onNavigateToDebts: () => onNavigateToTab(2), // Tab Công nợ
                  ),
                  const SizedBox(height: 20),

                  // 3. Cần xử lý ngay
                  ActionRequiredSection(
                    debts: debts,
                    currentUid: user.uid,
                    onSelectDebt: (debt) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DebtDetailScreen(
                          debt: debt,
                          currentUid: user.uid,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. Hoạt động gần đây
                  RecentActivitySection(
                    sessions: sessions,
                    currentUid: user.uid,
                    onSelectSession: (session) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SessionDetailScreen(
                          session: session,
                          currentUid: user.uid,
                        ),
                      ),
                    ),
                    onViewAllSessions: () => onNavigateToTab(1), // Tab Phiên
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
