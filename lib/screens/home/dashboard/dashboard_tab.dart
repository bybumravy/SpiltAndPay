import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_providers.dart';
import '../../../ui/app_tabs.dart';
import '../../../ui/app_theme.dart';

import '../../../repositories/debt_repository.dart';
import '../../../repositories/session_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../debt/debt_detail_screen.dart';
import '../../friends/add_friend_screen.dart';
import '../../session/create_session_screen.dart';
import '../../session/session_detail_screen.dart';
import '../widgets/notification_bell_button.dart';
import 'widgets/action_required_section.dart';
import 'widgets/net_balance_card.dart';
import 'widgets/quick_actions_bar.dart';
import 'widgets/recent_activity_section.dart';

/// Tái sử dụng userSessionsProvider đã tích hợp cơ chế auto-retry với backoff từ SessionRepository.
final dashboardSessionsProvider = userSessionsProvider;

class DashboardTab extends ConsumerWidget {
  final void Function(int tabIndex) onNavigateToTab;

  const DashboardTab({super.key, required this.onNavigateToTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    final userProfileAsync = ref.watch(currentUserProvider(user.uid));
    final debtsAsync = ref.watch(userDebtsProvider(user.uid));
    final sessionsAsync = ref.watch(dashboardSessionsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tổng quan'),
        actions: [NotificationBellButton(currentUid: user.uid)],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userDebtsProvider(user.uid));
          ref.invalidate(dashboardSessionsProvider(user.uid));
          ref.invalidate(currentUserProvider(user.uid));
        },
        child: debtsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const AppEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Chưa tải được công nợ',
              ),
              Center(
                child: TextButton.icon(
                  onPressed: () => ref.invalidate(userDebtsProvider(user.uid)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ),
            ],
          ),
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

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              children: [
                userProfileAsync.maybeWhen(
                  data: (profile) {
                    final name = profile?.name.trim();
                    final displayName = name == null || name.isEmpty
                        ? 'Bạn'
                        : name;
                    final avatarUrl = profile?.avatarUrl?.trim();
                    final fallback = InitialAvatar(displayName, radius: 26);
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Xin chào,',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  displayName,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontSize: 23),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          ExcludeSemantics(
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? fallback
                                : ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: avatarUrl,
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) => fallback,
                                      errorWidget: (_, _, _) => fallback,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
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
                      builder: (_) =>
                          DebtDetailScreen(debt: debt, currentUid: user.uid),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 4. Hoạt động gần đây (cách ly lỗi, tự động phục hồi)
                sessionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chưa tải được phiên gần đây',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(dashboardSessionsProvider(user.uid)),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                  data: (sessions) => RecentActivitySection(
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
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}
