import 'package:cloud_firestore/cloud_firestore.dart';

enum RequestType { shortage, surplus, regularIndent }
enum RequestStatus { draft, pending, approved, fulfilled, rejected }

class MedRequest {
  final String id;
  final String facilityId;
  final String medicineName;
  final RequestType type;
  final int quantity;
  final DateTime requestDate;
  final RequestStatus status;
  final String? notes;

  MedRequest({
    required this.id,
    required this.facilityId,
    required this.medicineName,
    required this.type,
    required this.quantity,
    required this.requestDate,
    required this.status,
    this.notes,
  });

  factory MedRequest.fromMap(Map<String, dynamic> map, String id) {
    return MedRequest(
      id: id,
      facilityId: map['facilityId'] ?? '',
      medicineName: map['medicineName'] ?? '',
      type: RequestType.values.firstWhere((e) => e.toString() == map['type'], orElse: () => RequestType.regularIndent),
      quantity: map['quantity']?.toInt() ?? 0,
      requestDate: (map['requestDate'] as Timestamp).toDate(),
      status: RequestStatus.values.firstWhere((e) => e.toString() == map['status'], orElse: () => RequestStatus.pending),
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'facilityId': facilityId,
      'medicineName': medicineName,
      'type': type.toString(),
      'quantity': quantity,
      'requestDate': Timestamp.fromDate(requestDate),
      'status': status.toString(),
      'notes': notes,
    };
  }
}
