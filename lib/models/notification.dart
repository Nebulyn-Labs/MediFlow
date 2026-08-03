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
      facilityId: data['facilityId']?.toString() ?? '',
      type: data['type']?.toString() ?? 'info',
      message: data['message']?.toString() ?? '',
      isRead: (data['isRead'] as bool?) ?? false,
      createdAt: data['createdAt'] is Timestamp
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
