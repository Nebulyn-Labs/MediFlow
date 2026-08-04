import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/daily_usage_log.dart';
import 'package:med_supply_prototype/services/simulation_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late SimulationService simulationService;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    simulationService = SimulationService(fakeFirestore);
  });

  group('SimulationService - Profile Generation', () {
    test('generateRealisticProfile generates valid fields with random type when unassigned', () {
      final profile = simulationService.generateRealisticProfile();

      expect(profile['type'], anyOf('urban', 'rural'));
      expect(profile['latitude'], isA<double>());
      expect(profile['longitude'], isA<double>());
      // Delhi NCR center (28.61, 77.20) with max offset ~0.2
      expect((profile['latitude'] as double), closeTo(28.61, 0.3));
      expect((profile['longitude'] as double), closeTo(77.20, 0.3));
      expect(profile['region'], isA<String>());
      expect(
        [
          'North District',
          'South District',
          'East State',
          'West Sector',
          'Central Zone'
        ],
        contains(profile['region']),
      );
      expect(profile['createdAt'], isA<Timestamp>());
    });

    test('generateRealisticProfile respects explicit facility type parameter', () {
      final urbanProfile = simulationService.generateRealisticProfile(type: 'urban');
      expect(urbanProfile['type'], equals('urban'));

      final ruralProfile = simulationService.generateRealisticProfile(type: 'rural');
      expect(ruralProfile['type'], equals('rural'));
    });
  });

  group('SimulationService - Full Simulation Workflow', () {
    test('runFullSimulation creates inventory and 31 days of logs for urban facility', () async {
      const facilityId = 'facility_urban_test';
      await simulationService.runFullSimulation(facilityId, 'urban');

      // 1. Verify Inventory creation
      final inventorySnapshot = await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .get();

      expect(inventorySnapshot.docs.length, equals(8));

      final expectedMedicines = [
        'Paracetamol',
        'Cough Syrup',
        'ORS',
        'Antibiotic',
        'Vitamin Tablets',
        'Metformin 500mg',
        'Iron Folic Acid',
        'Amoxicillin 250mg'
      ];

      final medicineNames =
          inventorySnapshot.docs.map((doc) => doc.data()['medicineName']).toList();
      for (final med in expectedMedicines) {
        expect(medicineNames, contains(med));
      }

      for (final doc in inventorySnapshot.docs) {
        final data = doc.data();
        expect(data['batchId'], startsWith('B-'));
        expect(data['initialQuantity'], greaterThanOrEqualTo(2000));
        expect(data['remainingQuantity'], isA<int>());
        expect(data['unit'], isA<String>());
        expect(data['arrivalDate'], isA<Timestamp>());
        expect(data['expiryDate'], isA<Timestamp>());
        expect(data['lastUpdated'], isA<Timestamp>());
      }

      // 2. Verify 31 days of Daily Usage Logs
      final logsSnapshot = await fakeFirestore
          .collection('daily_usage_logs')
          .doc(facilityId)
          .collection('logs')
          .get();

      expect(logsSnapshot.docs.length, equals(31));

      for (final doc in logsSnapshot.docs) {
        final data = doc.data();
        expect(data['date'], isA<Timestamp>());
        expect(data['totalPatients'], isA<int>());
        // Urban facility base patients is 150 (+/- 20% variation)
        expect(data['totalPatients'], greaterThan(80));
        expect(data['totalPatients'], lessThan(250));

        final medicinesList = data['medicines'] as List;
        expect(medicinesList.length, equals(8));

        final usages = medicinesList
            .map((m) => MedicineUsage.fromMap(Map<String, dynamic>.from(m as Map)))
            .toList();
        for (final usage in usages) {
          expect(usage.medicineName, isNotEmpty);
          expect(usage.unitsDistributed, greaterThanOrEqualTo(0));
        }
      }
    });

    test('runFullSimulation generates patient counts scaled for rural facility', () async {
      const facilityId = 'facility_rural_test';
      await simulationService.runFullSimulation(facilityId, 'rural');

      final logsSnapshot = await fakeFirestore
          .collection('daily_usage_logs')
          .doc(facilityId)
          .collection('logs')
          .get();

      expect(logsSnapshot.docs.length, equals(31));

      for (final doc in logsSnapshot.docs) {
        final totalPatients = doc.data()['totalPatients'] as int;
        // Rural facility base patients is 35 (+/- 20% variation)
        expect(totalPatients, greaterThan(15));
        expect(totalPatients, lessThan(70));
      }
    });

    test('runFullSimulation applies hardcoded health persona for rampur_mediflow_com', () async {
      const facilityId = 'rampur_mediflow_com';
      await simulationService.runFullSimulation(facilityId, 'rural');

      final inventorySnapshot = await fakeFirestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .get();

      Map<String, Map<String, dynamic>> itemsByMedName = {
        for (var doc in inventorySnapshot.docs)
          doc.data()['medicineName'].toString(): doc.data()
      };

      // Antibiotic: low stock (15%)
      final antibiotic = itemsByMedName['Antibiotic']!;
      final antInitial = antibiotic['initialQuantity'] as int;
      expect(antibiotic['remainingQuantity'], equals((antInitial * 0.15).round()));

      // Paracetamol: expired (-5 days to expiry)
      final paracetamol = itemsByMedName['Paracetamol']!;
      final paraExpiry = (paracetamol['expiryDate'] as Timestamp).toDate();
      expect(paraExpiry.isBefore(DateTime.now()), isTrue);

      // ORS: surplus stock (95%) and expiring soon
      final ors = itemsByMedName['ORS']!;
      final orsInitial = ors['initialQuantity'] as int;
      expect(ors['remainingQuantity'], equals((orsInitial * 0.95).round()));

      // Cough Syrup: 45% remaining
      final coughSyrup = itemsByMedName['Cough Syrup']!;
      final csInitial = coughSyrup['initialQuantity'] as int;
      expect(coughSyrup['remainingQuantity'], equals((csInitial * 0.45).round()));
    });

    test('re-running simulation updates inventory without creating duplicate docs', () async {
      const facilityId = 'repeat_sim_facility';
      await simulationService.runFullSimulation(facilityId, 'urban');

      final firstInventoryCount = (await fakeFirestore
              .collection('inventory')
              .doc(facilityId)
              .collection('medicines')
              .get())
          .docs
          .length;

      // Run simulation a second time
      await simulationService.runFullSimulation(facilityId, 'urban');

      final secondInventoryCount = (await fakeFirestore
              .collection('inventory')
              .doc(facilityId)
              .collection('medicines')
              .get())
          .docs
          .length;

      expect(secondInventoryCount, equals(firstInventoryCount));
    });
  });

  group('simulationServiceProvider', () {
    test('provides SimulationService instance via Riverpod container', () {
      final container = ProviderContainer(
        overrides: [
          // Override Firestore instance to avoid real connection
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(simulationServiceProvider);
      expect(service, isA<SimulationService>());
    });
  });
}
