enum SyncState {
  synced,
  pending,
  failed,
}

class SyncStatus {
  final String id;
  final SyncState state;
  final DateTime timestamp;

  SyncStatus({
    required this.id,
    required this.state,
    required this.timestamp,
  });
}