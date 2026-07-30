import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String facilityId;
  final String type;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.facilityId,
    required this.type,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromMap(
      Map<String, dynamic> data, String documentId) {
    return NotificationModel(
      id: documentId,
      facilityId: data['facilityId'] ?? '',
      type: data['type'] ?? 'info',
      message: data['message'] ?? '',
      isRead: data['isRead'] ?? false,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'facilityId': facilityId,
      'type': type,
      'message': message,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
