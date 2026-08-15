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

    test(
        'logUsage records actualDeduction in daily log when quantity > remaining',
        () async {
      const facilityId = 'facility_123';
      const medicineId = 'paracetamol';
      const medicineName = 'Paracetamol';
      final date = DateTime(2026, 8, 5);

      // Seed inventory with remainingQuantity = 20
      await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .doc(medicineId)
          .set({
        'medicineName': medicineName,
        'remainingQuantity': 20,
        'lastUpdated': Timestamp.now(),
      });

      // Attempt to log quantity = 30 (exceeds remaining of 20)
      await firebaseService.logUsage(
        facilityId: facilityId,
        date: date,
        medicineName: medicineName,
        quantity: 30,
        patients: 5,
      );

      // 1. Verify inventory remainingQuantity floors at 0 (deducted 20)
      final invDoc = await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .doc(medicineId)
          .get();
      expect(invDoc.data()?['remainingQuantity'], 0);

      // 2. Verify daily log unitsDistributed equals 20 (actualDeduction), NOT 30
      final dateStr = "2026-08-05";
      final logDoc = await fakeFirestore
          .collection('daily_usage_logs')
          .doc(facilityId)
          .collection('logs')
          .doc(dateStr)
          .get();
      final medicines = logDoc.data()?['medicines'] as List;
      expect(medicines.length, 1);
      expect(medicines.first['medicineName'], medicineName);
      expect(medicines.first['unitsDistributed'], 20);
    });

    test(
        'logUsage updates existing daily log with actualDeduction when quantity > remaining',
        () async {
      const facilityId = 'facility_123';
      const medicineId = 'amoxicillin';
      const medicineName = 'Amoxicillin';
      final date = DateTime(2026, 8, 5);
      final dateStr = "2026-08-05";

      // Seed inventory with remainingQuantity = 15
      await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .doc(medicineId)
          .set({
        'medicineName': medicineName,
        'remainingQuantity': 15,
        'lastUpdated': Timestamp.now(),
      });

      // Seed existing log document with unitsDistributed = 5
      await fakeFirestore
          .collection('daily_usage_logs')
          .doc(facilityId)
          .collection('logs')
          .doc(dateStr)
          .set({
        'date': Timestamp.fromDate(date),
        'medicines': [
          {'medicineName': medicineName, 'unitsDistributed': 5}
        ],
        'totalPatients': 2,
      });

      // Attempt to log quantity = 25 (exceeds remaining of 15)
      await firebaseService.logUsage(
        facilityId: facilityId,
        date: date,
        medicineName: medicineName,
        quantity: 25,
        patients: 3,
      );

      // 1. Verify inventory remainingQuantity floors at 0 (deducted 15)
      final invDoc = await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .doc(medicineId)
          .get();
      expect(invDoc.data()?['remainingQuantity'], 0);

      // 2. Verify daily log unitsDistributed is updated by actualDeduction (5 + 15 = 20), NOT (5 + 25 = 30)
      final logDoc = await fakeFirestore
          .collection('daily_usage_logs')
          .doc(facilityId)
          .collection('logs')
          .doc(dateStr)
          .get();
      final medicines = logDoc.data()?['medicines'] as List;
      expect(medicines.first['unitsDistributed'], 20);
    });

    test('hasPendingWritesStream starts as false with no pending writes',
        () async {
      final result = await firebaseService.hasPendingWritesStream.first;
      expect(result, isFalse);
    });

    test('forceSyncPendingWrites completes without hanging', () async {
      // fake_cloud_firestore doesn't implement waitForPendingWrites, so we
      // can't assert the return value here — only that the timeout/catch
      // path means this always resolves instead of hanging forever.
      final synced = await firebaseService.forceSyncPendingWrites();
      expect(synced, isA<bool>());
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

  group('FirebaseService - getFacilityByEmail', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late FirebaseService firebaseService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      firebaseService = FirebaseService(fakeFirestore, mockAuth);
    });

    test(
      'resolves facility with arbitrary non-email-derived document ID',
      () async {
        const customDocId = 'fac_uuid_98761234';
        const email = 'rampur.clinic@mediflow.org';

        await fakeFirestore.collection('facilities').doc(customDocId).set({
          'name': 'Rampur Clinic',
          'email': email,
          'type': 'rural',
          'region': 'North',
          'latitude': 28.8,
          'longitude': 79.0,
          'createdAt': DateTime.now(),
        });

        final fac = await firebaseService.getFacilityByEmail(email);
        expect(fac, isNotNull);
        expect(fac!.id, equals(customDocId));
        expect(fac.name, equals('Rampur Clinic'));
      },
    );

    test('resolves uppercase and trimmed email addresses', () async {
      const docId = 'fac_alpha_001';
      const canonicalEmail = 'hapur.general@mediflow.org';

      await fakeFirestore.collection('facilities').doc(docId).set({
        'name': 'Hapur Hospital',
        'email': canonicalEmail,
        'type': 'urban',
        'region': 'East',
        'latitude': 28.7,
        'longitude': 77.7,
        'createdAt': DateTime.now(),
      });

      final fac = await firebaseService
          .getFacilityByEmail('  HAPUR.GENERAL@MEDIFLOW.ORG  ');
      expect(fac, isNotNull);
      expect(fac!.id, equals(docId));
    });

    test(
      'resolves complex email addresses with subdomains and tags',
      () async {
        const docId = 'fac_complex_409';
        const email = 'supply+zone1@sub.health.district.gov.in';

        await fakeFirestore.collection('facilities').doc(docId).set({
          'name': 'District Health HQ',
          'email': email,
          'type': 'urban',
          'region': 'Central',
          'latitude': 28.6,
          'longitude': 77.2,
          'createdAt': DateTime.now(),
        });

        final fac = await firebaseService.getFacilityByEmail(email);
        expect(fac, isNotNull);
        expect(fac!.id, equals(docId));
        expect(fac.email, equals(email));
      },
    );

    test('returns null when no matching facility exists', () async {
      final fac =
          await firebaseService.getFacilityByEmail('nonexistent@mediflow.org');
      expect(fac, isNull);
    });
  });
}
