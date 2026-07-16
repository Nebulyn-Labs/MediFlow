import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_usage_log.dart';

final simulationServiceProvider =
    Provider((ref) => SimulationService(FirebaseFirestore.instance));

class SimulationService {
  final FirebaseFirestore _firestore;
  final Random _random = Random();

  SimulationService(this._firestore);

  // --- LOCATION & PROFILE SIMULATION ---

  Map<String, dynamic> generateRealisticProfile({String? type}) {
    // Center point: Delhi NCR (28.6139, 77.2090)
    final double centerLat = 28.61;
    final double centerLng = 77.20;

    // Add small random offset to cluster them (within ~50km)
    final double latOffset = (_random.nextDouble() - 0.5) * 0.4;
    final double lngOffset = (_random.nextDouble() - 0.5) * 0.4;

    final String assignedType =
        type ?? (_random.nextBool() ? 'urban' : 'rural');

    final List<String> regions = [
      'North District',
      'South District',
      'East State',
      'West Sector',
      'Central Zone'
    ];
    final String region = regions[_random.nextInt(regions.length)];

    return {
      'type': assignedType,
      'latitude': centerLat + latOffset,
      'longitude': centerLng + lngOffset,
      'region': region,
      'createdAt': Timestamp.now(),
    };
  }

  // --- DAILY USAGE SIMULATION ---

  Future<void> runFullSimulation(String facilityId, String facilityType) async {
    // 1. Initialize Inventory if not exists
    await _seedInventory(facilityId);

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
    await _resetInventoryLevels(facilityId);
  }

  Future<void> _resetInventoryLevels(String facilityId) async {
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
      final int initial = data['initialQuantity'] ?? 2000;
      final String medName = data['medicineName'] ?? '';

      int remaining;
      int? daysToExpiryOverride;
      if (facilityId == 'rampur_mediflow_com') {
        if (medName == 'Antibiotic') {
          remaining = (initial * 0.15).round(); // Low stock (15%)
        } else if (medName == 'Paracetamol') {
          remaining = (initial * 0.35).round(); // Expired (35% stock)
          daysToExpiryOverride = -5;
        } else if (medName == 'ORS') {
          remaining = (initial * 0.95).round(); // Surplus (Wastage risk)
          daysToExpiryOverride = 7;
        } else if (medName == 'Cough Syrup') {
          remaining = (initial * 0.45).round(); // Expiring soon (45% stock)
          daysToExpiryOverride = 10;
        } else if (medName == 'Vitamin Tablets') {
          remaining = (initial * 0.30).round(); // Healthy but 30% stock
        } else if (medName == 'Metformin 500mg') {
          remaining = (initial * 0.28).round(); // Healthy but 28% stock
        } else {
          remaining = (initial * 0.32).round(); // Healthy but 32% stock
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

  Future<void> _seedInventory(String facilityId) async {
    final Map<String, String> medicines = {
      'Paracetamol': 'tablets',
      'Cough Syrup': 'vials',
      'ORS': 'sachets',
      'Antibiotic': 'capsules',
      'Vitamin Tablets': 'tablets',
      'Metformin 500mg': 'tablets',
      'Iron Folic Acid': 'tablets',
      'Amoxicillin 250mg': 'capsules'
    };

    for (var entry in medicines.entries) {
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
        if (facilityId == 'rampur_mediflow_com') {
          if (med == 'Paracetamol') {
            daysToExpiry = -5; // Expired
          } else if (med == 'Cough Syrup') {
            daysToExpiry = 10; // Expiring soon
          } else if (med == 'ORS') {
            daysToExpiry = 7; // Expiring soon (wastage risk)
          } else {
            daysToExpiry = 180 + _random.nextInt(200); // Normal
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

  void _addSimulateDayToBatch(
      WriteBatch batch, String facilityId, String facilityType, DateTime date) {
    // 1. Determine patient count
    int basePatients = facilityType == 'urban' ? 150 : 35;
    double variation = 0.8 + (_random.nextDouble() * 0.4); // 80% to 120%
    int totalPatients = (basePatients * variation).round();

    // 2. Generate medicine usage for ALL medicines
    final List<String> medicines = [
      'Paracetamol',
      'Cough Syrup',
      'ORS',
      'Antibiotic',
      'Vitamin Tablets',
      'Metformin 500mg',
      'Iron Folic Acid',
      'Amoxicillin 250mg'
    ];
    List<MedicineUsage> usages = [];
    final month = date.month;

    for (var med in medicines) {
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
