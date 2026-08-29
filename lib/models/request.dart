import 'package:cloud_firestore/cloud_firestore.dart';

enum RequestType { shortage, surplus, regularIndent }

/// [needsManualReview] is written server-side by `onIndentApproved` (see
/// functions/helpers/approvalErrors.js) when approval processing hits a
/// non-retryable, non-business-rule failure — e.g. a permissions error or a
/// plain bug — rather than a transient Firestore/infra hiccup. It is
/// distinct from [rejected]: the request was never evaluated against
/// business rules, so no curated rejection reason exists, and an admin
/// needs to look at it manually (#314).
enum RequestStatus {
  draft,
  pending,
  approved,
  dispatched,
  inTransit,
  received,
  verified,
  fulfilled,
  rejected,
  needsManualReview
}

/// Human-readable labels for [RequestStatus], centralized so every screen
/// that displays a status (admin approvals, supply status table, facility
/// history) renders it the same way. Falling back to the raw enum name via
/// `.name` reads fine for single-word statuses but produces an ugly
/// run-together word for multi-word ones like [RequestStatus.needsManualReview].
extension RequestStatusLabel on RequestStatus {
  String get label {
    switch (this) {
      case RequestStatus.draft:
        return 'Draft';
      case RequestStatus.pending:
        return 'Pending';
      case RequestStatus.approved:
        return 'Approved';
      case RequestStatus.dispatched:
        return 'Dispatched';
      case RequestStatus.inTransit:
        return 'In Transit';
      case RequestStatus.received:
        return 'Received';
      case RequestStatus.verified:
        return 'Verified';
      case RequestStatus.fulfilled:
        return 'Fulfilled';
      case RequestStatus.rejected:
        return 'Rejected';
      case RequestStatus.needsManualReview:
        return 'Needs Review';
    }
  }
}

class MedRequest {
  final String id;
  final String facilityId;
  final String medicineName;
  final RequestType type;
  final int quantity;
  final DateTime requestDate;
  final RequestStatus status;
  final String? notes;
  final String? batchId;
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
    this.batchId,
    this.rejectionReason,
    this.resolvedAt,
  });

  /// Counts every request whose [RequestStatus] is [RequestStatus.pending],
  /// regardless of [RequestType]. This is the single source of truth for
  /// the "Pending Approvals" KPI on the admin dashboard and the row count
  /// on the /admin/approvals page; keeping it in one place means the two
  /// cannot drift out of sync (#334).
  ///
  /// [RequestStatus.needsManualReview] requests are intentionally excluded:
  /// they already failed automatic processing once, so lumping them back
  /// into "pending" would misrepresent both this count and the
  /// /admin/approvals list, which re-attempts approval processing (#314).
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

  /// Counts every request whose [RequestStatus] is
  /// [RequestStatus.needsManualReview]. Pair with the "NEEDS REVIEW" KPI
  /// card on the admin dashboard so requests that failed automatic
  /// approval processing are surfaced instead of sitting invisibly in
  /// Firestore (#314).
  static int countNeedsManualReview(Iterable<MedRequest> requests) {
    var count = 0;
    for (final r in requests) {
      if (r.status == RequestStatus.needsManualReview) count++;
    }
    return count;
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
      batchId: map['batchId']?.toString(),
      rejectionReason: map['rejectionReason']?.toString(),
      resolvedAt: map['resolvedAt'] is Timestamp
          ? (map['resolvedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Whether this request represents an actionable deficit (pending or approved regular indent or shortage).
  bool get isDeficit =>
      (status == RequestStatus.pending || status == RequestStatus.approved) &&
      (type == RequestType.regularIndent || type == RequestType.shortage);

  Map<String, dynamic> toMap() {
    return {
      'facilityId': facilityId,
      'medicineName': medicineName,
      'type': type.name,
      'quantity': quantity,
      'requestDate': Timestamp.fromDate(requestDate),
      'status': status.name,
      'notes': notes,
      if (batchId != null) 'batchId': batchId,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
    };
  }
}
