import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/optimization_service.dart';

void main() {
  group('OptimizationService', () {
    late OptimizationService service;
    final now = DateTime.now();

    setUp(() {
      service = OptimizationService();
    });

    // Helpers to create entities easily
    Facility createFacility(String id, String type, double lat, double lng) {
      return Facility(
        id: id,
        name: 'Facility $id',
        email: '$id@test.com',
        type: type,
        region: 'Region A',
        latitude: lat,
        longitude: lng,
        createdAt: now,
      );
    }

    InventoryItem createInventory(
        String facilityId, String medName, int initial, int remaining) {
      return InventoryItem(
        id: 'inv_$facilityId',
        medicineName: medName,
        batchId: 'B1',
        arrivalDate: now,
        expiryDate: now.add(const Duration(days: 180)),
        initialQuantity: initial,
        remainingQuantity: remaining,
        unit: 'tablets',
        lastUpdated: now,
        facilityId: facilityId,
      );
    }

    MedRequest createRequest(String id, String facilityId, String medName,
        RequestType type, int quantity) {
      return MedRequest(
        id: id,
        facilityId: facilityId,
        medicineName: medName,
        type: type,
        quantity: quantity,
        requestDate: now,
        status: RequestStatus.pending,
      );
    }

    test('returns empty list when there are no requests', () {
      final result = service.calculateOptimalTransfers(
        facilities: [],
        inventories: {},
        requests: [],
      );

      expect(result, isEmpty);
    });

    test('returns empty recommendations when no donor has surplus', () {
      final donor = createFacility('d1', 'urban', 28.6, 77.2);
      final recipient = createFacility('r1', 'rural', 28.7, 77.3);
      final inventory = createInventory(
          donor.id, 'Paracetamol', 100, 30); // 30 is exactly 30%, no surplus
      final request = createRequest(
          'req1', recipient.id, 'Paracetamol', RequestType.shortage, 20);

      final result = service.calculateOptimalTransfers(
        facilities: [donor, recipient],
        inventories: {
          donor.id: [inventory]
        },
        requests: [request],
      );

      expect(result, isEmpty);
    });

    test('returns empty recommendations when empty inventories', () {
      final donor = createFacility('d1', 'urban', 28.6, 77.2);
      final recipient = createFacility('r1', 'rural', 28.7, 77.3);
      final request = createRequest(
          'req1', recipient.id, 'Paracetamol', RequestType.shortage, 20);

      final result = service.calculateOptimalTransfers(
        facilities: [donor, recipient],
        inventories: {donor.id: []},
        requests: [request],
      );

      expect(result, isEmpty);
    });

    test('returns empty recommendations when medicine mismatch', () {
      final donor = createFacility('d1', 'urban', 28.6, 77.2);
      final recipient = createFacility('r1', 'rural', 28.7, 77.3);
      final inventory = createInventory(donor.id, 'Ibuprofen', 100, 100);
      final request = createRequest(
          'req1', recipient.id, 'Paracetamol', RequestType.shortage, 20);

      final result = service.calculateOptimalTransfers(
        facilities: [donor, recipient],
        inventories: {
          donor.id: [inventory]
        },
        requests: [request],
      );

      expect(result, isEmpty);
    });

    test('rural requests are prioritized over urban requests', () {
      // Setup one donor with limited surplus, and two requests (rural and urban).
      final donor = createFacility('d1', 'urban', 28.6, 77.2);
      final recipientUrban = createFacility('r_urban', 'urban', 28.7, 77.3);
      final recipientRural = createFacility('r_rural', 'rural', 28.7, 77.3);

      // Donor has 50 surplus
      final inventory = createInventory(donor.id, 'ORS', 100, 80);

      final reqUrban = createRequest(
          'reqU', recipientUrban.id, 'ORS', RequestType.regularIndent, 50);
      final reqRural = createRequest(
          'reqR', recipientRural.id, 'ORS', RequestType.regularIndent, 50);

      final result = service.calculateOptimalTransfers(
        facilities: [donor, recipientUrban, recipientRural],
        inventories: {
          donor.id: [inventory]
        },
        requests: [reqUrban, reqRural],
      );

      expect(result.length, 1);
      expect(result.first.recipient.id, 'r_rural'); // Rural should get it first
    });

    test('distance prioritization chooses closer donor', () {
      final donorClose = createFacility(
          'd_close', 'urban', 28.61, 77.21); // Close to recipient
      final donorFar =
          createFacility('d_far', 'urban', 29.0, 78.0); // Far from recipient
      final recipient = createFacility('r1', 'urban', 28.6, 77.2);

      final invClose =
          createInventory(donorClose.id, 'ORS', 100, 100); // 70 surplus
      final invFar =
          createInventory(donorFar.id, 'ORS', 100, 100); // 70 surplus

      final request =
          createRequest('req1', recipient.id, 'ORS', RequestType.shortage, 40);

      final result = service.calculateOptimalTransfers(
        facilities: [donorClose, donorFar, recipient],
        inventories: {
          donorClose.id: [invClose],
          donorFar.id: [invFar],
        },
        requests: [request],
      );

      expect(result.length, 1);
      expect(result.first.donor.id, 'd_close');
    });

    test('quantity matching chooses full fulfillment over partial fulfillment',
        () {
      final donorPartial = createFacility('d_partial', 'urban', 28.61, 77.21);
      final donorFull = createFacility(
          'd_full', 'urban', 28.62, 77.22); // Slightly further but full qty
      final recipient = createFacility('r1', 'urban', 28.6, 77.2);

      final invPartial =
          createInventory(donorPartial.id, 'ORS', 100, 50); // 20 surplus
      final invFull =
          createInventory(donorFull.id, 'ORS', 100, 100); // 70 surplus

      final request =
          createRequest('req1', recipient.id, 'ORS', RequestType.shortage, 40);

      final result = service.calculateOptimalTransfers(
        facilities: [donorPartial, donorFull, recipient],
        inventories: {
          donorPartial.id: [invPartial],
          donorFull.id: [invFull],
        },
        requests: [request],
      );

      expect(result.length, 1);
      expect(result.first.donor.id, 'd_full');
      expect(result.first.quantity, 40);
    });

    test('multiple recommendations generated to fulfill large request', () {
      final donor1 = createFacility('d1', 'urban', 28.61, 77.21);
      final donor2 = createFacility('d2', 'urban', 28.62, 77.22);
      final recipient = createFacility('r1', 'urban', 28.6, 77.2);

      final inv1 = createInventory(donor1.id, 'ORS', 100, 50); // 20 surplus
      final inv2 = createInventory(donor2.id, 'ORS', 100, 60); // 30 surplus

      // Need 40. Should take from both.
      final request =
          createRequest('req1', recipient.id, 'ORS', RequestType.shortage, 40);

      final result = service.calculateOptimalTransfers(
        facilities: [donor1, donor2, recipient],
        inventories: {
          donor1.id: [inv1],
          donor2.id: [inv2],
        },
        requests: [request],
      );

      expect(result.length, 2);
      final totalQty = result.fold<int>(0, (sum, rec) => sum + rec.quantity);
      expect(totalQty, 40);
      expect(result.map((r) => r.donor.id).toSet(), containsAll(['d1', 'd2']));
    });

    test('explicit surplus offers take precedence or add to surplus', () {
      final donor = createFacility('d1', 'urban', 28.6, 77.2);
      final recipient = createFacility('r1', 'rural', 28.7, 77.3);
      final inventory =
          createInventory(donor.id, 'Paracetamol', 100, 30); // 0 live surplus

      // Explicit surplus offer of 50
      final explicitSurplus = createRequest(
          'req_surplus', donor.id, 'Paracetamol', RequestType.surplus, 50);
      final request = createRequest('req_shortage', recipient.id, 'Paracetamol',
          RequestType.shortage, 20);

      final result = service.calculateOptimalTransfers(
        facilities: [donor, recipient],
        inventories: {
          donor.id: [inventory]
        },
        requests: [explicitSurplus, request],
      );

      expect(result.length, 1);
      expect(result.first.quantity, 20);
    });

    test('ignores self transfers', () {
      final facility = createFacility('f1', 'urban', 28.6, 77.2);
      final inventory =
          createInventory(facility.id, 'Paracetamol', 100, 100); // 70 surplus
      final request = createRequest(
          'req1', facility.id, 'Paracetamol', RequestType.shortage, 20);

      final result = service.calculateOptimalTransfers(
        facilities: [facility],
        inventories: {
          facility.id: [inventory]
        },
        requests: [request],
      );

      expect(result, isEmpty);
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
