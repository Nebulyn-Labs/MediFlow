import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/services/role_guard.dart';

void main() {
  group('authorizedLocation (router decision logic)', () {
    test(
        'a facility user navigating to any /admin/* path is bounced to their '
        'own overview', () {
      expect(
        authorizedLocation(
            uri: '/admin/approvals', role: roleFacilityHead, facilityId: 'f1'),
        '/facility/f1/overview',
      );
      expect(
        authorizedLocation(
            uri: '/admin/audit', role: roleFacilityHead, facilityId: 'f1'),
        '/facility/f1/overview',
      );
    });

    test("facility user cannot open another facility's pages", () {
      expect(
        authorizedLocation(
            uri: '/facility/someone-else/overview',
            role: roleFacilityHead,
            facilityId: 'f1'),
        '/facility/f1/overview',
      );
    });

    test('facility user may browse their own facility routes unchanged', () {
      expect(
        authorizedLocation(
            uri: '/facility/f1/logging',
            role: roleFacilityHead,
            facilityId: 'f1'),
        isNull,
      );
      expect(
        authorizedLocation(
            uri: '/facility/f1/overview',
            role: roleFacilityHead,
            facilityId: 'f1'),
        isNull,
      );
    });

    test('an admin can still reach every /admin/* route', () {
      for (final uri
          in ['/admin/overview', '/admin/approvals', '/admin/audit']) {
        expect(authorizedLocation(uri: uri, role: roleAdmin), isNull,
            reason: uri);
      }
    });

    test('admin is redirected away from facility shells', () {
      expect(
        authorizedLocation(uri: '/facility/f1/chat', role: roleAdmin),
        '/admin/overview',
      );
    });

    test('unknown / missing role bounces protected routes and keeps auth routes',
        () {
      expect(authorizedLocation(uri: '/admin/overview', role: 'ghost'), '/');
      expect(authorizedLocation(uri: '/', role: 'ghost'), isNull);
      expect(authorizedLocation(uri: '/login/admin', role: null), isNull);
    });

    test(
        'facility user with no resolvable facility id never enters a facility '
        "shell — '/facility/null/overview' would redirect-loop forever", () {
      expect(
        authorizedLocation(
            uri: '/admin/overview', role: roleFacilityHead, facilityId: null),
        '/',
      );
      expect(
        authorizedLocation(
            uri: '/facility/x/overview',
            role: roleFacilityHead,
            facilityId: ''),
        '/',
      );
    });

    test('query strings do not bypass the facility id comparison', () {
      expect(
        authorizedLocation(
            uri: '/facility/other/overview?tab=logs',
            role: roleFacilityHead,
            facilityId: 'f1'),
        '/facility/f1/overview',
      );
    });
  });

  group('resolveUserRole (Firestore lookup + cache)', () {
    setUp(clearRoleCache);

    test('reads role and facilityId from users/{uid}', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('u1').set({
        'role': roleFacilityHead,
        'facilityId': 'f1',
      });

      final resolved = await resolveUserRole('u1', firestore: firestore);

      expect(resolved?.role, roleFacilityHead);
      expect(resolved?.facilityId, 'f1');
    });

    test('returns null when the document or the role is missing', () async {
      final firestore = FakeFirebaseFirestore();

      expect(await resolveUserRole('missing', firestore: firestore), isNull);

      await firestore.collection('users').doc('norole').set({'email': 'x'});
      expect(await resolveUserRole('norole', firestore: firestore), isNull);
    });

    test('repeat navigations are served from cache until cleared', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('cache-user').set({
        'role': roleFacilityHead,
        'facilityId': 'f1',
      });

      await resolveUserRole('cache-user', firestore: firestore);

      // Mutate Firestore behind the guard's back: the cached value wins.
      await firestore.collection('users').doc('cache-user').set({
        'role': roleAdmin,
      });
      final cached = await resolveUserRole('cache-user', firestore: firestore);
      expect(cached?.role, roleFacilityHead);

      clearRoleCache('cache-user');
      final fresh = await resolveUserRole('cache-user', firestore: firestore);
      expect(fresh?.role, roleAdmin);
    });
  });
}
