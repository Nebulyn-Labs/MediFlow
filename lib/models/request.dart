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
  final String? rejectionReason;
  final DateTime? resolvedAt;

  MedRequest({
    required this.id,
    required this.facilityId,
    required this.medicineName,
    required this.type,
    required this.quantity,
    required this.requestDate,
    required this.status,
    this.notes,
    this.rejectionReason,
    this.resolvedAt,
  });

  factory MedRequest.fromMap(Map<String, dynamic> map, String id) {
    return MedRequest(
      id: id,
      facilityId: map['facilityId'] ?? '',
      medicineName: map['medicineName'] ?? '',
      type: RequestType.values.firstWhere((e) => e.name == map['type'],
          orElse: () => RequestType.regularIndent),
      quantity: map['quantity']?.toInt() ?? 0,
      requestDate: (map['requestDate'] as Timestamp).toDate(),
      status: RequestStatus.values.firstWhere((e) => e.name == map['status'],
          orElse: () => RequestStatus.pending),
      notes: map['notes'],
      rejectionReason: map['rejectionReason'],
      resolvedAt: map['resolvedAt'] != null
          ? (map['resolvedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'facilityId': facilityId,
      'medicineName': medicineName,
      'type': type.name,
      'quantity': quantity,
      'requestDate': Timestamp.fromDate(requestDate),
      'status': status.name,
      'notes': notes,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
    };
  }
}
