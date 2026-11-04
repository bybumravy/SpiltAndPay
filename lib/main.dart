import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Firebase với cấu hình tự động sinh bởi FlutterFire CLI.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
  );
  if (kDebugMode) {
    // Triggers creation of the local debug secret; registration happens in Console.
    unawaited(
      FirebaseAppCheck.instance.getToken().then<void>(
        (_) {},
        onError: (Object _) {
          debugPrint(
            'App Check: register this device debug token in Firebase Console.',
          );
        },
      ),
    );
  }

  runApp(
    // ProviderScope là bắt buộc để Riverpod hoạt động.
    const ProviderScope(child: SplitPayApp()),
  );
}
