import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps [Connectivity] and reduces the platform's connectivity report down to
/// the single question the UI cares about: is the device on a network?
///
/// Facilities in remote areas often lose connectivity mid-session, so screens
/// listen to [watchOnline] rather than probing on demand.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Whether a connectivity report from the platform means "online".
  ///
  /// The platform never returns an empty list; no connectivity is reported as a
  /// single [ConnectivityResult.none] entry.
  static bool isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  /// One-off connectivity check, useful right before starting a request.
  Future<bool> checkOnline() async =>
      isOnline(await _connectivity.checkConnectivity());

  /// Emits the current status immediately, then again on every change.
  ///
  /// Consecutive duplicates are dropped so listeners only rebuild when the
  /// online/offline state actually flips.
  Stream<bool> watchOnline() => _statusStream().distinct();

  Stream<bool> _statusStream() async* {
    yield await checkOnline();
    yield* _connectivity.onConnectivityChanged.map(isOnline);
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

/// Emits `true` while the device has a network connection.
///
/// Consumers should treat the loading state as online so that screens behave
/// normally until the first real report arrives.
final connectivityStatusProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).watchOnline();
});

/// Convenience read of [connectivityStatusProvider] that defaults to online
/// while the first status is still being resolved, or if the platform check
/// fails.
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityStatusProvider).value ?? true;
});
