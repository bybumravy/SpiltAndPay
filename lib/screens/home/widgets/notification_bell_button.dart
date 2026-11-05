import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/notification_repository.dart';
import '../../../ui/app_theme.dart';
import '../../notifications/notification_center_screen.dart';

class NotificationBellButton extends ConsumerWidget {
  final String currentUid;

  const NotificationBellButton({super.key, required this.currentUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount =
        ref.watch(unreadNotificationCountProvider(currentUid)).valueOrNull ?? 0;

    return IconButton(
      tooltip: 'Thông báo',
      icon: Badge.count(
        count: unreadCount,
        maxCount: 99,
        isLabelVisible: unreadCount > 0,
        backgroundColor: AppTheme.red,
        textColor: Colors.white,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
      ),
    );
  }
}
