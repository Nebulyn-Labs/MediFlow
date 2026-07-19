import 'package:cloud_firestore/cloud_firestore.dart';

class MedicineUsage {
  final String medicineName;
  final int unitsDistributed;

  MedicineUsage({
    required this.medicineName,
    required this.unitsDistributed,
  });

  factory MedicineUsage.fromMap(Map<String, dynamic> map) {
    return MedicineUsage(
      medicineName: map['medicineName'] ?? '',
      unitsDistributed: map['unitsDistributed']?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'medicineName': medicineName,
      'unitsDistributed': unitsDistributed,
    };
  }
}

class DailyUsageLog {
  final String id;
  final DateTime date;
  final List<MedicineUsage> medicines;
  final int totalPatients;

  DailyUsageLog({
    required this.id,
    required this.date,
    required this.medicines,
    required this.totalPatients,
  });

  factory DailyUsageLog.fromMap(Map<String, dynamic> map, String id) {
    return DailyUsageLog(
      id: id,
      date: (map['date'] as Timestamp).toDate(),
      medicines: (map['medicines'] as List? ?? [])
          .map((m) => MedicineUsage.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      totalPatients: map['totalPatients']?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'medicines': medicines.map((m) => m.toMap()).toList(),
      'totalPatients': totalPatients,
    };
  }
}
