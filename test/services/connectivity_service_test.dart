import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/services/connectivity_service.dart';

/// Stand-in for the plugin's [Connectivity] singleton so tests never touch a
/// platform channel.
class FakeConnectivity implements Connectivity {
  FakeConnectivity({
    this.initial = const [ConnectivityResult.wifi],
  });

  List<ConnectivityResult> initial;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();
  int checkCallCount = 0;

  void emit(List<ConnectivityResult> results) => _controller.add(results);

  Future<void> close() => _controller.close();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checkCallCount++;
    return initial;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;
}

void main() {
  group('ConnectivityService.isOnline', () {
    test('treats a lone "none" report as offline', () {
      expect(ConnectivityService.isOnline([ConnectivityResult.none]), isFalse);
    });

    test('treats any real interface as online', () {
      for (final result in [
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
        ConnectivityResult.ethernet,
        ConnectivityResult.vpn,
        ConnectivityResult.bluetooth,
        ConnectivityResult.other,
      ]) {
        expect(ConnectivityService.isOnline([result]), isTrue,
            reason: '$result should count as online');
      }
    });

    test('is online when at least one interface is up', () {
      expect(
        ConnectivityService.isOnline(
            [ConnectivityResult.none, ConnectivityResult.wifi]),
        isTrue,
      );
    });

    test('treats an empty report as offline', () {
      expect(ConnectivityService.isOnline([]), isFalse);
    });
  });

  group('ConnectivityService.checkOnline', () {
    test('maps the platform report to a boolean', () async {
      final fake = FakeConnectivity(initial: [ConnectivityResult.none]);
      addTearDown(fake.close);
      final service = ConnectivityService(connectivity: fake);

      expect(await service.checkOnline(), isFalse);

      fake.initial = [ConnectivityResult.mobile];
      expect(await service.checkOnline(), isTrue);
    });
  });

  group('ConnectivityService.watchOnline', () {
    test('emits the current status before any change arrives', () async {
      final fake = FakeConnectivity(initial: [ConnectivityResult.none]);
      addTearDown(fake.close);
      final service = ConnectivityService(connectivity: fake);

      expect(await service.watchOnline().first, isFalse);
      expect(fake.checkCallCount, 1);
    });

    test('emits on every flip and drops duplicates', () async {
      final fake = FakeConnectivity(initial: [ConnectivityResult.wifi]);
      addTearDown(fake.close);
      final service = ConnectivityService(connectivity: fake);

      final seen = <bool>[];
      final subscription = service.watchOnline().listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      // Same status as the initial check — must not be re-emitted.
      fake.emit([ConnectivityResult.mobile]);
      await pumpEventQueue();
      fake.emit([ConnectivityResult.none]);
      await pumpEventQueue();
      fake.emit([ConnectivityResult.none]);
      await pumpEventQueue();
      fake.emit([ConnectivityResult.ethernet]);
      await pumpEventQueue();

      expect(seen, [true, false, true]);
    });
  });

  group('isOnlineProvider', () {
    test('defaults to online while the first status is pending', () {
      final container = ProviderContainer(
        overrides: [
          connectivityStatusProvider.overrideWith((ref) => Stream.value(false)),
        ],
      );
      addTearDown(container.dispose);

      // Nothing has been emitted yet, so the screen should behave normally.
      expect(container.read(isOnlineProvider), isTrue);
    });

    test('follows the reported status once available', () async {
      final container = ProviderContainer(
        overrides: [
          connectivityStatusProvider.overrideWith((ref) => Stream.value(false)),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(isOnlineProvider, (_, __) {});
      addTearDown(subscription.close);
      await container.read(connectivityStatusProvider.future);

      expect(container.read(isOnlineProvider), isFalse);
    });

    test('falls back to online when the platform check fails', () async {
      final container = ProviderContainer(
        overrides: [
          connectivityStatusProvider.overrideWith(
              (ref) => Stream<bool>.error(Exception('channel unavailable'))),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(isOnlineProvider, (_, __) {});
      addTearDown(subscription.close);
      await pumpEventQueue();

      expect(container.read(isOnlineProvider), isTrue);
    });
  });
}
