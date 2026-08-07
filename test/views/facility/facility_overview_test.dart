import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/facility/facility_overview.dart';

class TestOverviewFirebaseService implements FirebaseService {
  final List<InventoryItem> items;
  TestOverviewFirebaseService(this.items);

  @override
  Stream<List<InventoryItem>> streamInventory(String facilityId) {
    return Stream.value(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final List<InventoryItem> sampleItems = [
    InventoryItem(
      id: '1',
      facilityId: 'fac-1',
      medicineName: 'Amoxicillin',
      batchId: 'BATCH-001',
      arrivalDate: DateTime.now().subtract(const Duration(days: 10)),
      expiryDate: DateTime.now().add(const Duration(days: 90)),
      initialQuantity: 100,
      remainingQuantity: 100,
      unit: 'tablets',
      lastUpdated: DateTime.now(),
    ),
  ];

  testWidgets('Total Meds in Inv KPI card is non-interactive while alert cards are clickable', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeService = TestOverviewFirebaseService(sampleItems);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseServiceProvider.overrideWithValue(fakeService),
        ],
        child: const MaterialApp(
          home: FacilityOverview(facilityId: 'fac-1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify 'Total Meds in Inv' card is rendered
    final totalMedsCard = find.text('Total Meds in Inv');
    expect(totalMedsCard, findsOneWidget);

    // Verify MouseRegion cursors
    final mouseRegions = tester.widgetList<MouseRegion>(find.byType(MouseRegion));
    final nonInteractiveRegions = mouseRegions.where((m) => m.cursor == SystemMouseCursors.basic);
    final clickRegions = mouseRegions.where((m) => m.cursor == SystemMouseCursors.click);

    expect(nonInteractiveRegions, isNotEmpty);
    expect(clickRegions, isNotEmpty);
  });
}
