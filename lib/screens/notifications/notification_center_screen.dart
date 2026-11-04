import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/firebase_providers.dart';
import '../../models/app_notification.dart';
import '../../models/debt.dart';
import '../../repositories/debt_repository.dart';
import '../../repositories/notification_repository.dart';
import '../../repositories/session_repository.dart';
import '../debt/debt_detail_screen.dart';
import '../session/session_detail_screen.dart';

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Vui lòng đăng nhập để xem thông báo.')),
      );
    }

    final notificationsAsync = ref.watch(userNotificationsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hộp thư thông báo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Đánh dấu tất cả đã đọc',
            onPressed: () async {
              final notifs =
                  ref.read(userNotificationsProvider(user.uid)).valueOrNull ??
                  [];
              final ids = notifs.map((n) => n.id).toList();
              await ref
                  .read(readNotificationIdsProvider.notifier)
                  .markAllRead(ids);
              await ref
                  .read(notificationRepositoryProvider)
                  .markAllAsRead(user.uid);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã đánh dấu tất cả đã đọc.')),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userNotificationsProvider(user.uid));
        },
        child: notificationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Bạn chưa có thông báo nào.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString().contains('permission-denied')
                        ? 'Lưu ý: Cần Publish firestore.rules lên Firebase Console của nhóm để đồng bộ realtime.'
                        : 'Lỗi: $e',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          data: (notifications) {
            if (notifications.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Bạn chưa có thông báo nào.',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final notif = notifications[index];
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

  Color _getColor() {
    switch (notification.type) {
      case NotificationType.debtReminder:
        return notification.title.contains('cho vay')
            ? Colors.teal.shade700
            : Colors.orange.shade700;
      case NotificationType.sessionClosed:
        return Colors.blue.shade700;
      case NotificationType.paymentPending:
        return Colors.purple.shade700;
      case NotificationType.paymentConfirmed:
        return Colors.green.shade700;
    }
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    // 1. Đánh dấu đã đọc
    if (!notification.isRead) {
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
    final iconColor = _getColor();
    final dateStr = DateFormat('dd/MM HH:mm').format(notification.createdAt);

    return ListTile(
      tileColor: notification.isRead
          ? null
          : theme.colorScheme.primaryContainer.withAlpha(25),
      leading: CircleAvatar(
        backgroundColor: iconColor.withAlpha(30),
        child: Icon(_getIcon(), color: iconColor, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              notification.title,
              style: TextStyle(
                fontWeight: notification.isRead
                    ? FontWeight.w600
                    : FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          if (!notification.isRead)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            notification.body,
            style: TextStyle(
              fontSize: 12,
              color: notification.isRead
                  ? theme.colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
      onTap: () => _handleTap(context, ref),
    );
  }
}
