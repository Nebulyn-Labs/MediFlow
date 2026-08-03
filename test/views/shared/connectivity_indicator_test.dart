import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/services/connectivity_service.dart';
import 'package:med_supply_prototype/views/shared/connectivity_indicator.dart';

/// Pushes [value] onto the status stream and pumps until the widget tree has
/// caught up: one frame to deliver the event, one to rebuild and settle the
/// banner animation.
Future<void> _emit(
  WidgetTester tester,
  StreamController<bool> controller,
  bool value,
) async {
  controller.add(value);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Widget _wrap(Widget child, {required Stream<bool> status}) {
  return ProviderScope(
    overrides: [
      connectivityStatusProvider.overrideWith((ref) => status),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('ConnectivityIndicator', () {
    testWidgets('shows an online pill when connected', (tester) async {
      await tester.pumpWidget(
          _wrap(const ConnectivityIndicator(), status: Stream.value(true)));
      await tester.pump();

      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
    });

    testWidgets('shows an offline pill when disconnected', (tester) async {
      await tester.pumpWidget(
          _wrap(const ConnectivityIndicator(), status: Stream.value(false)));
      await tester.pump();

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('reads as online until the first status arrives',
        (tester) async {
      await tester.pumpWidget(_wrap(const ConnectivityIndicator(),
          status: const Stream<bool>.empty()));
      await tester.pump();

      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('follows connectivity changes without a rebuild from the host',
        (tester) async {
      final controller = StreamController<bool>.broadcast();
      // Not awaited: closing inside tearDown would wait on a microtask that
      // the (already finished) fake async zone will never pump.
      addTearDown(() {
        controller.close();
      });

      await tester.pumpWidget(
          _wrap(const ConnectivityIndicator(), status: controller.stream));
      await _emit(tester, controller, true);
      expect(find.text('Online'), findsOneWidget);

      await _emit(tester, controller, false);
      expect(find.text('Offline'), findsOneWidget);

      await _emit(tester, controller, true);
      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('collapses to an icon on narrow layouts', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _wrap(const ConnectivityIndicator(), status: Stream.value(false)));
      await tester.pump();

      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
    });
  });

  group('OfflineBanner', () {
    testWidgets('stays hidden while online', (tester) async {
      await tester
          .pumpWidget(_wrap(const OfflineBanner(), status: Stream.value(true)));
      await tester.pump();

      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.textContaining('offline'), findsNothing);
    });

    testWidgets('explains the degraded behaviour while offline',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const OfflineBanner(), status: Stream.value(false)));
      await tester.pump();

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.textContaining('You are offline'), findsOneWidget);
    });

    testWidgets('disappears once connectivity is restored', (tester) async {
      final controller = StreamController<bool>.broadcast();
      // Not awaited: closing inside tearDown would wait on a microtask that
      // the (already finished) fake async zone will never pump.
      addTearDown(() {
        controller.close();
      });

      await tester
          .pumpWidget(_wrap(const OfflineBanner(), status: controller.stream));
      await _emit(tester, controller, false);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      await _emit(tester, controller, true);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    });
  });
}
