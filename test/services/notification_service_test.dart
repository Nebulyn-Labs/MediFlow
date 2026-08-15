import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:med_supply_prototype/services/notification_service.dart';

class MockFirebaseAuth extends Mock implements auth.FirebaseAuth {}

class MockUser extends Mock implements auth.User {}

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockNotificationSettings extends Mock implements NotificationSettings {}

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late MockFirebaseMessaging mockMessaging;
  late NotificationService service;

  const uid = 'user_123';
  const token = 'fcm_token_abc';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockMessaging = MockFirebaseMessaging();

    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.uid).thenReturn(uid);

    service = NotificationService(firestore, mockAuth, mockMessaging);
  });

  test(
      'persists fcmToken on users/{uid} via merge when permission is granted',
      () async {
    final settings = MockNotificationSettings();
    when(() => settings.authorizationStatus)
        .thenReturn(AuthorizationStatus.authorized);
    when(() => mockMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        )).thenAnswer((_) async => settings);
    when(() => mockMessaging.getToken()).thenAnswer((_) async => token);
    when(() => mockMessaging.onTokenRefresh)
        .thenAnswer((_) => const Stream.empty());

    // Pre-seed the doc with fields written at signup, to prove the token
    // write is a merge and doesn't clobber them.
    await firestore.collection('users').doc(uid).set({
      'role': 'facility_head',
      'facilityId': 'f1',
    });

    await service.registerForPushNotifications();

    final doc = await firestore.collection('users').doc(uid).get();
    expect(doc.data()?['fcmToken'], token);
    expect(doc.data()?['role'], 'facility_head');
    expect(doc.data()?['facilityId'], 'f1');
  });

  test('does not write a token when permission is denied', () async {
    final settings = MockNotificationSettings();
    when(() => settings.authorizationStatus)
        .thenReturn(AuthorizationStatus.denied);
    when(() => mockMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        )).thenAnswer((_) async => settings);

    await firestore.collection('users').doc(uid).set({'role': 'facility_head'});

    await service.registerForPushNotifications();

    final doc = await firestore.collection('users').doc(uid).get();
    expect(doc.data()?.containsKey('fcmToken'), false);
    verifyNever(() => mockMessaging.getToken());
  });

  test('does nothing when there is no authenticated user', () async {
    when(() => mockAuth.currentUser).thenReturn(null);

    await service.registerForPushNotifications();

    verifyNever(() => mockMessaging.requestPermission(
          alert: any(named: 'alert'),
          badge: any(named: 'badge'),
          sound: any(named: 'sound'),
        ));
  });

  test('updates stored token when onTokenRefresh fires', () async {
    final settings = MockNotificationSettings();
    when(() => settings.authorizationStatus)
        .thenReturn(AuthorizationStatus.authorized);
    when(() => mockMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        )).thenAnswer((_) async => settings);
    when(() => mockMessaging.getToken()).thenAnswer((_) async => token);

    const refreshedToken = 'fcm_token_refreshed';
    when(() => mockMessaging.onTokenRefresh)
        .thenAnswer((_) => Stream.value(refreshedToken));

    await firestore.collection('users').doc(uid).set({'role': 'facility_head'});

    await service.registerForPushNotifications();
    // Let the onTokenRefresh stream's single event flush.
    await Future<void>.delayed(Duration.zero);

    final doc = await firestore.collection('users').doc(uid).get();
    expect(doc.data()?['fcmToken'], refreshedToken);
  });
}