import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
export 'package:firebase_core/firebase_core.dart'; // Export it for main.dart
import 'package:firebase_app_check/firebase_app_check.dart';
import 'dart:io' show Platform;
import '../firebase_options.dart';

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

Future<void> initializeFirebaseServices() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
    // Cannot proceed with App Check if Firebase core initialization fails
    return;
  }

  try {
    // Requirements:
    // - Android Debug -> AndroidProvider.debug
    // - Android Release -> AndroidProvider.playIntegrity
    final androidProvider =
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity;

    // The site key can be supplied during build via:
    // --dart-define=RECAPTCHA_SITE_KEY=your_actual_key
    const webRecaptchaSiteKey =
        String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue: '');

    if (kIsWeb) {
      if (webRecaptchaSiteKey.isNotEmpty) {
        await FirebaseAppCheck.instance.activate(
          webProvider: ReCaptchaV3Provider(webRecaptchaSiteKey),
          androidProvider: androidProvider,
        );
        debugPrint('Firebase App Check activated (Web with reCAPTCHA)');
      } else {
        debugPrint(
            'WARNING: Firebase App Check skipped on Web because RECAPTCHA_SITE_KEY is empty. '
            'Please provide a valid site key to enable it.');
      }
    } else {
      await FirebaseAppCheck.instance.activate(
        androidProvider: androidProvider,
      );
      debugPrint(
          "Firebase App Check activated (Android: ${kDebugMode ? 'Debug' : 'Play Integrity'})");
    }
  } catch (e) {
    // Requirement: If App Check activation fails, log the error using debugPrint() and allow the application to continue running
    debugPrint('Firebase App Check initialization error: $e');
  }
}
