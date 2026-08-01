import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/views/shared/ai_chat_page.dart';

void main() {
  test('buildInventoryContextList produces no Timestamp instances', () {
    final item = InventoryItem(
      id: 'test-id',
      medicineName: 'Paracetamol',
      batchId: 'B123',
      arrivalDate: DateTime.now(),
      expiryDate: DateTime.now().add(const Duration(days: 90)),
      initialQuantity: 100,
      remainingQuantity: 50,
      unit: 'tablets',
      lastUpdated: DateTime.now(),
      facilityId: 'facility-1',
    );

    final result = buildInventoryContextList([item]);

    expect(result.length, 1);
    for (final value in result.first.values) {
      expect(value, isNot(isA<Timestamp>()));
    }
    // Sanity check the fields we care about are actually present
    expect(result.first['arrivalDate'], isA<String>());
    expect(result.first['facilityId'], 'facility-1');
  });
}
