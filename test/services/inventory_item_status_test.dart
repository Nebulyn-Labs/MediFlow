// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';

/// Builds a minimal [InventoryItem] for status testing.
InventoryItem _item({
  required int daysUntilExpiry,
  int initialQuantity = 1000,
  int remainingQuantity = 800,
}) {
  final now = DateTime.now();
  return InventoryItem(
    id: 'test-id',
    medicineName: 'TestMed',
    batchId: 'B001',
    arrivalDate: now.subtract(const Duration(days: 10)),
    expiryDate: now.add(Duration(days: daysUntilExpiry)),
    initialQuantity: initialQuantity,
    remainingQuantity: remainingQuantity,
    unit: 'units',
    lastUpdated: now,
  );
}

void main() {
  group('InventoryItem.status – centralized classification (#237)', () {
    test('healthy item returns ItemStatus.healthy', () {
      final item = _item(daysUntilExpiry: 90);
      expect(item.status, ItemStatus.healthy);
      expect(item.hasAlert, isFalse);
    });

    test('expired item returns ItemStatus.expired, NOT expiringSoon', () {
      final item = _item(daysUntilExpiry: -1);
      expect(item.status, ItemStatus.expired);
      // Core invariant: expired is never also classified as expiringSoon.
      expect(item.status, isNot(ItemStatus.expiringSoon));
      expect(item.hasAlert, isTrue);
    });

    test('item expiring today (0 days left) is not yet expired', () {
      // daysUntilExpiry == 0 means the expiry date is today; difference
      // in inDays rounds down to 0 – still >= 0, not yet expired.
      final item = _item(daysUntilExpiry: 0);
      expect(item.isExpired, isFalse);
      expect(item.status, isNot(ItemStatus.expired));
    });

    test('item expiring in -5 days is expired', () {
      final item = _item(daysUntilExpiry: -5);
      expect(item.status, ItemStatus.expired);
    });

    test('expiring-soon item (within 30 days, low stock pct) is expiringSoon',
        () {
      // remainingQuantity = 600 / 1000 = 60 % → NOT wastageRisk (< 70 %)
      // and > kLowStockAbsolute (500), so NOT lowStock either.
      final item = _item(
        daysUntilExpiry: 20,
        initialQuantity: 1000,
        remainingQuantity: 600,
      );
      expect(item.status, ItemStatus.expiringSoon);
      expect(item.hasAlert, isTrue);
    });

    test('wastageRisk: ≥70 % stock remaining with expiry within 30 days', () {
      final item = _item(
        daysUntilExpiry: 15,
        initialQuantity: 1000,
        remainingQuantity: 750, // 75 % → wastageRisk
      );
      expect(item.status, ItemStatus.wastageRisk);
      expect(item.hasAlert, isTrue);
    });

    test('low-stock item (≤20 %) is classified as lowStock', () {
      final item = _item(
        daysUntilExpiry: 180,
        initialQuantity: 1000,
        remainingQuantity: 150, // 15 % → lowStock
      );
      expect(item.status, ItemStatus.lowStock);
      expect(item.isLowStock, isTrue);
      expect(item.hasAlert, isTrue);
    });

    test('low-stock absolute floor (≤500 units) triggers lowStock', () {
      final item = _item(
        daysUntilExpiry: 180,
        initialQuantity: 10000,
        remainingQuantity: 400, // 4 % AND ≤500 units
      );
      expect(item.isLowStock, isTrue);
      expect(item.status, ItemStatus.lowStock);
    });

    test('expired item is not counted in expiringSoon bucket', () {
      // This is the core regression guard for issue #237.
      final expiredItem = _item(daysUntilExpiry: -3);
      final expiringSoonItem = _item(
        daysUntilExpiry: 10,
        initialQuantity: 1000,
        remainingQuantity: 600,
      );
      final inventory = [expiredItem, expiringSoonItem];

      final expiredCount =
          inventory.where((i) => i.status == ItemStatus.expired).length;
      final expiringSoonCount =
          inventory.where((i) => i.status == ItemStatus.expiringSoon).length;

      // Expired item must NOT be counted in expiringSoon.
      expect(expiredCount, 1);
      expect(expiringSoonCount, 1);
      // Total unique alert items should equal 2, not 3.
      expect(expiredCount + expiringSoonCount, 2);
    });

    test('kExpiringSoonDays constant is 30', () {
      expect(InventoryItem.kExpiringSoonDays, 30);
    });

    test('kLowStockPercentage constant is 0.20', () {
      expect(InventoryItem.kLowStockPercentage, 0.20);
    });

    test('kLowStockAbsolute constant is 500', () {
      expect(InventoryItem.kLowStockAbsolute, 500);
    });
  });
}
