import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/daily_usage_log.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/services/connectivity_service.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/facility/daily_logging_page.dart';
import 'package:med_supply_prototype/views/facility/indent_creation_page.dart';

const String _facilityId = 'facility-1';

InventoryItem _item(String name) {
  final now = DateTime(2026, 1, 1);
  return InventoryItem(
    id: 'inv-$name',
    medicineName: name,
    batchId: 'batch-$name',
    arrivalDate: now,
    expiryDate: now.add(const Duration(days: 365)),
    initialQuantity: 1000,
    remainingQuantity: 800,
    unit: 'units',
    lastUpdated: now,
  );
}

class FakeFirebaseService implements FirebaseService {
  FakeFirebaseService({this.inventory = const []});

  final List<InventoryItem> inventory;
  int logUsageCallCount = 0;
  int addRequestCallCount = 0;

  @override
  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async =>
      inventory;

  @override
  Future<PaginatedLogsResult> getPaginatedLogs(
    String facilityId, {
    int pageSize = 15,
    DocumentSnapshot? startAfter,
  }) async =>
      PaginatedLogsResult(logs: const [], lastDocument: null, hasMore: false);

  @override
  Future<void> logUsage({
    required String facilityId,
    required DateTime date,
    required String medicineName,
    required int quantity,
    required int patients,
  }) async {
    logUsageCallCount++;
  }

  @override
  Future<void> addRequest(dynamic request) async {
    addRequestCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FakeFirebaseService> _pumpDailyLoggingPage(WidgetTester tester) async {
  final firebase = FakeFirebaseService(
    inventory: [_item('Paracetamol'), _item('ORS')],
  );

  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(firebase),
        connectivityStatusProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const DailyLoggingPage(facilityId: _facilityId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 300));

  return firebase;
}

Future<FakeFirebaseService> _pumpIndentCreationPage(WidgetTester tester) async {
  final firebase = FakeFirebaseService(
    inventory: [_item('Paracetamol'), _item('ORS')],
  );

  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(firebase),
        connectivityStatusProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const IndentCreationPage(facilityId: _facilityId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 300));

  return firebase;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Daily Logging - Units Distributed Validator Widget Tests', () {
    testWidgets('rejects zero and negative units and blocks submit',
        (tester) async {
      final firebase = await _pumpDailyLoggingPage(tester);

      // Enter 0 for Units Distributed and 5 for Patients Served
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Units Distributed'), '0');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Patients Served'), '5');

      await tester.tap(find.text('Save Log'));
      await tester.pump();

      expect(find.text('Enter a number greater than 0'), findsOneWidget);
      expect(firebase.logUsageCallCount, 0);

      // Enter negative number (-10) for Units Distributed
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Units Distributed'), '-10');

      await tester.tap(find.text('Save Log'));
      await tester.pump();

      expect(find.text('Enter a number greater than 0'), findsOneWidget);
      expect(firebase.logUsageCallCount, 0);
    });

    testWidgets('accepts positive units and submits log', (tester) async {
      final firebase = await _pumpDailyLoggingPage(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Units Distributed'), '25');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Patients Served'), '10');

      await tester.tap(find.text('Save Log'));
      await tester.pump();

      expect(find.text('Enter a number greater than 0'), findsNothing);
      expect(firebase.logUsageCallCount, 1);
    });
  });

  group('Daily Logging - Patients Served Validator Widget Tests', () {
    testWidgets('rejects negative patients and blocks submit', (tester) async {
      final firebase = await _pumpDailyLoggingPage(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Units Distributed'), '10');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Patients Served'), '-5');

      await tester.tap(find.text('Save Log'));
      await tester.pump();

      expect(find.text('Enter a number 0 or greater'), findsOneWidget);
      expect(firebase.logUsageCallCount, 0);
    });

    testWidgets('accepts zero patients and submits log', (tester) async {
      final firebase = await _pumpDailyLoggingPage(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Units Distributed'), '10');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Patients Served'), '0');

      await tester.tap(find.text('Save Log'));
      await tester.pump();

      expect(find.text('Enter a number 0 or greater'), findsNothing);
      expect(firebase.logUsageCallCount, 1);
    });
  });

  group('Indent Form - Quantity Validator Widget Tests', () {
    testWidgets('shows inline error when typing 0 or negative quantity',
        (tester) async {
      final firebase = await _pumpIndentCreationPage(tester);

      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeastNWidgets(1));

      // Enter 0 in the first medicine quantity field
      await tester.enterText(textFields.first, '0');
      await tester.pump();

      expect(find.text('Enter a number > 0'), findsWidgets);

      // Enter -5 in the first medicine quantity field
      await tester.enterText(textFields.first, '-5');
      await tester.pump();

      expect(find.text('Enter a number > 0'), findsWidgets);

      // Attempt submit with negative quantity
      await tester.tap(find.text('Save as Draft'));
      await tester.pump();

      expect(find.text('Please enter valid quantities greater than 0.'),
          findsOneWidget);
      expect(firebase.addRequestCallCount, 0);

      // Enter valid positive quantity (15)
      await tester.enterText(textFields.first, '15');
      await tester.pump();

      expect(find.text('Enter a number > 0'), findsNothing);
    });
  });
}
