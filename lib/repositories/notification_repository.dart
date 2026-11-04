import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/firebase_providers.dart';
import '../core/money.dart';
import '../models/app_notification.dart';
import '../models/debt.dart';
import 'debt_repository.dart';

class NotificationRepository {
  final FirebaseFirestore _db;

  NotificationRepository(this._db);

  CollectionReference<Map<String, dynamic>> _notifCol(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  /// Lắng nghe danh sách thông báo theo thời gian thực (mới nhất lên đầu)
  Stream<List<AppNotification>> watchNotifications(String uid) async* {
    yield <AppNotification>[];
    try {
      await for (final snapshot in _notifCol(
        uid,
      ).orderBy('createdAt', descending: true).limit(50).snapshots()) {
        yield snapshot.docs
            .map((doc) => AppNotification.fromMap(doc.id, doc.data()))
            .toList();
      }
    } catch (error) {
      debugPrint('Notification watch stream error: $error');
    }
  }

  /// Đếm số lượng thông báo chưa đọc
  Stream<int> watchUnreadCount(String uid) async* {
    yield 0;
    try {
      await for (final snapshot in _notifCol(
        uid,
      ).where('isRead', isEqualTo: false).snapshots()) {
        yield snapshot.docs.length;
      }
    } catch (error) {
      debugPrint('Notification unread count error: $error');
    }
  }

  /// Đánh dấu một thông báo đã đọc
  Future<void> markAsRead(String uid, String notificationId) async {
    // Nếu là thông báo thông minh được sinh in-memory từ khoản nợ thì không cần gọi Firestore
    if (notificationId.startsWith('debt_need_pay_') ||
        notificationId.startsWith('debt_lend_')) {
      return;
    }
    try {
      await _notifCol(uid).doc(notificationId).update({'isRead': true});
    } catch (e) {
      debugPrint('markAsRead error: $e');
    }
  }

  /// Đánh dấu tất cả thông báo đã đọc
  Future<void> markAllAsRead(String uid) async {
    try {
      final unread = await _notifCol(uid)
          .where('isRead', isEqualTo: false)
          .get();
      if (unread.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('markAllAsRead error: $e');
    }
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    ref.watch(firestoreProvider),
  );
});

class ReadNotificationIdsNotifier extends StateNotifier<Set<String>> {
  ReadNotificationIdsNotifier() : super(<String>{}) {
    _load();
  }

  static const _key = 'splitpay_read_notification_ids';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    state = list.toSet();
  }

  Future<void> markRead(String notifId) async {
    if (state.contains(notifId)) return;
    final updated = {...state, notifId};
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated.toList());
  }

  Future<void> markAllRead(List<String> notifIds) async {
    final updated = {...state, ...notifIds};
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated.toList());
  }
}

final readNotificationIdsProvider =
    StateNotifierProvider<ReadNotificationIdsNotifier, Set<String>>((ref) {
      return ReadNotificationIdsNotifier();
    });

final userNotificationsProvider = StreamProvider.autoDispose
    .family<List<AppNotification>, String>((ref, uid) {
      final debtsAsync = ref.watch(userDebtsProvider(uid));
      final readIds = ref.watch(readNotificationIdsProvider);

      final debts = debtsAsync.valueOrNull ?? [];
      final smartNotifs = <AppNotification>[];

      for (final debt in debts) {
        final owed = debt.amountOwedBy(uid);
        final debtDocId = Debt.docId(debt.userA, debt.userB);

        if (owed > 0) {
          final notifId = 'debt_need_pay_${debtDocId}_${debt.balance}';
          smartNotifs.add(
            AppNotification(
              id: notifId,
              title: '🔔 Cần thanh toán nợ',
              body:
                  'Bạn đang có khoản nợ ${formatVnd(owed)}. Chạm để mở App Ngân hàng chuyển khoản ngay!',
              type: NotificationType.debtReminder,
              targetDebtId: debtDocId,
              isRead: readIds.contains(notifId),
              createdAt: debt.updatedAt,
            ),
          );
        } else if (owed < 0) {
          final notifId = 'debt_lend_${debtDocId}_${debt.balance}';
          smartNotifs.add(
            AppNotification(
              id: notifId,
              title: '🤝 Khoản tiền cho vay',
              body:
                  'Bạn đang cho bạn bè vay ${formatVnd(owed.abs())}. Chạm để xem chi tiết!',
              type: NotificationType.debtReminder,
              targetDebtId: debtDocId,
              isRead: readIds.contains(notifId),
              createdAt: debt.updatedAt,
            ),
          );
        }
      }

      return ref
          .watch(notificationRepositoryProvider)
          .watchNotifications(uid)
          .map((cloudNotifs) {
            final all = [...smartNotifs, ...cloudNotifs];
            all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return all;
          });
    });

final unreadNotificationCountProvider = Provider.autoDispose
    .family<AsyncValue<int>, String>((ref, uid) {
      final notifsAsync = ref.watch(userNotificationsProvider(uid));
      return notifsAsync.whenData(
        (notifs) => notifs.where((n) => !n.isRead).length,
      );
    });
