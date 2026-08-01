import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

const useFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

Future<void> setupFirebaseEmulator() async {
  if (useFirebaseEmulator && kDebugMode) {
    try {
      final String host =
          !kIsWeb && Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';

      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);

      debugPrint('Connected to Firebase Emulators at $host');
    } catch (e) {
      debugPrint('Failed to connect to Firebase Emulators: $e');
    }
  }
}
