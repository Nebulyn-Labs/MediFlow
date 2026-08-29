import 'package:cloud_firestore/cloud_firestore.dart';

class TransferThread {
  final String id;
  final String requestId;
  final String medicineName;
  final int quantity;
  final String donorFacilityId;
  final String recipientFacilityId;
  final String status;
  final DateTime createdAt;
  final DateTime lastMessageAt;

  TransferThread({
    required this.id,
    required this.requestId,
    required this.medicineName,
    required this.quantity,
    required this.donorFacilityId,
    required this.recipientFacilityId,
    required this.status,
    required this.createdAt,
    required this.lastMessageAt,
  });

  factory TransferThread.fromMap(Map<String, dynamic> map, String id) {
    return TransferThread(
      id: id,
      requestId: map['requestId']?.toString() ?? '',
      medicineName: map['medicineName']?.toString() ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      donorFacilityId: map['donorFacilityId']?.toString() ?? '',
      recipientFacilityId: map['recipientFacilityId']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessageAt:
          (map['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'medicineName': medicineName,
      'quantity': quantity,
      'donorFacilityId': donorFacilityId,
      'recipientFacilityId': recipientFacilityId,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastMessageAt': Timestamp.fromDate(lastMessageAt),
    };
  }
}
