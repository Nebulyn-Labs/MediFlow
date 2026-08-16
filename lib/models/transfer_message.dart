import 'package:cloud_firestore/cloud_firestore.dart';

class TransferMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;

  TransferMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
  });

  factory TransferMessage.fromMap(Map<String, dynamic> map, String id) {
    return TransferMessage(
      id: id,
      senderId: map['senderId']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      sentAt: (map['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'text': text,
      'sentAt': Timestamp.fromDate(sentAt),
    };
  }
}
