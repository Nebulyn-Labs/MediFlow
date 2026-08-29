import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/facility/active_indents_page.dart';
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

  @override
  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async =>
      inventory;

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI Stock Analysis Table - Checkbox Removal Verification', () {
    testWidgets('IndentCreationPage table has no non-functional checkboxes or header icons',
        (tester) async {
      final firebase = FakeFirebaseService(
        inventory: [_item('Paracetamol'), _item('Amoxicillin')],
      );

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseServiceProvider.overrideWithValue(firebase),
          ],
          child: const MaterialApp(
            home: IndentCreationPage(facilityId: _facilityId),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 300));

      // Checkboxes should not exist in the table
      expect(find.byType(Checkbox), findsNothing);
      // Static check_box_outline_blank header icon should not exist
      expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);

      // Verify table headers are rendered
      expect(find.text('Medicine'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('AI Predicted Usage'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Request Qty'), findsOneWidget);
    });

    testWidgets('ActiveIndentsPage table has no non-functional checkboxes or header icons',
        (tester) async {
      final firebase = FakeFirebaseService(
        inventory: [_item('Paracetamol'), _item('Amoxicillin')],
      );

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseServiceProvider.overrideWithValue(firebase),
          ],
          child: const MaterialApp(
            home: ActiveIndentsPage(facilityId: _facilityId),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 300));

      // Checkboxes should not exist in the AI table
      expect(find.byType(Checkbox), findsNothing);
      // Static check_box_outline_blank header icon should not exist
      expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);

      // Verify table headers are rendered
      expect(find.text('Medicine'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('AI Predicted Usage'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Request Qty'), findsOneWidget);
    });
  });
}
