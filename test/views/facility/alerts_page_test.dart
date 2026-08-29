import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:med_supply_prototype/constants/colors.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/facility/alerts_page.dart';

class MockFirebaseService extends Mock implements FirebaseService {}

void main() {
  late MockFirebaseService mockService;
  late StreamController<List<Map<String, dynamic>>> alertsController;

  setUp(() {
    mockService = MockFirebaseService();
    // broadcast so the same instance can be returned for repeated streamAlerts
    // calls; events are delivered only to listeners attached at the time of
    // add(), so tests must emit *after* the widget has subscribed.
    alertsController = StreamController<List<Map<String, dynamic>>>.broadcast();
    when(() => mockService.streamAlerts(any()))
        .thenAnswer((_) => alertsController.stream);
    when(() => mockService.disposeInventory(any(), any()))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    await alertsController.close();
  });

  /// Pumps [AlertsPage] and lets the StreamBuilder subscribe to the alerts
  /// stream. Tests then emit fixture data and call [settle].
  Future<void> pumpAlertPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseServiceProvider.overrideWithValue(mockService),
        ],
        child: const MaterialApp(
          home: AlertsPage(facilityId: 'fac_test'),
        ),
      ),
    );
    // First frame: StreamBuilder enters waiting.
    await tester.pump();
  }

  /// Emits [data] on the alerts stream and flushes the widget tree.
  Future<void> emitAlerts(
      WidgetTester tester, List<Map<String, dynamic>> data) {
    alertsController.add(data);
    return tester.pumpAndSettle();
  }

  group('AlertsPage', () {
    testWidgets('renders the empty state when there are no alerts',
        (tester) async {
      await pumpAlertPage(tester);
      await emitAlerts(tester, []);

      expect(find.text('No active alerts detected.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Expired Medicines'), findsNothing);
      expect(find.text('Stock Action Alerts'), findsNothing);
      expect(find.text('Expiry Watch'), findsNothing);

      verify(() => mockService.streamAlerts('fac_test')).called(1);
    });

    testWidgets('maps alert type strings to correct badges and colors',
        (tester) async {
      final now = DateTime.now();
      await pumpAlertPage(tester);
      await emitAlerts(tester, [
        {
          'type': 'expired',
          'medicineName': 'Amoxicillin',
          'batchId': 'B1',
          'stockId': 's1',
          'expiryDate':
              Timestamp.fromDate(now.subtract(const Duration(days: 5))),
          'initialQuantity': 100,
          'qtyRemaining': 10,
          'unit': 'tablets',
        },
        {
          'type': 'low_stock',
          'medicineName': 'Paracetamol',
          'batchId': 'B2',
          'stockId': 's2',
          'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 60))),
          'initialQuantity': 100,
          'qtyRemaining': 5,
          'unit': 'tablets',
        },
        {
          'type': 'wastage_risk',
          'medicineName': 'Ibuprofen',
          'batchId': 'B3',
          'stockId': 's3',
          'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 10))),
          'initialQuantity': 100,
          'qtyRemaining': 90,
          'unit': 'tablets',
        },
        {
          'type': 'expiring_soon',
          'medicineName': 'Vitamin C',
          'batchId': 'B4',
          'stockId': 's4',
          'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 20))),
          'initialQuantity': 100,
          'qtyRemaining': 80,
          'unit': 'tablets',
        },
        {
          'type': 'unknown_type',
          'medicineName': 'Fallback Med',
          'batchId': 'B5',
          'stockId': 's5',
          'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 15))),
          'initialQuantity': 50,
          'qtyRemaining': 40,
          'unit': 'tablets',
        },
      ]);

      // Badges render the title text. Note "unknown_type" falls through to the
      // expiring_soon default, so "Expiring Soon" appears twice.
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Low Stock'), findsOneWidget);
      expect(find.text('Wastage Risk'), findsOneWidget);
      expect(find.text('Expiring Soon'), findsNWidgets(2));

      // Badge text color matches the kind's color (error / warning).
      expect(
        (tester.widget(find.text('Expired')) as Text).style?.color,
        MediColors.error,
      );
      expect(
        (tester.widget(find.text('Low Stock')) as Text).style?.color,
        MediColors.error,
      );
      expect(
        (tester.widget(find.text('Wastage Risk')) as Text).style?.color,
        MediColors.warning,
      );
      expect(
        (find.text('Expiring Soon').evaluate().first.widget as Text)
            .style
            ?.color,
        MediColors.warning,
      );

      // Section headers present.
      expect(find.text('Expired Medicines'), findsOneWidget);
      expect(find.text('Stock Action Alerts'), findsOneWidget);
      expect(find.text('Expiry Watch'), findsOneWidget);
    });

    testWidgets(
        'sorts alerts by priority: expired, low_stock, wastage, expiring',
        (tester) async {
      final now = DateTime.now();
      // Emitting deliberately out of order (expiring first, expired last).
      await pumpAlertPage(tester);
      await emitAlerts(tester, [
        {
          'type': 'expiring_soon',
          'medicineName': 'Expiring-Med',
          'batchId': 'E1',
          'stockId': 'e1',
          'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 20))),
          'initialQuantity': 100,
          'qtyRemaining': 80,
          'unit': 'tablets',
        },
        {
          'type': 'wastage_risk',
          'medicineName': 'Wastage-Med',
          'batchId': 'W1',
          'stockId': 'w1',
          'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 10))),
          'initialQuantity': 100,
          'qtyRemaining': 90,
          'unit': 'tablets',
        },
        {
          'type': 'low_stock',
          'medicineName': 'LowStock-Med',
          'batchId': 'L1',
          'stockId': 'l1',
          'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 60))),
          'initialQuantity': 100,
          'qtyRemaining': 5,
          'unit': 'tablets',
        },
        {
          'type': 'expired',
          'medicineName': 'Expired-Med',
          'batchId': 'X1',
          'stockId': 'x1',
          'expiryDate':
              Timestamp.fromDate(now.subtract(const Duration(days: 5))),
          'initialQuantity': 100,
          'qtyRemaining': 10,
          'unit': 'tablets',
        },
      ]);

      expect(find.text('Expired-Med'), findsOneWidget);
      expect(find.text('LowStock-Med'), findsOneWidget);
      expect(find.text('Wastage-Med'), findsOneWidget);
      expect(find.text('Expiring-Med'), findsOneWidget);

      // Section ordering: Expired, then Stock Action, then Expiry Watch.
      final expiredHeader = find.text('Expired Medicines');
      final stockHeader = find.text('Stock Action Alerts');
      final expiryHeader = find.text('Expiry Watch');

      expect(
        tester.getTopLeft(expiredHeader).dy,
        lessThan(tester.getTopLeft(stockHeader).dy),
      );
      expect(
        tester.getTopLeft(stockHeader).dy,
        lessThan(tester.getTopLeft(expiryHeader).dy),
      );

      // Within the Stock Action section, low_stock (priority 1) precedes
      // wastage_risk (priority 2).
      final lowStockPos = tester.getTopLeft(find.text('LowStock-Med')).dy;
      final wastagePos = tester.getTopLeft(find.text('Wastage-Med')).dy;
      expect(lowStockPos, lessThan(wastagePos));
    });

    testWidgets('omits empty sections and shows only populated groups',
        (tester) async {
      final now = DateTime.now();
      // Only expired present -> only "Expired Medicines" section renders.
      await pumpAlertPage(tester);
      await emitAlerts(tester, [
        {
          'type': 'expired',
          'medicineName': 'Solo-Med',
          'batchId': 'S1',
          'stockId': 'solo1',
          'expiryDate':
              Timestamp.fromDate(now.subtract(const Duration(days: 3))),
          'initialQuantity': 100,
          'qtyRemaining': 20,
          'unit': 'vials',
        },
      ]);

      expect(find.text('Expired Medicines'), findsOneWidget);
      expect(find.text('Stock Action Alerts'), findsNothing);
      expect(find.text('Expiry Watch'), findsNothing);
      expect(find.text('Solo-Med'), findsOneWidget);
    });

    testWidgets('parses Timestamp, ISO-string, and missing expiry dates',
        (tester) async {
      final now = DateTime.now();
      await pumpAlertPage(tester);
      await emitAlerts(tester, [
        {
          'type': 'expired',
          'medicineName': 'Ts-Med',
          'batchId': 'T1',
          'stockId': 'ts1',
          'expiryDate':
              Timestamp.fromDate(now.subtract(const Duration(days: 2))),
          'initialQuantity': 100,
          'qtyRemaining': 10,
          'unit': 'tablets',
        },
        {
          'type': 'expiring_soon',
          'medicineName': 'Str-Med',
          'batchId': 'S1',
          'stockId': 'str1',
          'expiryDate': now.add(const Duration(days: 10)).toIso8601String(),
          'initialQuantity': 100,
          'qtyRemaining': 80,
          'unit': 'tablets',
        },
        {
          'type': 'expiring_soon',
          'medicineName': 'Null-Med',
          'batchId': 'N1',
          'stockId': 'n1',
          'expiryDate': null,
          'initialQuantity': 100,
          'qtyRemaining': 80,
          'unit': 'tablets',
        },
      ]);

      expect(find.text('Ts-Med'), findsOneWidget);
      expect(find.text('Str-Med'), findsOneWidget);
      expect(find.text('Null-Med'), findsOneWidget);
      // The expired card shows the disposal action; the others show AI analysis.
      expect(find.text('Mark for Disposal'), findsOneWidget);
      expect(find.text('Run Smart AI Stock Analysis'), findsNWidgets(2));
    });

    testWidgets(
        'Mark for Disposal on an expired card calls disposeInventory and shows success SnackBar',
        (tester) async {
      final now = DateTime.now();
      await pumpAlertPage(tester);
      await emitAlerts(tester, [
        {
          'type': 'expired',
          'medicineName': 'Disposable-Med',
          'batchId': 'D1',
          'stockId': 'd1',
          'expiryDate':
              Timestamp.fromDate(now.subtract(const Duration(days: 5))),
          'initialQuantity': 100,
          'qtyRemaining': 10,
          'unit': 'vials',
        },
      ]);

      await tester.ensureVisible(find.text('Mark for Disposal'));
      await tester.tap(find.text('Mark for Disposal'));
      await tester.pumpAndSettle();

      verify(() => mockService.disposeInventory('fac_test', 'Disposable-Med'))
          .called(1);
      expect(find.text('Marked Disposable-Med for safe disposal.'),
          findsOneWidget);
    });

    testWidgets('disposal error path shows an Error SnackBar', (tester) async {
      final now = DateTime.now();
      // Stub disposal to throw *before* the widget is pumped.
      when(() => mockService.disposeInventory(any(), any()))
          .thenThrow(Exception('disposal failed'));

      await pumpAlertPage(tester);
      await emitAlerts(tester, [
        {
          'type': 'expired',
          'medicineName': 'Failing-Med',
          'batchId': 'F1',
          'stockId': 'f1',
          'expiryDate':
              Timestamp.fromDate(now.subtract(const Duration(days: 5))),
          'initialQuantity': 100,
          'qtyRemaining': 10,
          'unit': 'vials',
        },
      ]);

      await tester.ensureVisible(find.text('Mark for Disposal'));
      await tester.tap(find.text('Mark for Disposal'));
      await tester.pumpAndSettle();

      verify(() => mockService.disposeInventory('fac_test', 'Failing-Med'))
          .called(1);
      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets(
        'non-expired cards render "Run Smart AI Stock Analysis" and no disposal button',
        (tester) async {
      final now = DateTime.now();
      await pumpAlertPage(tester);
      await emitAlerts(tester, [
        {
          'type': 'expiring_soon',
          'medicineName': 'Soon-Med',
          'batchId': 'SF1',
          'stockId': 'sf1',
          'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 20))),
          'initialQuantity': 100,
          'qtyRemaining': 80,
          'unit': 'vials',
        },
      ]);

      expect(find.text('Run Smart AI Stock Analysis'), findsOneWidget);
      expect(find.text('Mark for Disposal'), findsNothing);
    });
  });
}
