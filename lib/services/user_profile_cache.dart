import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String role;
  final String? facilityId;

  const UserProfile({required this.role, this.facilityId});

  bool get isAdmin => role == 'admin';
  bool get isFacilityHead => role == 'facility_head';
}

class UserProfileCache {
  final FirebaseFirestore _firestore;
  UserProfile? _cache;
  String? _cachedUid;

  UserProfileCache({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<UserProfile?> getUserProfile(String uid) async {
    if (_cache != null && _cachedUid == uid) return _cache;

    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;

    final data = doc.data()!;
    final role = data['role'] as String?;
    if (role == null) return null;

    _cache = UserProfile(
      role: role,
      facilityId: data['facilityId'] as String?,
    );
    _cachedUid = uid;
    return _cache;
  }

  void clear() {
    _cache = null;
    _cachedUid = null;
  }
}
