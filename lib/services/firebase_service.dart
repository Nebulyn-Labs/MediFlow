import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/facility.dart';
import '../models/inventory_item.dart';
import '../models/daily_usage_log.dart';
import '../models/request.dart';
import 'simulation_service.dart';

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService(
      FirebaseFirestore.instance, auth.FirebaseAuth.instance);
});

class FirebaseService {
  final FirebaseFirestore _firestore;
  final auth.FirebaseAuth _auth;
  late final SimulationService _simulation;

  FirebaseService(this._firestore, this._auth) {
    _simulation = SimulationService(_firestore);
  }

  // --- AUTH & FACILITY ---

  Future<auth.UserCredential> login(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  Future<void> signUpFacility({
    required String name,
    required String email,
    required String password,
    String? type,
    double? fixedLat,
    double? fixedLng,
    String? fixedRegion,
  }) async {
    // 1. Generate a deterministic ID from email to bypass Auth dependency
    // This ensures Firestore docs are created even if Auth rate limits hit.
    final String facilityId =
        email.toLowerCase().replaceAll('@', '_').replaceAll('.', '_');

    // 2. Try to create Auth User in background (Non-blocking for data seeding)
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } catch (e) {
      // If user exists or rate limit hits, we don't care for seeding Firestore data
      debugPrint('Auth skip/fail for $email: $e');
      try {
        await _auth.signInWithEmailAndPassword(
            email: email, password: password);
      } catch (loginErr) {
        debugPrint('Sign in fallback failed for $email: $loginErr');
      }
    }

    // 3. Generate Profile
    final profile = _simulation.generateRealisticProfile(type: type);

    // 4. Create Facility Document
    final facility = Facility(
      id: facilityId,
      name: name,
      email: email,
      type: type ?? profile['type'],
      region: fixedRegion ?? profile['region'],
      latitude: fixedLat ?? profile['latitude'],
      longitude: fixedLng ?? profile['longitude'],
      createdAt: (profile['createdAt'] as Timestamp).toDate(),
    );

    await _firestore
        .collection('facilities')
        .doc(facilityId)
        .set(facility.toMap());

    // 5. Run Initial Simulation (30 days)
    await _simulation.runFullSimulation(facilityId, facility.type);
  }

