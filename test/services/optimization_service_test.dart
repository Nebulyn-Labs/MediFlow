import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/optimization_service.dart';

void main() {
  group('OptimizationService - MultiStopRoutes', () {
    late OptimizationService service;

    setUp(() {
      service = OptimizationService();
    });

    test('calculateMultiStopRoutes groups by donor and orders stops', () {
      final f1 = Facility(
          id: 'd1',
          name: 'Donor 1',
          type: 'hospital',
          latitude: 0,
          longitude: 0,
          email: 'test@example.com',
          region: 'test',
          createdAt: DateTime.now());
      final f2 = Facility(
          id: 'r1',
          name: 'Rec 1',
          type: 'clinic',
          latitude: 10,
          longitude: 10,
          email: 'test@example.com',
          region: 'test',
          createdAt: DateTime.now());
      final f3 = Facility(
          id: 'r2',
          name: 'Rec 2',
          type: 'clinic',
          latitude: 1,
          longitude: 1,
          email: 'test@example.com',
          region: 'test',
          createdAt: DateTime.now());

      final inv = {
        'd1': [
          InventoryItem(
              id: 'i1',
              facilityId: 'd1',
              medicineName: 'A',
              remainingQuantity: 100,
              expiryDate: DateTime.now().add(const Duration(days: 10)),
              batchId: 'b1',
              arrivalDate: DateTime.now(),
              initialQuantity: 100,
              unit: 'box',
              lastUpdated: DateTime.now()),
          InventoryItem(
              id: 'i2',
              facilityId: 'd1',
              medicineName: 'B',
              remainingQuantity: 100,
              expiryDate: DateTime.now().add(const Duration(days: 10)),
              batchId: 'b2',
              arrivalDate: DateTime.now(),
              initialQuantity: 100,
              unit: 'box',
              lastUpdated: DateTime.now()),
        ]
      };

      final req = [
        MedRequest(
            id: 'req1',
            facilityId: 'r1',
            medicineName: 'A',
            quantity: 50,
            requestDate: DateTime.now(),
            type: RequestType.shortage,
            status: RequestStatus.pending),
        MedRequest(
            id: 'req2',
            facilityId: 'r2',
            medicineName: 'B',
            quantity: 50,
            requestDate: DateTime.now(),
            type: RequestType.shortage,
            status: RequestStatus.pending),
      ];

      final multiRoutes = service.calculateMultiStopRoutes(
        facilities: [f1, f2, f3],
        inventories: inv,
        requests: req,
      );

      expect(multiRoutes.length, 1);
      final mr = multiRoutes.first;
      expect(mr.transfers.length, 2);

      expect(mr.stops.length, 3);
      expect(mr.stops[0].id, 'd1');
      expect(mr.stops[1].id, 'r2');
      expect(mr.stops[2].id, 'r1');
    });
    test('calculateMultiStopRoutes creates separate routes for multiple donors',
        () {
      final d1 = Facility(
          id: 'd1',
          name: 'Donor 1',
          type: 'hospital',
          latitude: 0,
          longitude: 0,
          email: 'test@example.com',
          region: 'test',
          createdAt: DateTime.now());
      final d2 = Facility(
          id: 'd2',
          name: 'Donor 2',
          type: 'hospital',
          latitude: 5,
          longitude: 5,
          email: 'test@example.com',
          region: 'test',
          createdAt: DateTime.now());
      final r1 = Facility(
          id: 'r1',
          name: 'Rec 1',
          type: 'clinic',
          latitude: 10,
          longitude: 10,
          email: 'test@example.com',
          region: 'test',
          createdAt: DateTime.now());
      final r2 = Facility(
          id: 'r2',
          name: 'Rec 2',
          type: 'clinic',
          latitude: 1,
          longitude: 1,
          email: 'test@example.com',
          region: 'test',
          createdAt: DateTime.now());

      final inv = {
        'd1': [
          InventoryItem(
              id: 'i1',
              facilityId: 'd1',
              medicineName: 'A',
              remainingQuantity: 100,
              expiryDate: DateTime.now().add(const Duration(days: 10)),
              batchId: 'b1',
              arrivalDate: DateTime.now(),
              initialQuantity: 100,
              unit: 'box',
              lastUpdated: DateTime.now()),
        ],
        'd2': [
          InventoryItem(
              id: 'i2',
              facilityId: 'd2',
              medicineName: 'B',
              remainingQuantity: 100,
              expiryDate: DateTime.now().add(const Duration(days: 10)),
              batchId: 'b2',
              arrivalDate: DateTime.now(),
              initialQuantity: 100,
              unit: 'box',
              lastUpdated: DateTime.now()),
        ]
      };

      final req = [
        MedRequest(
            id: 'req1',
            facilityId: 'r1',
            medicineName: 'A',
            quantity: 50,
            requestDate: DateTime.now(),
            type: RequestType.shortage,
            status: RequestStatus.pending),
        MedRequest(
            id: 'req2',
            facilityId: 'r2',
            medicineName: 'B',
            quantity: 50,
            requestDate: DateTime.now(),
            type: RequestType.shortage,
            status: RequestStatus.pending),
      ];

      final multiRoutes = service.calculateMultiStopRoutes(
        facilities: [d1, d2, r1, r2],
        inventories: inv,
        requests: req,
      );

      expect(multiRoutes.length, 2);

      expect(
        multiRoutes.map((r) => r.stops.first.id),
        containsAll(['d1', 'd2']),
      );
    });
  });
}
