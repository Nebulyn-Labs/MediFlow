import 'package:flutter/foundation.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({required this.text, required this.isUser, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class ChatService {
  ChatService() {
    debugPrint('ChatService: client-side model is disabled for security.');
  }

  bool get isAvailable => false;
  String get activeModelName => 'Disabled';

  Future<void> initChat(String? facilityId) async {
    // Stubbed for security
  }

  Future<String> sendMessage(String message) async {
    return 'Chat service is disabled on the client side for security.';
  }
}
