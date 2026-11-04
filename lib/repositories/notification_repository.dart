import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  Stream<List<AppNotification>> watchNotifications(String uid) {
    return _notifCol(uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AppNotification.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Đếm số lượng thông báo chưa đọc
  Stream<int> watchUnreadCount(String uid) {
    return _notifCol(uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Đánh dấu một thông báo đã đọc
  Future<void> markAsRead(String uid, String notificationId) async {
    await _notifCol(uid).doc(notificationId).update({'isRead': true});
  }

  /// Đánh dấu tất cả thông báo đã đọc
  Future<void> markAllAsRead(String uid) async {
    final unread = await _notifCol(uid).where('isRead', isEqualTo: false).get();
    if (unread.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Gửi lời nhắc trả tiền (Manual Nudge) với kiểm tra giới hạn tần suất 24h
  Future<void> sendDebtReminder({
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
        body = 'Hôm nay trời nhẹ lên cao, mình buồn không hiểu vì sao... bạn chưa chuyển $formattedAmt? 🥺';
        break;
      case 'gentle':
        body = 'Ghé SplitPay thanh toán nốt $formattedAmt cho $creditorName để sổ nợ về 0 nào bạn ơi! ☕';
        break;
      case 'polite':
      default:
        body = '$creditorName gửi lời nhắc thanh toán khoản nợ $formattedAmt. Bạn tranh thủ chuyển nhé! 🔔';
        break;
    }

    await _db.runTransaction((tx) async {
      final debtSnap = await tx.get(debtRef);
      final debtData = debtSnap.data();
      if (debtData == null) throw StateError('Không tìm thấy khoản nợ.');

      // Kiểm tra người gọi phải là chủ nợ
      final balance = (debtData['balance'] as num).toInt();
      final isUserA = currentUserId == debtData['userA'];
      final iAmCreditor = isUserA ? balance < 0 : balance > 0;
      if (!iAmCreditor) {
        throw StateError('Chỉ chủ nợ mới có quyền gửi lời nhắc.');
      }

      // Kiểm tra Rate Limit 24h
      final lastReminder = debtData['lastReminderAt'];
      if (lastReminder is Timestamp) {
        final lastDate = lastReminder.toDate();
        final diff = DateTime.now().difference(lastDate);
        if (diff.inHours < 24) {
          final hoursLeft = 24 - diff.inHours;
          throw StateError('Bạn vừa gửi lời nhắc gần đây. Vui lòng thử lại sau $hoursLeft giờ.');
        }
      }

      // 1. Ghi thông báo vào hộp thư của con nợ
      final newNotifId = const Uuid().v4();
      final notifRef = _db.collection('users').doc(targetUid).collection('notifications').doc(newNotifId);

      tx.set(notifRef, {
        'title': '💌 Lời nhắc thanh toán từ $creditorName',
        'body': body,
        'type': NotificationType.debtReminder.name,
        'targetDebtId': debtId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Cập nhật mốc thời gian nhắc nợ trên document nợ
      tx.update(debtRef, {
        'lastReminderAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    ref.watch(firestoreProvider),
    ref.watch(authProvider),
  );
});

final userNotificationsProvider =
    StreamProvider.family<List<AppNotification>, String>((ref, uid) {
  return ref.watch(notificationRepositoryProvider).watchNotifications(uid);
});

final unreadNotificationCountProvider =
    StreamProvider.family<int, String>((ref, uid) {
  return ref.watch(notificationRepositoryProvider).watchUnreadCount(uid);
});
