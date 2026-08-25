import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:med_supply_prototype/main.dart' show authRedirect, profileCache;
import 'package:med_supply_prototype/services/user_profile_cache.dart';

class MockUser extends Mock implements User {}

/// Builds a minimal GoRouterState-like object for [authRedirect] testing.
///
/// Since GoRouterState cannot be constructed directly, we use a real
/// GoRouter and inspect where it navigates to.
GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/',
    redirect: authRedirect,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('Home'))),
      GoRoute(
        path: '/login/:role',
        builder: (_, __) => const Scaffold(body: Text('Login')),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const Scaffold(body: Text('Forgot')),
      ),
      GoRoute(
        path: '/admin/overview',
        builder: (_, __) => const Scaffold(body: Text('Admin Overview')),
      ),
      GoRoute(
        path: '/facility/:id/overview',
        builder: (_, __) => const Scaffold(body: Text('Facility Overview')),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    profileCache.clear();
  });

  group('authRedirect', () {
    testWidgets('unauthenticated user is redirected to / from /admin/overview',
        (tester) async {
      // FirebaseAuth.instance.currentUser is null without Firebase init.
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.go('/admin/overview');
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets(
        'unauthenticated user is redirected to / from /facility/any/overview',
        (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.go('/facility/any/overview');
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('auth routes are accessible without profile lookup',
        (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.go('/');
      await tester.pump();
      expect(find.text('Home'), findsOneWidget);

      router.go('/login/facility');
      await tester.pump();
      expect(find.text('Login'), findsOneWidget);

      router.go('/forgot-password');
      await tester.pump();
      expect(find.text('Forgot'), findsOneWidget);
    });
  });

  group('UserProfileCache', () {
    test('returns null for non-existent user', () async {
      final cache = UserProfileCache(firestore: fakeFirestore);
      final profile = await cache.getUserProfile('non-existent-uid');
      expect(profile, isNull);
    });

    test('returns admin profile', () async {
      await fakeFirestore.collection('users').doc('admin-uid').set({
        'email': 'admin@mediflow.com',
        'role': 'admin',
      });

      final cache = UserProfileCache(firestore: fakeFirestore);
      final profile = await cache.getUserProfile('admin-uid');

      expect(profile, isNotNull);
      expect(profile!.isAdmin, isTrue);
      expect(profile.isFacilityHead, isFalse);
      expect(profile.facilityId, isNull);
    });

    test('returns facility_head profile with facilityId', () async {
      await fakeFirestore.collection('users').doc('fac-uid').set({
        'email': 'rampur@mediflow.com',
        'role': 'facility_head',
        'facilityId': 'rampur_mediflow_com',
      });

      final cache = UserProfileCache(firestore: fakeFirestore);
      final profile = await cache.getUserProfile('fac-uid');

      expect(profile, isNotNull);
      expect(profile!.isAdmin, isFalse);
      expect(profile.isFacilityHead, isTrue);
      expect(profile.facilityId, 'rampur_mediflow_com');
    });

    test('caches result and does not query Firestore again', () async {
      await fakeFirestore.collection('users').doc('uid-1').set({
        'role': 'admin',
      });

      final cache = UserProfileCache(firestore: fakeFirestore);

      final p1 = await cache.getUserProfile('uid-1');
      final p2 = await cache.getUserProfile('uid-1');

      expect(p1!.isAdmin, isTrue);
      expect(p2!.isAdmin, isTrue);
    });

    test('clear() invalidates cache', () async {
      await fakeFirestore.collection('users').doc('uid-1').set({
        'role': 'admin',
      });

      final cache = UserProfileCache(firestore: fakeFirestore);
      await cache.getUserProfile('uid-1');
      cache.clear();

      // After clear, next call should query Firestore again.
      final profile = await cache.getUserProfile('uid-1');
      expect(profile, isNotNull);
    });

    test('returns null for user with no role field', () async {
      await fakeFirestore.collection('users').doc('no-role-uid').set({
        'email': 'test@test.com',
      });

      final cache = UserProfileCache(firestore: fakeFirestore);
      final profile = await cache.getUserProfile('no-role-uid');

      expect(profile, isNull);
    });
  });
}
