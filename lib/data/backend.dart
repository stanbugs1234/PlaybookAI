import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Whether Firebase initialized. When false the app runs fully on-device.
abstract final class Backend {
  static bool firebaseReady = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase unavailable, running in local mode: $e');
      firebaseReady = false;
    }
  }
}
