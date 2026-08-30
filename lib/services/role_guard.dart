import 'package:cloud_firestore/cloud_firestore.dart';

/// How long a resolved role/facility pair may be reused by the router before
/// the next navigation re-reads `users/{uid}` from Firestore.
const Duration roleCacheTtl = Duration(minutes: 5);

/// Role assigned to admin accounts (`firebase_service.dart` seed data and
/// `firestore.rules` both use these exact strings).
const String roleAdmin = 'admin';

/// Role stored on facility accounts at sign-up.
const String roleFacilityHead = 'facility_head';

/// A user's authorization attributes as resolved from `users/{uid}`.
class ResolvedUserRole {
  const ResolvedUserRole({
    required this.role,
    this.facilityId,
    required this.fetchedAt,
  });

  final String role;
  final String? facilityId;
  final DateTime fetchedAt;
}

final Map<String, ResolvedUserRole> _roleCache = <String, ResolvedUserRole>{};

/// Drops cached roles — one user's entry when [uid] is given, otherwise all.
void clearRoleCache([String? uid]) {
  if (uid == null) {
    _roleCache.clear();
  } else {
    _roleCache.remove(uid);
  }
}

/// Reads the signed-in user's `role` (and `facilityId`) from Firestore,
/// serving repeat navigations from an in-memory cache so the lookup does not
/// run from scratch on every navigation.
///
/// Returns null when the document is missing or carries no usable role, or
/// when Firestore throws; callers must treat that as "no resolvable role"
/// and fail closed.
Future<ResolvedUserRole?> resolveUserRole(
  String uid, {
  FirebaseFirestore? firestore,
}) async {
  final store = firestore ?? FirebaseFirestore.instance;

  final cached = _roleCache[uid];
  if (cached != null &&
      DateTime.now().difference(cached.fetchedAt) < roleCacheTtl) {
    return cached;
  }

  try {
    final doc = await store.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final dynamic roleValue = doc.data()?['role'];
    if (roleValue is! String || roleValue.isEmpty) return null;
    final dynamic facilityValue = doc.data()?['facilityId'];
    final resolved = ResolvedUserRole(
      role: roleValue,
      facilityId: facilityValue is String ? facilityValue : null,
      fetchedAt: DateTime.now(),
    );
    _roleCache[uid] = resolved;
    return resolved;
  } catch (_) {
    return null;
  }
}

/// Pure routing decision for an authenticated user: returns the location to
/// redirect to, or null to allow [uri] through unchanged.
///
/// Deliberately free of Firebase dependencies so every acceptance criterion
/// of issue #318 can be unit-tested directly.
String? authorizedLocation({
  required String uri,
  required String? role,
  required String? facilityId,
}) {
  final path = uri.isEmpty ? '/' : uri;
  final isAuthRoute = path == '/' ||
      path.startsWith('/login') ||
      path.startsWith('/forgot-password');

  // No resolvable role: auth routes stay reachable, everything else bounces.
  if (role == null || role.isEmpty) {
    return isAuthRoute ? null : '/';
  }

  // Inspect the second segment rather than a bare startsWith('/admin') so a
  // hypothetical '/administrative' prefix cannot slip through. Route params
  // arrive percent-encoded, hence decodeComponent before comparing ids.
  final segments = path.split('/');
  final first = segments.length > 1 ? segments[1] : '';
  final requestedFacilityId =
      segments.length > 2 && segments[2].isNotEmpty
          ? Uri.decodeComponent(segments[2])
          : null;

  switch (role) {
    case roleAdmin:
      // Admins own every /admin/* route. Facility shells bounce back to the
      // admin overview on purpose — nothing in the app links admins into
      // /facility/* today (raised on PR #401; trivially relaxed later).
      return first == 'facility' ? '/admin/overview' : null;

    case roleFacilityHead:
      // A facility account without a resolvable facility id has no safe home:
      // interpolating it into '/facility/null/overview' would re-enter this
      // guard forever (redirect-loop flagged on PR #401/#458). Fail closed.
      if (facilityId == null || facilityId.isEmpty) {
        return isAuthRoute ? null : '/';
      }
      if (first == 'admin') {
        return '/facility/$facilityId/overview';
      }
      if (first == 'facility' && requestedFacilityId != facilityId) {
        return '/facility/$facilityId/overview';
      }
      return null;

    default:
      return isAuthRoute ? null : '/';
  }
}