  Future<List<Facility>> getFacilities() async {
    final snapshot = await _firestore.collection('facilities').get();
    return snapshot.docs
        .map((doc) => Facility.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<Facility?> getFacility(String id) async {
    final doc = await _firestore.collection('facilities').doc(id).get();
    if (!doc.exists) return null;
    return Facility.fromMap(doc.data()!, doc.id);
  }

  // --- INVENTORY ---

  Stream<List<InventoryItem>> streamInventory(String facilityId) {
    return _firestore
        .collection('inventory')
        .doc(facilityId)
        .collection('medicines')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => InventoryItem.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async {
    final snapshot = await _firestore
        .collection('inventory')
        .doc(facilityId)
        .collection('medicines')
        .get();
    return snapshot.docs
        .map((doc) => InventoryItem.fromMap(doc.data(), doc.id))
        .toList();
  }

  Stream<List<InventoryItem>> streamAllMedicines() {
    return _firestore.collectionGroup('medicines').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        // Path is inventory/{facilityId}/medicines/{medicineId}
        final pathSegments = doc.reference.path.split('/');
        final facId = pathSegments.length >= 2 ? pathSegments[1] : '';
        return InventoryItem.fromMap(doc.data(), doc.id, facilityId: facId);
      }).toList();
    });
  }

  Future<void> restock(
      String facilityId, String medicineName, int quantity) async {
    final medicineId = medicineName.toLowerCase().replaceAll(' ', '_');
    final invRef = _firestore
        .collection('inventory')
        .doc(facilityId)
        .collection('medicines')
        .doc(medicineId);

    await _firestore.runTransaction((transaction) async {
      final invDoc = await transaction.get(invRef);
      if (invDoc.exists) {
        int current = invDoc.data()?['remainingQuantity'] ?? 0;
        transaction.update(invRef, {
          'remainingQuantity': current + quantity,
          'lastUpdated': Timestamp.now(),
        });
      }
    });
  }

  // --- DAILY USAGE LOGS ---

  Stream<List<DailyUsageLog>> streamDailyLogs(String facilityId) {
    return _firestore
        .collection('daily_usage_logs')
        .doc(facilityId)
        .collection('logs')
        .orderBy('date', descending: true)
        .limit(120)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DailyUsageLog.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<List<DailyUsageLog>> getRecentLogs(String facilityId,
      {int days = 30}) async {
    final snapshot = await _firestore
        .collection('daily_usage_logs')
        .doc(facilityId)
        .collection('logs')
        .orderBy('date', descending: true)
        .limit(days)
        .get();
    return snapshot.docs
        .map((doc) => DailyUsageLog.fromMap(doc.data(), doc.id))
        .toList();
  }

  /// Fetches one page of daily usage logs ordered by date descending, using
  /// Firestore's document-cursor pagination (startAfterDocument) instead of
  /// a flat limit. Pass the previous page's lastDocument as [startAfter] to
  /// fetch the next page.
  Future<PaginatedLogsResult> getPaginatedLogs(
    String facilityId, {
    int pageSize = 15,
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _firestore
        .collection('daily_usage_logs')
        .doc(facilityId)
        .collection('logs')
        .orderBy('date', descending: true)
        .limit(pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final logs = snapshot.docs
        .map((doc) =>
            DailyUsageLog.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();

    return PaginatedLogsResult(
      logs: logs,
      lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  // --- LOGGING ---

  Future<void> logUsage({
    required String facilityId,
    required DateTime date,
    required String medicineName,
    required int quantity,
    required int patients,
  }) async {
    final dateStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    final logRef = _firestore
        .collection('daily_usage_logs')
        .doc(facilityId)
        .collection('logs')
        .doc(dateStr);

    final medicineId = medicineName.toLowerCase().replaceAll(' ', '_');
    final invRef = _firestore
        .collection('inventory')
        .doc(facilityId)
        .collection('medicines')
        .doc(medicineId);

    await _firestore.runTransaction((transaction) async {
      // 1. Update Inventory
      final invDoc = await transaction.get(invRef);
      if (invDoc.exists) {
        int remaining = invDoc.data()?['remainingQuantity'] ?? 0;
        int actualDeduction = min(quantity, remaining);
        transaction.update(invRef, {
          'remainingQuantity': remaining - actualDeduction,
          'lastUpdated': Timestamp.now(),
        });
      }

      // 2. Update Daily Log
      final logDoc = await transaction.get(logRef);
      if (logDoc.exists) {
        List medicines = logDoc.data()?['medicines'] ?? [];
        int totalPatients = logDoc.data()?['totalPatients'] ?? 0;

        // Update existing medicine usage or add new
        int index =
            medicines.indexWhere((m) => m['medicineName'] == medicineName);
        if (index >= 0) {
          medicines[index]['unitsDistributed'] += quantity;
        } else {
          medicines.add(
              {'medicineName': medicineName, 'unitsDistributed': quantity});
        }

        transaction.update(logRef, {
          'medicines': medicines,
          'totalPatients': totalPatients + patients,
        });
      } else {
        transaction.set(logRef, {
          'date': Timestamp.fromDate(date),
          'medicines': [
            {'medicineName': medicineName, 'unitsDistributed': quantity}
          ],
          'totalPatients': patients,
        });
      }
    });
  }

  Stream<List<MedRequest>> streamRequests(String? facilityId) {
    var query = _firestore.collection('requests');
    if (facilityId != null) {
      // Note: Requests are still top-level as they involve cross-facility matching
      return query.where('facilityId', isEqualTo: facilityId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => MedRequest.fromMap(doc.data(), doc.id))
              .toList());
    }
    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => MedRequest.fromMap(doc.data(), doc.id))
        .toList());
  }

  Future<void> addRequest(MedRequest request) async {
    await _firestore.collection('requests').add(request.toMap());
  }

  Future<void> updateRequestStatus(
      String requestId, RequestStatus status) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': status.name,
    });
  }

  Future<void> updateRequestQuantity(String requestId, int quantity) async {
    await _firestore.collection('requests').doc(requestId).update({
      'quantity': quantity,
    });
  }

  Future<void> deleteRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).delete();
  }

  Future<void> disposeInventory(String facilityId, String medicineName) async {
    final medicineId = medicineName.toLowerCase().replaceAll(' ', '_');
    final invRef = _firestore
        .collection('inventory')
        .doc(facilityId)
        .collection('medicines')
        .doc(medicineId);

    await _firestore.runTransaction((transaction) async {
      final invDoc = await transaction.get(invRef);
      if (invDoc.exists) {
        transaction.update(invRef, {
          'remainingQuantity': 0,
          'lastUpdated': Timestamp.now(),
        });
      }
    });
  }

  // --- CLEANUP & SEEDING ---

  Future<void> clearDatabase() async {
    // Note: This is for demo purposes to provide a clean state.
    // In production, you would never wipe collections like this.

    final collections = [
      'facilities',
      'inventory',
      'daily_usage_logs',
      'requests'
    ];

    for (var collection in collections) {
      final snapshot = await _firestore.collection(collection).get();
      List<Future> deleteFutures = [];

      for (var doc in snapshot.docs) {
        // For hierarchical collections, we need to delete sub-collections too
        if (collection == 'inventory') {
          final meds = await doc.reference.collection('medicines').get();
          for (var med in meds.docs) {
            deleteFutures.add(med.reference.delete());
          }
        } else if (collection == 'daily_usage_logs') {
          final logs = await doc.reference.collection('logs').get();
          for (var log in logs.docs) {
            deleteFutures.add(log.reference.delete());
          }
        } else if (collection == 'facilities') {
          // Cleanup legacy sub-collections from old schema
          final stocks = await doc.reference.collection('stocks').get();
          for (var s in stocks.docs) {
            deleteFutures.add(s.reference.delete());
          }
          final logs = await doc.reference.collection('usage_logs').get();
          for (var l in logs.docs) {
            deleteFutures.add(l.reference.delete());
          }
        }
        deleteFutures.add(doc.reference.delete());

        if (deleteFutures.length >= 50) {
          await Future.wait(deleteFutures);
          deleteFutures = [];
        }
      }
      if (deleteFutures.isNotEmpty) await Future.wait(deleteFutures);
    }
  }

  Future<String?> seedDemoData() async {
    try {
      // 1. Seed/Login Admin first to ensure authorization for database clearing/seeding
      try {
        await _auth.createUserWithEmailAndPassword(
            email: 'admin@mediflow.com', password: 'password123');
      } catch (_) {
        try {
          await _auth.signInWithEmailAndPassword(
              email: 'admin@mediflow.com', password: 'password123');
        } catch (loginError) {
          debugPrint('Admin login failed during seed: $loginError');
        }
      }

      // 2. Clear old data to avoid duplicates and schema conflicts
      await clearDatabase();

      // 3. Seed new facilities
      final List<Map<String, dynamic>> demoFacilities = [
        {
          'name': 'PHC Rampur',
          'type': 'rural',
          'email': 'rampur@mediflow.com',
          'password': 'password123',
          'region': 'North District',
          'lat': 28.6139,
          'lng': 77.2090
        },
        {
          'name': 'CHC Modinagar',
          'type': 'urban',
          'email': 'modinagar@mediflow.com',
          'password': 'password123',
          'region': 'East Zone',
          'lat': 28.6500,
          'lng': 77.3000
        },
        {
          'name': 'PHC Loni',
          'type': 'urban',
          'email': 'loni@mediflow.com',
          'password': 'password123',
          'region': 'North District',
          'lat': 28.7000,
          'lng': 77.2800
        },
        {
          'name': 'DH Ghaziabad',
          'type': 'urban',
          'email': 'ghaziabad@mediflow.com',
          'password': 'password123',
          'region': 'Central Hub',
          'lat': 28.6600,
          'lng': 77.4200
        },
        {
          'name': 'PHC Bhojpur',
          'type': 'rural',
          'email': 'bhojpur@mediflow.com',
          'password': 'password123',
          'region': 'West Sector',
          'lat': 28.7500,
          'lng': 77.5000
        },
        {
          'name': 'CHC Hapur',
          'type': 'urban',
          'email': 'hapur@mediflow.com',
          'password': 'password123',
          'region': 'East Zone',
          'lat': 28.7200,
          'lng': 77.7800
        },
        {
          'name': 'PHC Dasna',
          'type': 'rural',
          'email': 'dasna@mediflow.com',
          'password': 'password123',
          'region': 'Central Hub',
          'lat': 28.6800,
          'lng': 77.5200
        },
        {
          'name': 'SubCentre Pilkhuwa',
          'type': 'rural',
          'email': 'pilkhuwa@mediflow.com',
          'password': 'password123',
          'region': 'West Sector',
          'lat': 28.7100,
          'lng': 77.6500
        },
      ];

      for (var f in demoFacilities) {
        try {
          await signUpFacility(
            name: f['name']!,
            email: f['email']!,
            password: f['password']!,
            type: f['type'],
            fixedLat: f['lat'],
            fixedLng: f['lng'],
            fixedRegion: f['region'],
          );
          // Delay to avoid auth rate limits
          await Future.delayed(const Duration(milliseconds: 1500));
        } catch (e) {
          debugPrint('Error seeding $f: $e');
          return 'Failed at ${f['name']}: $e';
        }
      }

      // Sign back in as admin to have global access to create requests for different facilities
      try {
        await _auth.signInWithEmailAndPassword(
            email: 'admin@mediflow.com', password: 'password123');
      } catch (e) {
        debugPrint('Failed to sign back in as admin: $e');
      }

      // 4. Seed sample requests for Admin Dashboard KPIs & Route Optimization
      final String f1Id = demoFacilities[0]['email']!
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Rampur (Rural)
      final String f2Id = demoFacilities[1]['email']!
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Modinagar (Urban)
      final String f3Id = demoFacilities[2]['email']!
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Loni (Urban)
      final String f4Id = demoFacilities[3]['email']!
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Ghaziabad (Urban)
      final String f5Id = demoFacilities[4]['email']!
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Bhojpur (Rural)

      // Match 1: ORS (Rampur Rural Needs, Modinagar Urban Surplus)
      await addRequest(MedRequest(
          id: '',
          facilityId: f1Id,
          medicineName: 'ORS',
          type: RequestType.regularIndent,
          quantity: 800,
          requestDate: DateTime.now(),
          status: RequestStatus.pending,
          notes: 'Critical shortage predicted by AI for summer spike.'));

      await addRequest(MedRequest(
          id: '',
          facilityId: f2Id,
          medicineName: 'ORS',
          type: RequestType.surplus,
          quantity: 1000,
          requestDate: DateTime.now(),
          status: RequestStatus.pending,
          notes: 'Excess stock identified. Available for redistribution.'));

      // Match 2: Antibiotics (Bhojpur Rural Needs, Ghaziabad Urban Surplus)
      await addRequest(MedRequest(
          id: '',
          facilityId: f5Id,
          medicineName: 'Antibiotic',
          type: RequestType.shortage,
          quantity: 300,
          requestDate: DateTime.now(),
          status: RequestStatus.approved,
          notes: 'Post-monsoon surge in infections.'));

      await addRequest(MedRequest(
          id: '',
          facilityId: f4Id,
          medicineName: 'Antibiotic',
          type: RequestType.surplus,
          quantity: 500,
          requestDate: DateTime.now(),
          status: RequestStatus.pending,
          notes: 'Surplus stock optimization.'));

      // Unmatched: Paracetamol (Just for variety)
      await addRequest(MedRequest(
        id: '',
        facilityId: f3Id,
        medicineName: 'Paracetamol',
        type: RequestType.regularIndent,
        quantity: 1200,
        requestDate: DateTime.now(),
        status: RequestStatus.pending,
      ));

      return null; // Success
    } catch (e) {
      return 'Critical error: $e';
    }
  }
}
