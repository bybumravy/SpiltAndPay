import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/firebase_providers.dart';
import '../models/app_user.dart';
import '../models/friend_request.dart';

/// Thao tác đọc/ghi profile người dùng trong Firestore.
class UserRepository {
  final FirebaseFirestore _db;

  UserRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('users');

  /// Stream profile của [uid]. Emit null nếu document chưa tồn tại.
  Stream<AppUser?> watchUser(String uid) {
    return _col.doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return AppUser.fromMap(snap.id, snap.data()!);
    });
  }

  /// Tạo hoặc cập nhật (merge) profile.
  Future<void> saveUser(AppUser user) {
    return _col.doc(user.uid).set(user.toMap(), SetOptions(merge: true));
  }

  /// Cập nhật chỉ URL ảnh QR.
  Future<void> updateQrImageUrl(String uid, String url) {
    return _col.doc(uid).update({'qrImageUrl': url});
  }

  /// Tìm user theo uid (dùng khi quét QR).
  Future<AppUser?> findByUid(String uid) async {
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    return AppUser.fromMap(snap.id, snap.data()!);
  }

  /// Tìm user theo email chính xác (dùng emailLower để không phân biệt hoa thường).
  Future<AppUser?> findByEmail(String email) async {
    final snap = await _col
        .where('emailLower', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return AppUser.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  /// Danh sách bạn bè gần đây của [uid].
  Stream<List<AppUser>> watchContacts(String uid) {
    return _col
        .doc(uid)
        .collection('contacts')
        .orderBy('lastInteractedAt', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<FriendRequest>> watchFriendRequests(String uid) => _db
      .collection('friendRequests')
      .where('participants', arrayContains: uid)
      .snapshots()
      .map(
        (snap) => snap.docs
            .where((d) => d.data()['status'] == 'pending')
            .map((d) => FriendRequest.fromMap(d.id, d.data()))
            .toList(),
      );

  Future<void> sendFriendRequest(String senderId, AppUser recipient) async {
    if (senderId == recipient.uid) {
      throw StateError('Không thể kết bạn với chính mình.');
    }
    final sender = await findByUid(senderId);
    if (sender == null) throw StateError('Không tải được hồ sơ của bạn.');
    final target = _db
        .collection('friendRequests')
        .doc('${senderId}_${recipient.uid}');
    final reverse = _db
        .collection('friendRequests')
        .doc('${recipient.uid}_$senderId');
    await _db.runTransaction((tx) async {
      final existing = await tx.get(target);
      final incoming = await tx.get(reverse);
      final contact = await tx.get(
        _col.doc(senderId).collection('contacts').doc(recipient.uid),
      );
      if (contact.exists) throw StateError('Hai bạn đã là bạn bè.');
      if (existing.exists) throw StateError('Bạn đã gửi lời mời.');
      if (incoming.exists) {
        throw StateError(
          'Người này đã gửi lời mời cho bạn. Hãy mở Lời mời để xác nhận.',
        );
      }
      tx.set(target, {
        'senderId': senderId,
        'recipientId': recipient.uid,
        'participants': [senderId, recipient.uid],
        'senderName': sender.name,
        'recipientName': recipient.name,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> acceptFriendRequest(FriendRequest request) async {
    final sender = await findByUid(request.senderId);
    final recipient = await findByUid(request.recipientId);
    if (sender == null || recipient == null) {
      throw StateError('Không tìm thấy hồ sơ.');
    }
    final target = _db.collection('friendRequests').doc(request.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(target);
      if (snap.data()?['status'] != 'pending') {
        throw StateError('Lời mời không còn hiệu lực.');
      }
      tx.update(target, {'status': 'accepted'});
      for (final pair in [
        (request.senderId, recipient),
        (request.recipientId, sender),
      ]) {
        tx.set(_col.doc(pair.$1).collection('contacts').doc(pair.$2.uid), {
          ...pair.$2.toMap(),
          'lastInteractedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> dismissFriendRequest(FriendRequest request) =>
      _db.collection('friendRequests').doc(request.id).delete();

  Future<void> deleteContact(String ownerUid, String contactUid) async {
    final batch = _db.batch();
    batch.delete(_col.doc(ownerUid).collection('contacts').doc(contactUid));
    batch.delete(_col.doc(contactUid).collection('contacts').doc(ownerUid));
    batch.delete(
      _db.collection('friendRequests').doc('${ownerUid}_$contactUid'),
    );
    batch.delete(
      _db.collection('friendRequests').doc('${contactUid}_$ownerUid'),
    );
    await batch.commit();
  }
}

/// Provider cho UserRepository.
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(firestoreProvider));
});

/// Stream profile của user hiện tại theo [uid].
final currentUserProvider = StreamProvider.family<AppUser?, String>((ref, uid) {
  return ref.watch(userRepositoryProvider).watchUser(uid);
});

/// Stream danh sách bạn bè gần đây của [uid].
final contactsProvider = StreamProvider.family<List<AppUser>, String>((
  ref,
  uid,
) {
  return ref.watch(userRepositoryProvider).watchContacts(uid);
});

final friendRequestsProvider =
    StreamProvider.family<List<FriendRequest>, String>((ref, uid) {
      return ref.watch(userRepositoryProvider).watchFriendRequests(uid);
    });
