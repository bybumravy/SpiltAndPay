import 'package:shared_preferences/shared_preferences.dart';

import '../models/debt.dart';
import 'debt_repository.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/firebase_providers.dart';
import '../core/money.dart';
import '../models/app_notification.dart';

class NotificationRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  NotificationRepository(this._db, [FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  String get _currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn cần đăng nhập để thao tác.');
    return uid;
  }

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

  /// Gửi lời nhắc trả tiền (Manual Nudge) với kiểm tra giới hạn tần suất 24h.
  /// Trả về nội dung lời nhắc để chia sẻ qua Zalo/Messenger/SMS.
  Future<String> sendDebtReminder({
    required String debtId,
    required String targetUid,
    required String creditorName,
    required String debtorName,
    required int amount,
    required String style, // 'funny', 'polite', 'gentle'
  }) async {
    final currentUserId = _currentUid;
    final debtRef = _db.collection('debts').doc(debtId);

    // Xây dựng nội dung tin nhắn theo phong cách đã chọn
    final String body;
    final String formattedAmt = formatVnd(amount);

    switch (style) {
      case 'funny':
        body =
            'Hôm nay trời nhẹ lên cao, mình buồn không hiểu vì sao... bạn chưa chuyển $formattedAmt? 🥺';
        break;
      case 'gentle':
        body =
            'Ghé SplitPay thanh toán nốt $formattedAmt cho $creditorName để sổ nợ về 0 nào bạn ơi! ☕';
        break;
      case 'polite':
      default:
        body =
            '$creditorName gửi lời nhắc thanh toán khoản nợ $formattedAmt. Bạn tranh thủ chuyển nhé! 🔔';
        break;
    }

    final debtSnap = await debtRef.get();
    final debtData = debtSnap.data();
    if (debtData == null) throw StateError('Không tìm thấy khoản nợ.');

    // Kiểm tra người gọi phải là chủ nợ
    final balance = (debtData['balance'] as num).toInt();
    final isUserA = currentUserId == debtData['userA'];
    final iAmCreditor = isUserA ? balance < 0 : balance > 0;
    if (!iAmCreditor) {
      throw StateError('Chỉ chủ nợ mới có quyền gửi lời nhắc.');
    }

    // Kiểm tra Rate Limit 24h (từ Firestore hoặc local SharedPreferences)
    final lastReminder = debtData['lastReminderAt'];
    DateTime? lastDate;
    if (lastReminder is Timestamp) {
      lastDate = lastReminder.toDate();
    } else {
      final prefs = await SharedPreferences.getInstance();
      final localMs = prefs.getInt('splitpay_last_reminder_$debtId');
      if (localMs != null) {
        lastDate = DateTime.fromMillisecondsSinceEpoch(localMs);
      }
    }
    if (lastDate != null) {
      final diff = DateTime.now().difference(lastDate);
      if (diff.inHours < 24) {
        final hoursLeft = 24 - diff.inHours;
        throw StateError(
          'Bạn vừa gửi lời nhắc gần đây. Vui lòng thử lại sau $hoursLeft giờ.',
        );
      }
    }

    // 1. Cố gắng ghi thông báo vào hộp thư Cloud Firestore (nếu rules trên cloud cho phép)
    try {
      final newNotifId = const Uuid().v4();
      final notifRef = _db
          .collection('users')
          .doc(targetUid)
          .collection('notifications')
          .doc(newNotifId);

      await notifRef.set({
        'title': '💌 Lời nhắc thanh toán từ $creditorName',
        'body': body,
        'type': NotificationType.debtReminder.name,
        'targetDebtId': debtId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      try {
        await debtRef.update({'lastReminderAt': FieldValue.serverTimestamp()});
      } catch (e) {
        debugPrint('sendDebtReminder: update lastReminderAt skipped ($e)');
      }
    } catch (e) {
      debugPrint('sendDebtReminder: cloud notification write skipped ($e)');
    }

    // 2. Ghi mốc thời gian nhắc nợ cục bộ (SharedPreferences) để bảo đảm rate limit 24h
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'splitpay_last_reminder_$debtId',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}

    return body;
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    ref.watch(firestoreProvider),
    ref.watch(authProvider),
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
          final notifId = 'debt_need_pay_$debtDocId';
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
          final notifId = 'debt_lend_$debtDocId';
          smartNotifs.add(
            AppNotification(
              id: notifId,
              title: '🤝 Khoản tiền cho vay',
              body:
                  'Bạn đang cho bạn bè vay ${formatVnd(owed.abs())}. Chạm để xem chi tiết hoặc gửi lời nhắc!',
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
