import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/optimization_service.dart';

void main() {
  group('OptimizationService', () {
    test('skips requests that reference a missing facility', () {
      final service = OptimizationService();
      final now = DateTime.now();

      final donorFacility = Facility(
        id: 'facility-donor',
        name: 'Urban District Hospital',
        email: 'donor@mediflow.com',
        type: 'urban',
        region: 'UP',
        latitude: 28.6149,
        longitude: 77.2100,
        createdAt: now,
      );

      final recipientFacility = Facility(
        id: 'facility-recipient',
        name: 'Rural PHC',
        email: 'recipient@mediflow.com',
        type: 'rural',
        region: 'UP',
        latitude: 28.6139,
        longitude: 77.2090,
        createdAt: now,
      );

      final validRequest = MedRequest(
        id: 'req-valid',
        facilityId: recipientFacility.id,
        medicineName: 'Paracetamol',
        type: RequestType.regularIndent,
        quantity: 100,
        requestDate: now,
        status: RequestStatus.pending,
      );

      final orphanRequest = MedRequest(
        id: 'req-orphan',
        facilityId: 'missing-facility',
        medicineName: 'Paracetamol',
        type: RequestType.regularIndent,
        quantity: 75,
        requestDate: now,
        status: RequestStatus.pending,
      );

      final surplusInventory = InventoryItem(
        id: 'inv-donor-1',
        medicineName: 'Paracetamol',
        batchId: 'batch-001',
        arrivalDate: now,
        expiryDate: now.add(const Duration(days: 90)),
        initialQuantity: 1000,
        remainingQuantity: 700,
        unit: 'tablets',
        lastUpdated: now,
        facilityId: donorFacility.id,
      );

      final recommendations = service.calculateOptimalTransfers(
        facilities: [donorFacility, recipientFacility],
        inventories: {
          donorFacility.id: [surplusInventory],
          recipientFacility.id: const [],
        },
        requests: [orphanRequest, validRequest],
      );

      expect(recommendations, hasLength(1));
      expect(recommendations.first.donor.id, donorFacility.id);
      expect(recommendations.first.recipient.id, recipientFacility.id);
      expect(recommendations.first.quantity, 100);
      expect(recommendations.first.medicine, 'Paracetamol');
    });
  });
}
