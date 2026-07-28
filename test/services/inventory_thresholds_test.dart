import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/constants/inventory_thresholds.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';

void main() {
  group('Inventory Thresholds Synchronization Tests', () {
    test('Dart thresholds match backend JSON source of truth', () {
      final jsonFile = File('functions/helpers/inventory_thresholds.json');
      expect(jsonFile.existsSync(), isTrue, reason: 'Source of truth JSON file must exist.');

      final jsonContent = jsonFile.readAsStringSync();
      final Map<String, dynamic> thresholds = jsonDecode(jsonContent);

      final double expectedPercentage = thresholds['lowStockPercentage'];
      final int expectedAbsolute = thresholds['lowStockAbsolute'];

      expect(InventoryThresholds.lowStockPercentage, expectedPercentage,
          reason: 'Dart lowStockPercentage must match JSON source of truth.');
      expect(InventoryThresholds.lowStockAbsolute, expectedAbsolute,
          reason: 'Dart lowStockAbsolute must match JSON source of truth.');
    });

    test('Client evaluates low-stock identically to backend criteria', () {
      // Test cases that mimic the JS stockStatus classification tests
      // Case 1: drops to 20% remaining
      final item1 = InventoryItem(
        id: '1',
        medicineName: 'Paracetamol',
        batchId: 'B1',
        arrivalDate: DateTime.now(),
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        initialQuantity: 100,
        remainingQuantity: 20,
        unit: 'units',
        lastUpdated: DateTime.now(),
      );
      expect(item1.isLowStock, isTrue);

      // Case 2: absolute floor <= 500
      final item2 = InventoryItem(
        id: '2',
        medicineName: 'Paracetamol',
        batchId: 'B1',
        arrivalDate: DateTime.now(),
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        initialQuantity: 100000,
        remainingQuantity: 500,
        unit: 'units',
        lastUpdated: DateTime.now(),
      );
      expect(item2.isLowStock, isTrue);

      // Case 3: healthy stock
      final item3 = InventoryItem(
        id: '3',
        medicineName: 'Paracetamol',
        batchId: 'B1',
        arrivalDate: DateTime.now(),
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        initialQuantity: 10000,
        remainingQuantity: 8000,
        unit: 'units',
        lastUpdated: DateTime.now(),
      );
      expect(item3.isLowStock, isFalse);
    });
  });
}
