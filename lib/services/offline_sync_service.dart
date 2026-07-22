import 'package:flutter/foundation.dart';

class PendingWrite {
  final String id;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  PendingWrite({
    required this.id,
    required this.data,
    required this.createdAt,
  });
}

class OfflineSyncService {
  final List<PendingWrite> _queue = [];

  List<PendingWrite> get pendingWrites => List.unmodifiable(_queue);

  void addPendingWrite(PendingWrite write) {
    _queue.add(write);
    debugPrint('Queued offline write: ${write.id}');
  }

  void removePendingWrite(String id) {
    _queue.removeWhere((item) => item.id == id);
  }

  void clearQueue() {
    _queue.clear();
  }
}