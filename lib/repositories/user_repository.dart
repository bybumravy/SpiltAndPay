import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/firebase_providers.dart';
import '../models/app_user.dart';

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
        .map((snap) => snap.docs
            .map((d) => AppUser.fromMap(d.id, d.data()))
            .toList());
  }

  /// Lưu hoặc cập nhật thông tin bạn bè vào sub-collection contacts.
  Future<void> upsertContact(String ownerUid, AppUser contact) {
    return _col.doc(ownerUid).collection('contacts').doc(contact.uid).set({
      'name': contact.name,
      'avatarUrl': contact.avatarUrl,
      'lastInteractedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Xoá bạn bè khỏi danh bạ.
  Future<void> deleteContact(String ownerUid, String contactUid) {
    return _col.doc(ownerUid).collection('contacts').doc(contactUid).delete();
  }
}

/// Provider cho UserRepository.
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(firestoreProvider));
});

/// Stream profile của user hiện tại theo [uid].
final currentUserProvider =
    StreamProvider.family<AppUser?, String>((ref, uid) {
  return ref.watch(userRepositoryProvider).watchUser(uid);
});

/// Stream danh sách bạn bè gần đây của [uid].
final contactsProvider =
    StreamProvider.family<List<AppUser>, String>((ref, uid) {
  return ref.watch(userRepositoryProvider).watchContacts(uid);
});
