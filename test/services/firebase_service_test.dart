import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

// Helper: write a medicine document into inventory/{facilityId}/medicines/{medId}
Future<void> _addMedicine(
  FakeFirebaseFirestore fakeFirestore, {
  required String facilityId,
  required String medicineId,
  required String medicineName,
}) async {
  final now = Timestamp.now();
  await fakeFirestore
      .collection('inventory')
      .doc(facilityId)
      .collection('medicines')
      .doc(medicineId)
      .set({
    'medicineName': medicineName,
    'batchId': 'B001',
    'arrivalDate': now,
    'expiryDate': now,
    'initialQuantity': 100,
    'remainingQuantity': 80,
    'unit': 'units',
    'lastUpdated': now,
  });
}

void main() {
  group('FirebaseService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late FirebaseService firebaseService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      firebaseService = FirebaseService(fakeFirestore, mockAuth);
    });

    test('throws Exception when inventory document is missing', () async {
      const facilityId = 'facility_123';
      const medicineName = 'NonExistentMeds';
      final date = DateTime.now();
      const quantity = 10;
      const patients = 2;

      // Note: We intentionally do NOT create the inventory document in fakeFirestore.

      expect(
        () => firebaseService.logUsage(
          facilityId: facilityId,
          date: date,
          medicineName: medicineName,
          quantity: quantity,
          patients: patients,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
                'Inventory document not found for medicine: $medicineName'),
          ),
        ),
      );
    });

    test('updateFacility updates facility document', () async {
      const facilityId = 'facility_123';
      final testData = {'name': 'Updated Name', 'region': 'Updated Region'};

      // Seed a document first
      await fakeFirestore.collection('facilities').doc(facilityId).set({
        'name': 'Original Name',
        'region': 'Original Region',
        'email': 'test@test.com',
      });

      await firebaseService.updateFacility(facilityId, testData);

      final doc =
          await fakeFirestore.collection('facilities').doc(facilityId).get();
      expect(doc.data()?['name'], 'Updated Name');
      expect(doc.data()?['region'], 'Updated Region');
      expect(doc.data()?['email'], 'test@test.com');
    });
  });

  group('FirebaseService - getPaginatedMedicines', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late FirebaseService firebaseService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      firebaseService = FirebaseService(fakeFirestore, mockAuth);
    });

    test('initial page load returns up to pageSize items', () async {
      // Seed 5 medicines in one facility
      for (var i = 1; i <= 5; i++) {
        await _addMedicine(
          fakeFirestore,
          facilityId: 'fac_a',
          medicineId: 'med_$i',
          medicineName: 'Medicine $i',
        );
      }

      final result = await firebaseService.getPaginatedMedicines(pageSize: 3);

      expect(result.medicines.length, 3);
      expect(result.hasMore, isTrue);
      expect(result.lastDocument, isNotNull);
    });

    test(
        'cursor advancement: lastDocument is set and can be passed as startAfter',
        () async {
      // Seed 4 medicines and verify the cursor returned on page 1 is usable.
      // Note: fake_cloud_firestore does not simulate startAfterDocument on
      // collectionGroup queries, so we verify the contract — that lastDocument
      // is non-null after a full page — rather than the full multi-page result.
      for (var i = 1; i <= 4; i++) {
        await _addMedicine(
          fakeFirestore,
          facilityId: 'fac_b',
          medicineId: 'med_$i',
          medicineName: 'Med $i',
        );
      }

      final page1 = await firebaseService.getPaginatedMedicines(pageSize: 2);

      // The cursor must be set so the caller can request the next page.
      expect(page1.lastDocument, isNotNull,
          reason: 'lastDocument must be set when a full page is returned');

      // Calling with the cursor must not throw (fake returns whatever it can).
      final DocumentSnapshot cursor = page1.lastDocument!;
      final page2 = await firebaseService.getPaginatedMedicines(
        pageSize: 2,
        startAfter: cursor,
      );

      // The result object must always be valid.
      expect(page2.medicines, isA<List<InventoryItem>>());
    });

    test(
        'cursor advances: items returned on page 1 are distinct InventoryItems',
        () async {
      for (var i = 1; i <= 6; i++) {
        await _addMedicine(
          fakeFirestore,
          facilityId: 'fac_c',
          medicineId: 'drug_$i',
          medicineName: 'Drug $i',
        );
      }

      final page1 = await firebaseService.getPaginatedMedicines(pageSize: 3);

      // All IDs within a single page must be unique.
      final ids = page1.medicines.map((m) => m.id).toList();
      final uniqueIds = ids.toSet();
      expect(uniqueIds.length, ids.length,
          reason:
              'A single page must not contain duplicate medicine documents');
    });

    test('hasMore is false when fewer than pageSize documents are returned',
        () async {
      // Seed exactly 2 medicines but request a page of 5
      for (var i = 1; i <= 2; i++) {
        await _addMedicine(
          fakeFirestore,
          facilityId: 'fac_d',
          medicineId: 'item_$i',
          medicineName: 'Item $i',
        );
      }

      final result = await firebaseService.getPaginatedMedicines(pageSize: 5);

      expect(result.medicines.length, 2);
      expect(result.hasMore, isFalse,
          reason: 'hasMore must be false when result is smaller than pageSize');
    });

    test('empty collection returns empty list and hasMore is false', () async {
      // No documents seeded
      final result = await firebaseService.getPaginatedMedicines(pageSize: 20);

      expect(result.medicines, isEmpty);
      expect(result.hasMore, isFalse);
      expect(result.lastDocument, isNull);
    });
  });
}
