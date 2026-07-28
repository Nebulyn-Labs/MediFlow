import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

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

      final doc = await fakeFirestore.collection('facilities').doc(facilityId).get();
      expect(doc.data()?['name'], 'Updated Name');
      expect(doc.data()?['region'], 'Updated Region');
      expect(doc.data()?['email'], 'test@test.com');
    });
  });
}
