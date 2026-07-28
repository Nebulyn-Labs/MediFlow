import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

void main() {
  group('FirebaseService - logUsage', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late FirebaseService firebaseService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      firebaseService = FirebaseService(fakeFirestore, mockAuth);
    });

    test('auto-seeds inventory document when it is missing during logUsage', () async {
      const facilityId = 'facility_123';
      const medicineName = 'NonExistentMeds';
      final date = DateTime.now();
      const quantity = 10;
      const patients = 2;

      // Note: We intentionally do NOT create the inventory document in fakeFirestore beforehand.
      await firebaseService.logUsage(
        facilityId: facilityId,
        date: date,
        medicineName: medicineName,
        quantity: quantity,
        patients: patients,
      );

      // Verify that the inventory document was auto-seeded as expected for bulk imports
      final invSnap = await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .doc('nonexistentmeds')
          .get();
      expect(invSnap.exists, isTrue);
      expect(invSnap.data()!['medicineName'], equals(medicineName));
    });
  });
}
