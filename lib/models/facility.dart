import 'package:cloud_firestore/cloud_firestore.dart';

class Facility {
  final String id;
  final String name;
  final String email;
  final String type; // 'rural' or 'urban'
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
      type: map['type']?.toString() ?? 'urban',
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
      'type': type,
      'region': region,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
