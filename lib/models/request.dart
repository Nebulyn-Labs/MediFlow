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

  /// Counts every request whose [RequestStatus] is [RequestStatus.pending],
  /// regardless of [RequestType]. This is the single source of truth for
  /// the "Pending Approvals" KPI on the admin dashboard and the row count
  /// on the /admin/approvals page; keeping it in one place means the two
  /// cannot drift out of sync (#334).
  static int countPending(Iterable<MedRequest> requests) {
    var count = 0;
    for (final r in requests) {
      if (r.status == RequestStatus.pending) count++;
    }
    return count;
  }

  /// Returns every request whose [RequestStatus] is [RequestStatus.pending],
  /// regardless of [RequestType]. Pair with [countPending] so the dashboard
  /// KPI and the /admin/approvals list agree on the same definition of
  /// "pending" (#334).
  static List<MedRequest> filterPending(Iterable<MedRequest> requests) {
    return requests
        .where((r) => r.status == RequestStatus.pending)
        .toList(growable: false);
  }

  factory MedRequest.fromMap(Map<String, dynamic> map, String id) {
    return MedRequest(
      id: id,
      facilityId: map['facilityId']?.toString() ?? '',
      medicineName: map['medicineName']?.toString() ?? '',
      type: RequestType.values.firstWhere((e) => e.name == map['type'],
          orElse: () => RequestType.regularIndent),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      requestDate:
          (map['requestDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: RequestStatus.values.firstWhere((e) => e.name == map['status'],
          orElse: () => RequestStatus.pending),
      notes: map['notes']?.toString(),
      rejectionReason: map['rejectionReason']?.toString(),
      resolvedAt: map['resolvedAt'] is Timestamp
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
