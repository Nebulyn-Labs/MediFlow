import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../firebase_options.dart';

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
          "Firebase App Check activated (Android: \${kDebugMode ? 'Debug' : 'Play Integrity'})");
    }
  } catch (e) {
    // Requirement: If App Check activation fails, log the error using debugPrint() and allow the application to continue running
    debugPrint('Firebase App Check initialization error: $e');
  }
}
