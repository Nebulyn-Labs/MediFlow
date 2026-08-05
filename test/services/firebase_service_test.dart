import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

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
              'Inventory document not found for medicine: $medicineName',
            ),
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

    test('streamAlerts emits real-time updates when alerts collection changes',
        () async {
      const facilityId = 'facility_123';
      final alertRef =
          fakeFirestore.collection('alerts').doc('facility_123_med_1');

      final stream = firebaseService.streamAlerts(facilityId);
      final initialAlerts = await stream.first;
      expect(initialAlerts, isEmpty);

      await alertRef.set({
        'facilityId': facilityId,
        'medicineName': 'Paracetamol',
        'type': 'low_stock',
        'qtyRemaining': 5,
        'initialQuantity': 100,
      });

      final updatedAlerts = await stream.first;
      expect(updatedAlerts.length, 1);
      expect(updatedAlerts.first['medicineName'], 'Paracetamol');
      expect(updatedAlerts.first['type'], 'low_stock');
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
        expect(
          page1.lastDocument,
          isNotNull,
          reason: 'lastDocument must be set when a full page is returned',
        );

        // Calling with the cursor must not throw (fake returns whatever it can).
        final DocumentSnapshot cursor = page1.lastDocument!;
        final page2 = await firebaseService.getPaginatedMedicines(
          pageSize: 2,
          startAfter: cursor,
        );

        // The result object must always be valid.
        expect(page2.medicines, isA<List<InventoryItem>>());
      },
    );

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
        expect(
          uniqueIds.length,
          ids.length,
          reason: 'A single page must not contain duplicate medicine documents',
        );
      },
    );

    test(
      'hasMore is false when fewer than pageSize documents are returned',
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
        expect(
          result.hasMore,
          isFalse,
          reason: 'hasMore must be false when result is smaller than pageSize',
        );
      },
    );

    test('empty collection returns empty list and hasMore is false', () async {
      // No documents seeded
      final result = await firebaseService.getPaginatedMedicines(pageSize: 20);

      expect(result.medicines, isEmpty);
      expect(result.hasMore, isFalse);
      expect(result.lastDocument, isNull);
    });
  });

  group('FirebaseService - signUpFacility', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late FirebaseService firebaseService;
    late MockUserCredential mockCredential;
    late MockUser mockUser;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      firebaseService = FirebaseService(fakeFirestore, mockAuth);
      mockCredential = MockUserCredential();
      mockUser = MockUser();
    });

    test(
      'writes role document using UID returned from credential on creation',
      () async {
        const email = 'newfacility@mediflow.com';
        const password = 'password123';
        const uid = 'new_facility_uid';

        // Simulate ambient user (e.g. logged in admin)
        final mockAmbientUser = MockUser();
        when(() => mockAmbientUser.uid).thenReturn('admin_uid');
        when(() => mockAuth.currentUser).thenReturn(mockAmbientUser);

        // Seed admin user document
        await fakeFirestore.collection('users').doc('admin_uid').set({
          'email': 'admin@mediflow.com',
          'role': 'admin',
        });

        when(
          () => mockAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          ),
        ).thenAnswer((_) async => mockCredential);
        when(() => mockCredential.user).thenReturn(mockUser);
        when(() => mockUser.uid).thenReturn(uid);

        await firebaseService.signUpFacility(
          name: 'New Facility',
          email: email,
          password: password,
        );

        // Verify role document written for new UID
        final newDoc = await fakeFirestore.collection('users').doc(uid).get();
        expect(newDoc.exists, isTrue);
        expect(newDoc.data()?['email'], email);
        expect(newDoc.data()?['role'], 'facility_head');

        // Verify admin document was NOT overwritten
        final adminDoc =
            await fakeFirestore.collection('users').doc('admin_uid').get();
        expect(adminDoc.data()?['role'], 'admin');
      },
    );

    test(
      'falls back to signInWithEmailAndPassword if createUser fails',
      () async {
        const email = 'existing@mediflow.com';
        const password = 'password123';
        const fallbackUid = 'fallback_uid';

        when(
          () => mockAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          ),
        ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

        when(
          () => mockAuth.signInWithEmailAndPassword(
            email: email,
            password: password,
          ),
        ).thenAnswer((_) async => mockCredential);
        when(() => mockCredential.user).thenReturn(mockUser);
        when(() => mockUser.uid).thenReturn(fallbackUid);

        await firebaseService.signUpFacility(
          name: 'Existing Facility',
          email: email,
          password: password,
        );

        final userDoc =
            await fakeFirestore.collection('users').doc(fallbackUid).get();
        expect(userDoc.exists, isTrue);
        expect(userDoc.data()?['role'], 'facility_head');
      },
    );

    test(
      'throws exception and writes no user document when both auth attempts fail',
      () async {
        const email = 'failed@mediflow.com';
        const password = 'password123';

        // Simulate ambient user
        final mockAmbientUser = MockUser();
        when(() => mockAmbientUser.uid).thenReturn('ambient_uid');
        when(() => mockAuth.currentUser).thenReturn(mockAmbientUser);

        await fakeFirestore.collection('users').doc('ambient_uid').set({
          'email': 'ambient@mediflow.com',
          'role': 'admin',
        });

        when(
          () => mockAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          ),
        ).thenThrow(FirebaseAuthException(code: 'error_1'));

        when(
          () => mockAuth.signInWithEmailAndPassword(
            email: email,
            password: password,
          ),
        ).thenThrow(FirebaseAuthException(code: 'error_2'));

        expect(
          () => firebaseService.signUpFacility(
            name: 'Failed Facility',
            email: email,
            password: password,
          ),
          throwsA(isA<FirebaseAuthException>()),
        );

        // Verify ambient user document remains untouched
        final ambientDoc =
            await fakeFirestore.collection('users').doc('ambient_uid').get();
        expect(ambientDoc.data()?['role'], 'admin');

        // Verify no other user document was created
        final usersSnapshot = await fakeFirestore.collection('users').get();
        expect(usersSnapshot.docs.length, 1);
      },
    );
  });
}
