import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(
    FirebaseFirestore.instance,
    auth.FirebaseAuth.instance,
    FirebaseMessaging.instance,
  );
});

/// Handles FCM permission requests, token retrieval, persistence on the
/// user's Firestore doc, and keeping that token fresh on rotation.
class NotificationService {
  final FirebaseFirestore _firestore;
  final auth.FirebaseAuth _auth;
  final FirebaseMessaging _messaging;

  StreamSubscription<String>? _refreshSubscription;

  NotificationService(this._firestore, this._auth, this._messaging);

  /// Requests notification permission, fetches the current FCM token, and
  /// persists it on `users/{uid}`. Also subscribes to token refresh so the
  /// stored value stays current when the token rotates.
  ///
  /// Safe to call every time a facility head logs in / signs up — it's a
  /// no-op-safe upsert, not a one-time registration. Any existing refresh
  /// subscription is cancelled first so repeated calls (e.g. login ->
  /// logout -> login again in one app session) don't stack listeners.
  Future<void> registerForPushNotifications() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint(
          'NotificationService: no authenticated user, skipping FCM registration.');
      return;
    }

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('NotificationService: push permission denied by user.');
        return;
      }

      final token = await _messaging.getToken();
      if (token != null) {
        await _saveToken(uid, token);
      }

      // Keep the stored token current when FCM rotates it. Cancel any prior
      // subscription first to avoid stacking duplicate listeners across
      // repeated login/logout cycles in the same app session.
      await _refreshSubscription?.cancel();
      _refreshSubscription = _messaging.onTokenRefresh.listen((newToken) {
        final currentUid = _auth.currentUser?.uid;
        if (currentUid != null) {
          _saveToken(currentUid, newToken);
        }
      });
    } catch (e) {
      debugPrint(
          'NotificationService: failed to register for push notifications: $e');
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      await _firestore.collection('users').doc(uid).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('NotificationService: failed to persist FCM token: $e');
    }
  }

  /// Cancels the token-refresh subscription. Call this on logout.
  void dispose() {
    _refreshSubscription?.cancel();
    _refreshSubscription = null;
  }
}