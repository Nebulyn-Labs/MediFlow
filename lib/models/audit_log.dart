import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLog {
  final String id;
  final String adminId;
  final DateTime timestamp;
  final String action;
  final String resourceType;
  final String resourceId;
  final Map<String, dynamic>? metadata;
  final String status;

  AuditLog({
    required this.id,
    required this.adminId,
    required this.timestamp,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    this.metadata,
    required this.status,
  });

  factory AuditLog.fromMap(Map<String, dynamic> map, String id) {
    return AuditLog(
      id: id,
      adminId: map['adminId'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      action: map['action'] ?? '',
      resourceType: map['resourceType'] ?? '',
      resourceId: map['resourceId'] ?? '',
      metadata: map['metadata'] as Map<String, dynamic>?,
      status: map['status'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'adminId': adminId,
      'timestamp': Timestamp.fromDate(timestamp),
      'action': action,
      'resourceType': resourceType,
      'resourceId': resourceId,
      'metadata': metadata,
      'status': status,
    };
  }
}

class PaginatedAuditLogsResult {
  final List<AuditLog> logs;
  final DocumentSnapshot? lastDocument;
  final bool hasMore;

  PaginatedAuditLogsResult({
    required this.logs,
    this.lastDocument,
    required this.hasMore,
  });
}
