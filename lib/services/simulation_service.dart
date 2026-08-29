import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_usage_log.dart';
import '../models/facility.dart';

final simulationServiceProvider =
    Provider((ref) => SimulationService(FirebaseFirestore.instance));

/// Generates realistic demo data so a freshly created facility has
/// plausible inventory, usage history, and stock-health variety without
/// requiring real operational data.
///
/// ### Inputs
/// - [generateRealisticProfile]: an optional [FacilityType] `type`;
///   randomly assigned if omitted.
/// - [runFullSimulation]: a `facilityId` and [FacilityType] `facilityType`,
///   used to seed inventory and 31 days (`i = 30 ... 0`) of usage history
///   for that facility.
///
/// ### Outputs
/// - [generateRealisticProfile]: a map of facility fields (`type`,
///   `latitude`, `longitude`, `region`, `createdAt`) suitable for writing
///   to the `facilities` collection. The `type` value in the map is the
///   Firestore string form ('urban'/'rural').
/// - [runFullSimulation]: no return value; it writes directly to
///   Firestore (`inventory/{facilityId}/medicines` and
///   `daily_usage_logs/{facilityId}/logs`) via batched writes.
///
/// ### Algorithm assumptions
/// - **Geography:** simulated facilities are clustered around Delhi NCR
///   (28.61, 77.20) with a random offset of up to ~0.2 degrees
///   (~20km) in each direction, purely for demo map visuals.
/// - **Usage volume:** urban facilities simulate a base of 150
///   patients/day, rural facilities 35/day, each with +/-20% daily
///   variation.
/// - **Seasonality:** cough syrup and paracetamol usage is multiplied
///   2.5x in winter months (Nov-Feb); ORS usage is multiplied 3x in
///   summer months (May-Aug), mirroring the seasonal patterns referenced
///   elsewhere in the AI forecasting logic.
/// - **Batching:** Firestore's per-batch write limit is 500; this service
///   commits every 400 writes to stay safely under that limit while
///   simulating up to 31 days of logs per facility.
/// - **Stock "personas":** after generating history, `_resetInventoryLevels`
///   assigns each facility a random health persona (critical/low stock,
///   surplus, or normal) so demo dashboards show varied, realistic stock
///   states rather than uniform inventory. The demo facility (defined by
///   [defaultDemoFacilityId]) is initialized with a fixed, deliberately
///   varied set of stock levels (including an expired batch) for demo-script consistency.
class SimulationService {
  final FirebaseFirestore _firestore;
  final Random _random = Random();

  /// Default facility ID used for demo inventory persona profiling.
  static const String defaultDemoFacilityId = 'rampur_mediflow_com';

  /// Single source of truth for the demo medicine catalog and unit types.
  static const Map<String, String> demoMedicineCatalog = {
    'Paracetamol': 'tablets',
    'Cough Syrup': 'vials',
    'ORS': 'sachets',
    'Antibiotic': 'capsules',
    'Vitamin Tablets': 'tablets',
    'Metformin 500mg': 'tablets',
    'Iron Folic Acid': 'tablets',
    'Amoxicillin 250mg': 'capsules',
  };

  /// List of canonical medicine names derived from [demoMedicineCatalog].
  static List<String> get demoMedicineNames =>
      demoMedicineCatalog.keys.toList();

  /// Demo stock profiles specifying inventory remaining factors and expiry overrides.
  static const Map<String, DemoStockProfile> demoStockProfiles = {
    'Antibiotic': DemoStockProfile(0.15),
    'Paracetamol': DemoStockProfile(0.35, -5),
    'ORS': DemoStockProfile(0.95, 7),
    'Cough Syrup': DemoStockProfile(0.45, 10),
    'Vitamin Tablets': DemoStockProfile(0.30),
    'Metformin 500mg': DemoStockProfile(0.28),
  };

  SimulationService(this._firestore);

  // --- LOCATION & PROFILE SIMULATION ---

  Map<String, dynamic> generateRealisticProfile({FacilityType? type}) {
    // Center point: Delhi NCR (28.6139, 77.2090)
    final double centerLat = 28.61;
    final double centerLng = 77.20;

    // Add small random offset to cluster them (within ~50km)
    final double latOffset = (_random.nextDouble() - 0.5) * 0.4;
    final double lngOffset = (_random.nextDouble() - 0.5) * 0.4;

    final FacilityType assignedType =
        type ?? (_random.nextBool() ? FacilityType.urban : FacilityType.rural);

    final List<String> regions = [
      'North District',
      'South District',
      'East State',
      'West Sector',
      'Central Zone'
    ];
    final String region = regions[_random.nextInt(regions.length)];

    return {
      'type': assignedType.toFirestore(),
      'latitude': centerLat + latOffset,
      'longitude': centerLng + lngOffset,
      'region': region,
      'createdAt': Timestamp.now(),
    };
  }

  // --- DAILY USAGE SIMULATION ---

  Future<void> runFullSimulation(
    String facilityId,
    FacilityType facilityType, {
    String demoFacilityId = defaultDemoFacilityId,
  }) async {
    final bool isDemoFacility = (facilityId == demoFacilityId);

    // 1. Initialize Inventory if not exists
    await _seedInventory(facilityId, isDemoFacility: isDemoFacility);

    // 2. Simulate last 30 days using a single WriteBatch
    final now = DateTime.now();
    var batch = _firestore.batch();
    int writeCount = 0;

    for (int i = 30; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      _addSimulateDayToBatch(batch, facilityId, facilityType, date);
      writeCount++;

      // Batch limit is 500
      if (writeCount >= 400) {
        await batch.commit();
        batch = _firestore.batch();
        writeCount = 0;
      }
    }

    if (writeCount > 0) {
      await batch.commit();
    }

    // 3. Reset inventory to realistic remaining levels after simulation
    await _resetInventoryLevels(facilityId, isDemoFacility: isDemoFacility);
  }

