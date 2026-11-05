import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/firebase_providers.dart';
import '../../ui/app_theme.dart';
import '../../ui/app_tabs.dart';
import '../../models/app_notification.dart';
import '../../models/debt.dart';
import '../../repositories/debt_repository.dart';
import '../../repositories/notification_repository.dart';
import '../../repositories/session_repository.dart';
import '../debt/debt_detail_screen.dart';
import '../session/session_detail_screen.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  bool _showHidden = false;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Vui lòng đăng nhập để xem thông báo.')),
      );
    }

    final notificationsAsync = ref.watch(userNotificationsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        bottom: AppTabs(
          controller: _tabs,
          labels: const ['Hiện tại', 'Tất cả'],
          onTap: (index) => setState(() => _showHidden = index == 1),
        ),
        actions: [
          notificationsAsync.maybeWhen(
            data: (notifications) {
              final activeNotifications = notifications
                  .where((n) => !n.isRead || !n.canDismissOnRead)
                  .toList();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.done_all),
                    tooltip: 'Đánh dấu đã đọc',
                    onPressed: () async {
                      final dismissableIds = activeNotifications
                          .where((n) => n.canDismissOnRead)
                          .map((n) => n.id)
                          .toList();
                      await ref
                          .read(readNotificationIdsProvider.notifier)
                          .markAllRead(dismissableIds);
                      await ref
                          .read(notificationRepositoryProvider)
                          .markAllAsRead(user.uid);
                      if (context.mounted) {
                        final hasUnpaidDebt = activeNotifications.any(
                          (n) => !n.canDismissOnRead,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              hasUnpaidDebt
                                  ? 'Đã đọc. Các khoản cần xử lý vẫn được giữ lại.'
                                  : 'Đã đánh dấu đã đọc',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userNotificationsProvider(user.uid));
        },
        child: notificationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const AppEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Chưa tải được thông báo',
              ),
              Center(
                child: TextButton.icon(
                  onPressed: () =>
                      ref.invalidate(userNotificationsProvider(user.uid)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ),
            ],
          ),
          data: (notifications) {
            final activeNotifications = notifications
                .where((n) => !n.isRead || !n.canDismissOnRead)
                .toList();
            final displayList = _showHidden
                ? notifications
                : activeNotifications;
            if (displayList.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  AppEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: notifications.isEmpty
                        ? 'Chưa có thông báo'
                        : 'Không có thông báo mới',
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              itemCount: displayList.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppTheme.line),
              itemBuilder: (context, index) {
                final notif = displayList[index];
                return _NotificationTile(
                  notification: notif,
                  currentUid: user.uid,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  final String currentUid;

  const _NotificationTile({
    required this.notification,
    required this.currentUid,
  });

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.debtReminder:
        return notification.title.contains('cho vay')
            ? Icons.volunteer_activism
            : Icons.forward_to_inbox;
      case NotificationType.sessionClosed:
        return Icons.receipt_long;
      case NotificationType.paymentPending:
        return Icons.payment;
      case NotificationType.paymentConfirmed:
        return Icons.check_circle;
    }
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    // 1. Nếu là thông báo được phép ẩn khi đọc thì đánh dấu đã đọc
    if (notification.canDismissOnRead && !notification.isRead) {
      await ref
          .read(readNotificationIdsProvider.notifier)
          .markRead(notification.id);
      await ref
          .read(notificationRepositoryProvider)
          .markAsRead(currentUid, notification.id);
    }

    if (!context.mounted) return;

    // 2. Điều hướng nếu có targetDebtId
    if (notification.targetDebtId != null) {
      final debts = ref.read(userDebtsProvider(currentUid)).valueOrNull;
      final matchedDebt = debts
          ?.where(
            (d) => Debt.docId(d.userA, d.userB) == notification.targetDebtId,
          )
          .firstOrNull;
      if (matchedDebt != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                DebtDetailScreen(debt: matchedDebt, currentUid: currentUid),
          ),
        );
        return;
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Khoản nợ đã được tất toán hoặc không còn khả dụng.'),
          ),
        );
        return;
      }
    }

    // 3. Điều hướng nếu có targetSessionId
    if (notification.targetSessionId != null) {
      final sessions = ref.read(userSessionsProvider(currentUid)).valueOrNull;
      final matchedSession = sessions
          ?.where((s) => s.sessionId == notification.targetSessionId)
          .firstOrNull;
      if (matchedSession != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(
              session: matchedSession,
              currentUid: currentUid,
            ),
          ),
        );
        return;
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không tìm thấy phiên chia tiền hoặc phiên đã kết thúc.',
            ),
          ),
        );
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('dd/MM · HH:mm').format(notification.createdAt);
    final status = notification.id.startsWith('debt_confirm_')
        ? 'Cần xác nhận'
        : 'Cần thanh toán';
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _handleTap(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.soft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(_getIcon(), color: AppTheme.purple, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: notification.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!notification.isRead) ...[
                          const SizedBox(width: 10),
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.circle,
                              color: AppTheme.purple,
                              size: 7,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.muted,
                        height: 1.5,
                      ),
                    ),
                    if (!notification.canDismissOnRead) ...[
                      const SizedBox(height: 10),
                      Text(
                        status,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: notification.id.startsWith('debt_confirm_')
                              ? AppTheme.purple
                              : AppTheme.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      dateStr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
