import 'package:cloud_firestore/cloud_firestore.dart';

class UsageLog {
  final String id;
  final String facilityId;
  final String medicineName;
  final DateTime date;
  final int quantityUsed;
  final int patientsTreated;

  UsageLog({
    required this.id,
    required this.facilityId,
    required this.medicineName,
    required this.date,
    required this.quantityUsed,
    required this.patientsTreated,
  });

  factory UsageLog.fromMap(Map<String, dynamic> map, String id) {
    return UsageLog(
      id: id,
      facilityId: map['facilityId']?.toString() ?? '',
      medicineName: map['medicineName']?.toString() ?? '',
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      quantityUsed: (map['quantityUsed'] as num?)?.toInt() ?? 0,
      patientsTreated: (map['patientsTreated'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'facilityId': facilityId,
      'medicineName': medicineName,
      'date': Timestamp.fromDate(date),
      'quantityUsed': quantityUsed,
      'patientsTreated': patientsTreated,
    };
  }
}
