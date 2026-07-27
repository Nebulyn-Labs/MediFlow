import 'package:cloud_firestore/cloud_firestore.dart';

enum FacilityType { rural, urban }

FacilityType facilityTypeFromString(String? value) {
  switch (value?.toLowerCase()) {
    case 'rural':
      return FacilityType.rural;
    case 'urban':
    default:
      return FacilityType.urban;
  }
}

extension FacilityTypeX on FacilityType {
  String get apiValue => name;

  String get label => switch (this) {
        FacilityType.rural => 'Rural',
        FacilityType.urban => 'Urban',
      };
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
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      type: facilityTypeFromString(map['type']),
      region: map['region'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'type': type.apiValue,
      'region': region,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