  Future<void> _resetInventoryLevels(
    String facilityId, {
    bool? isDemoFacility,
  }) async {
    final bool isDemo = isDemoFacility ?? (facilityId == defaultDemoFacilityId);
    final medsSnapshot = await _firestore
        .collection('inventory')
        .doc(facilityId)
        .collection('medicines')
        .get();

    // Create a specific "health persona" for this facility to make the dashboard varied
    // 1: Critical (Low stock), 2: Surplus (High stock), 0: Normal
    final int persona = _random.nextInt(3);

    for (var doc in medsSnapshot.docs) {
      final data = doc.data();
      final int initial = (data['initialQuantity'] as num?)?.toInt() ?? 2000;
      final String medName = data['medicineName']?.toString() ?? '';

      int remaining;
      int? daysToExpiryOverride;
      if (isDemo) {
        final profile = demoStockProfiles[medName];
        if (profile != null) {
          remaining = (initial * profile.remainingFactor).round();
          daysToExpiryOverride = profile.daysToExpiry;
        } else {
          remaining = (initial * 0.32).round();
        }
      } else {
        double factor;
        if (persona == 1) {
          factor = 0.05 + (_random.nextDouble() * 0.15);
        } else if (persona == 2) {
          factor = 0.75 + (_random.nextDouble() * 0.20);
        } else {
          factor = 0.40 + (_random.nextDouble() * 0.25);
        }
        remaining = (initial * factor).round();
      }

      final Map<String, dynamic> updates = {
        'remainingQuantity': remaining,
        'lastUpdated': Timestamp.now(),
      };
      if (daysToExpiryOverride != null) {
        updates['expiryDate'] = Timestamp.fromDate(
            DateTime.now().add(Duration(days: daysToExpiryOverride)));
      }

      await doc.reference.update(updates);
    }
  }

  Future<void> _seedInventory(
    String facilityId, {
    bool? isDemoFacility,
  }) async {
    final bool isDemo = isDemoFacility ?? (facilityId == defaultDemoFacilityId);

    for (var entry in demoMedicineCatalog.entries) {
      final med = entry.key;
      final unit = entry.value;
      final medicineId = med.toLowerCase().replaceAll(' ', '_');
      final invRef = _firestore
          .collection('inventory')
          .doc(facilityId)
          .collection('medicines')
          .doc(medicineId);

      final snapshot = await invRef.get();
      if (!snapshot.exists) {
        final int initialQty = 2000 + _random.nextInt(3000);

        int daysToExpiry;
        if (isDemo) {
          final profile = demoStockProfiles[med];
          if (profile?.daysToExpiry != null) {
            daysToExpiry = profile!.daysToExpiry!;
          } else {
            daysToExpiry = 180 + _random.nextInt(200);
          }
        } else {
          daysToExpiry = _random.nextInt(10) < 2
              ? 15 + _random.nextInt(60)
              : 180 + _random.nextInt(200);
        }

        await invRef.set({
          'medicineName': med,
          'batchId': 'B-${1000 + _random.nextInt(9000)}',
          'initialQuantity': initialQty,
          'remainingQuantity': initialQty,
          'unit': unit,
          'arrivalDate': Timestamp.fromDate(DateTime.now()
              .subtract(Duration(days: 90 + _random.nextInt(100)))),
          'expiryDate': Timestamp.fromDate(
              DateTime.now().add(Duration(days: daysToExpiry))),
          'lastUpdated': Timestamp.now(),
        });
      }
    }
  }

  void _addSimulateDayToBatch(WriteBatch batch, String facilityId,
      FacilityType facilityType, DateTime date) {
    // 1. Determine patient count
    int basePatients = facilityType == FacilityType.urban ? 150 : 35;
    double variation = 0.8 + (_random.nextDouble() * 0.4); // 80% to 120%
    int totalPatients = (basePatients * variation).round();

    // 2. Generate medicine usage for ALL medicines
    List<MedicineUsage> usages = [];
    final month = date.month;

    for (var med in demoMedicineCatalog.keys) {
      double usagePerPatient =
          0.4 + (_random.nextDouble() * 0.3); // more realistic base

      // Seasonal Influences
      if ((month >= 11 || month <= 2) &&
          (med == 'Cough Syrup' || med == 'Paracetamol')) {
        usagePerPatient *= 2.5; // Winter spike
      } else if ((month >= 5 && month <= 8) && med == 'ORS') {
        usagePerPatient *= 3.0; // Summer spike
      }

      int unitsUsed =
          (totalPatients * usagePerPatient * (0.8 + _random.nextDouble() * 0.4))
              .round();
      usages.add(MedicineUsage(medicineName: med, unitsDistributed: unitsUsed));
    }

    // 3. Write Daily Log to Batch
    final dateStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    final logRef = _firestore
        .collection('daily_usage_logs')
        .doc(facilityId)
        .collection('logs')
        .doc(dateStr);

    batch.set(logRef, {
      'date': Timestamp.fromDate(date),
      'medicines': usages.map((u) => u.toMap()).toList(),
      'totalPatients': totalPatients,
    });
  }
}

/// Represents initial remaining quantity factor and optional expiry override
/// for demo inventory stock persona assignment.
class DemoStockProfile {
  final double remainingFactor;
  final int? daysToExpiry;

  const DemoStockProfile(this.remainingFactor, [this.daysToExpiry]);
}
