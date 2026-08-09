import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/services/simulation_service.dart';

void main() {
  group('SimulationService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late SimulationService simulationService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      simulationService = SimulationService(fakeFirestore);
    });

    test('demoMedicineCatalog single source of truth is consistent', () {
      expect(SimulationService.demoMedicineCatalog, isNotEmpty);
      expect(
        SimulationService.demoMedicineCatalog.keys,
        containsAll([
          'Paracetamol',
          'Cough Syrup',
          'ORS',
          'Antibiotic',
          'Vitamin Tablets',
          'Metformin 500mg',
          'Iron Folic Acid',
          'Amoxicillin 250mg',
        ]),
      );
      expect(
        SimulationService.demoMedicineNames,
        equals(SimulationService.demoMedicineCatalog.keys.toList()),
      );
      expect(SimulationService.defaultDemoFacilityId, equals('rampur_mediflow_com'));
    });

    test('generateRealisticProfile returns valid facility map', () {
      final profile = simulationService.generateRealisticProfile(type: 'rural');
      expect(profile['type'], equals('rural'));
      expect(profile['latitude'], isA<double>());
      expect(profile['longitude'], isA<double>());
      expect(profile['region'], isNotNull);
      expect(profile['createdAt'], isNotNull);
    });

    test('runFullSimulation seeds inventory and daily logs for demo facility', () async {
      const demoId = SimulationService.defaultDemoFacilityId;

      await simulationService.runFullSimulation(demoId, 'rural');

      // Verify inventory documents match demo medicine catalog
      final invSnapshot = await fakeFirestore
          .collection('inventory')
          .doc(demoId)
          .collection('medicines')
          .get();

      expect(invSnapshot.docs.length, equals(SimulationService.demoMedicineCatalog.length));

      final paracetamolDoc = invSnapshot.docs.firstWhere(
        (doc) => doc.data()['medicineName'] == 'Paracetamol',
      );
      expect(paracetamolDoc.data()['unit'], equals('tablets'));
      // Demo persona profile for Paracetamol sets expired date (-5 days)
      final DateTime expiry =
          (paracetamolDoc.data()['expiryDate'] as Timestamp).toDate();
      expect(expiry.isBefore(DateTime.now()), isTrue);

      // Verify 31 daily logs were seeded
      final logsSnapshot = await fakeFirestore
          .collection('daily_usage_logs')
          .doc(demoId)
          .collection('logs')
          .get();

      expect(logsSnapshot.docs.length, equals(31));
    });

    test('runFullSimulation with custom demoFacilityId parameter applies demo persona', () async {
      const customDemoId = 'custom_demo_facility';

      await simulationService.runFullSimulation(
        customDemoId,
        'urban',
        demoFacilityId: customDemoId,
      );

      final invSnapshot = await fakeFirestore
          .collection('inventory')
          .doc(customDemoId)
          .collection('medicines')
          .get();

      expect(invSnapshot.docs.length, equals(SimulationService.demoMedicineCatalog.length));

      // ORS demo persona sets remaining to 95% of initial
      final orsDoc = invSnapshot.docs.firstWhere(
        (doc) => doc.data()['medicineName'] == 'ORS',
      );
      final int initial = orsDoc.data()['initialQuantity'] as int;
      final int remaining = orsDoc.data()['remainingQuantity'] as int;
      expect(remaining, equals((initial * 0.95).round()));
    });
  });
}
