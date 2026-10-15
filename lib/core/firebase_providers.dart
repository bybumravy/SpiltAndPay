import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cung cấp instance FirebaseAuth dùng chung toàn app.
final authProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Cung cấp instance Firestore dùng chung toàn app.
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

/// Stream trạng thái đăng nhập. Emit User khi đã đăng nhập, null khi chưa.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authProvider).authStateChanges();
});
