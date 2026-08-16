import 'package:cloud_firestore/cloud_firestore.dart';

/// Typed representation of a facility's setting.
///
/// Firestore only ever stores the lowercase string form ('rural' / 'urban')
/// at the persistence boundary. Everywhere else in the app should use this
/// enum instead of comparing raw strings.
enum FacilityType {
  rural,
  urban;

  /// Parses the Firestore string representation into a [FacilityType].
  /// Falls back to [FacilityType.urban] for missing/unrecognized values,
  /// matching the previous default behavior of the raw string field.
  static FacilityType fromFirestore(String? value) {
    switch (value) {
      case 'rural':
        return FacilityType.rural;
      case 'urban':
        return FacilityType.urban;
      default:
        return FacilityType.urban;
    }
  }

  /// The lowercase string persisted to Firestore.
  String toFirestore() {
    switch (this) {
      case FacilityType.rural:
        return 'rural';
      case FacilityType.urban:
        return 'urban';
    }
  }
}

class Facility {
  final String id;
  final String name;
  final String email;
  final FacilityType type;
  final String region;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  Facility({
    required this.id,
    required this.name,
    required this.email,
    required this.type,
    required this.region,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory Facility.fromMap(Map<String, dynamic> map, String id) {
    return Facility(
      id: id,
      name: map['name']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      type: FacilityType.fromFirestore(map['type']?.toString()),
      region: map['region']?.toString() ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'type': type.toFirestore(),
      'region': region,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
