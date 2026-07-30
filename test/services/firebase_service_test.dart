import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements auth.FirebaseAuth {}

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirebaseService firebaseService;
  late MockFirebaseAuth mockAuth;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth();
    firebaseService = FirebaseService(fakeFirestore, mockAuth);
  });

  group('disposeInventory', () {
    test('throws exception when inventory document does not exist', () async {
      const facilityId = 'facility_1';
      const medicineName = 'Paracetamol';

      expect(
        () => firebaseService.disposeInventory(facilityId, medicineName),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Inventory document not found for medicine: Paracetamol'),
        )),
      );
    });

    test('successfully zeroes inventory, records wastage, and deletes alert', () async {
      const facilityId = 'facility_1';
      const medicineName = 'Paracetamol';
      const medicineId = 'paracetamol';

      // 1. Setup inventory document
      await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .doc(medicineId)
          .set({
        'medicineName': medicineName,
        'batchId': 'BATCH-001',
        'remainingQuantity': 50,
        'unit': 'boxes',
        'lastUpdated': Timestamp.now(),
      });

      // 2. Setup alert document
      final alertRef = await fakeFirestore.collection('alerts').add({
        'facilityId': facilityId,
        'medicineName': medicineName,
        'type': 'expired',
      });

      // 3. Execute disposal
      await firebaseService.disposeInventory(facilityId, medicineName);

      // 4. Verify inventory is zeroed
      final invDoc = await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .doc(medicineId)
          .get();
      expect(invDoc.data()?['remainingQuantity'], 0);

      // 5. Verify wastage log is created durably
      final wastageSnapshot = await fakeFirestore.collection('wastage_logs').get();
      expect(wastageSnapshot.docs.length, 1);
      final wastageData = wastageSnapshot.docs.first.data();
      expect(wastageData['facilityId'], facilityId);
      expect(wastageData['medicineName'], medicineName);
      expect(wastageData['batchId'], 'BATCH-001');
      expect(wastageData['quantityDestroyed'], 50);
      expect(wastageData['unit'], 'boxes');

      // 6. Verify alert is deleted so it doesn't show up again
      final alertDoc = await alertRef.get();
      expect(alertDoc.exists, false);
    });
  });
}
