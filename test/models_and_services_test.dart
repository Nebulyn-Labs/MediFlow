import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/optimization_service.dart';

void main() {
  group('MediFlow Models & Optimization Tests', () {
    test('Facility mapping test', () {
      final now = DateTime.now();
      final map = {
        'name': 'Rampur PHC',
        'email': 'rampur@mediflow.com',
        'type': 'rural',
        'region': 'UP',
        'latitude': 28.1234,
        'longitude': 77.5678,
        'createdAt': Timestamp.fromDate(now),
      };

      final facility = Facility.fromMap(map, 'facility_1');
      expect(facility.id, 'facility_1');
      expect(facility.name, 'Rampur PHC');
      expect(facility.type, 'rural');
      expect(facility.latitude, 28.1234);
      expect(facility.longitude, 77.5678);

      final outputMap = facility.toMap();
      expect(outputMap['name'], 'Rampur PHC');
      expect(outputMap['type'], 'rural');
    });

    test('Optimization Heuristic matching logic test', () {
      final optimizationService = OptimizationService();

      // Donors & Recipients
      final ruralClinic = Facility(
        id: 'clinic_rural',
        name: 'Rural PHC',
        email: 'rural@mediflow.com',
        type: 'rural',
        region: 'UP',
        latitude: 28.6139,
        longitude: 77.2090,
        createdAt: DateTime.now(),
      );

      final urbanHospital = Facility(
        id: 'hosp_urban',
        name: 'Urban District Hospital',
        email: 'urban@mediflow.com',
        type: 'urban',
        region: 'UP',
        latitude: 28.6149, // 1.1 km away
        longitude: 77.2100,
        createdAt: DateTime.now(),
      );

      // Rural clinic has shortage (regularIndent request)
      final request = MedRequest(
        id: 'req_1',
        facilityId: 'clinic_rural',
        medicineName: 'Paracetamol',
        type: RequestType.regularIndent,
        quantity: 1000,
        requestDate: DateTime.now(),
        status: RequestStatus.pending,
      );

      // Urban hospital has surplus inventory (remaining > 30% initial).
      // Expiry is set to 180 days to sit unambiguously outside the 90-day
      // near-expiry window, so the +100 bonus is not expected.
      final surplusInventory = InventoryItem(
        id: 'inv_1',
        medicineName: 'Paracetamol',
        batchId: 'batch_xyz',
        arrivalDate: DateTime.now(),
        expiryDate: DateTime.now().add(const Duration(days: 180)),
        initialQuantity: 10000,
        remainingQuantity: 6000, // 30% of initial is 3000, so 3000 is surplus
        unit: 'tablets',
        lastUpdated: DateTime.now(),
        facilityId: 'hosp_urban',
      );

      final recommendations = optimizationService.calculateOptimalTransfers(
        facilities: [ruralClinic, urbanHospital],
        inventories: {
          'clinic_rural': [],
          'hosp_urban': [surplusInventory],
        },
        requests: [request],
      );

      expect(recommendations.length, 1);
      final rec = recommendations.first;
      expect(rec.donor.id, 'hosp_urban');
      expect(rec.recipient.id, 'clinic_rural');
      expect(rec.medicine, 'Paracetamol');
      expect(rec.quantity, 1000);

      // Pin exact expected score derived from documented weights:
      // Distance score: (200 - distKm)
      // Rural Priority: +150
      // Full Fulfillment: +50
      // Near Expiry (180d > 90d): +0 (unambiguously outside 90-day window)
      final distKm = const Distance().call(
            LatLng(urbanHospital.latitude, urbanHospital.longitude),
            LatLng(ruralClinic.latitude, ruralClinic.longitude),
          ) /
          1000;
      final expectedScore = (200 - distKm) + 150 + 50;

      expect(rec.score, expectedScore);
      expect(
        rec.reasoning,
        'Proximity (${distKm.toStringAsFixed(1)}km) + Rural Priority + Full Fulfillment',
      );
    });
  });
}
