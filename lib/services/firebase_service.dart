import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/facility.dart';
import '../models/inventory_item.dart';
import '../models/daily_usage_log.dart';
import '../models/request.dart';
import 'simulation_service.dart';

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService(FirebaseFirestore.instance, auth.FirebaseAuth.instance);
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
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUpFacility({
    required String name,
    required String email,
    required String password,
    String? type, // 'rural' or 'urban'
  }) async {
    String facilityId;
    try {
      // 1. Create Auth User
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      facilityId = credential.user!.uid;
    } on auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // If user exists, sign in to get the UID
        final credential = await _auth.signInWithEmailAndPassword(email: email, password: password);
        facilityId = credential.user!.uid;
      } else {
        rethrow;
      }
    }

    // 2. Generate Profile
    final profile = _simulation.generateRealisticProfile(type: type);
    
    // 3. Create Facility Document
    final facility = Facility(
      id: facilityId,
      name: name,
      email: email,
      type: profile['type'],
      region: profile['region'],
      latitude: profile['latitude'],
      longitude: profile['longitude'],
      createdAt: (profile['createdAt'] as Timestamp).toDate(),
    );

    await _firestore.collection('facilities').doc(facilityId).set(facility.toMap());

    // 4. Run Initial Simulation (120 days)
    await _simulation.runFullSimulation(facilityId, facility.type);
  }

  Future<List<Facility>> getFacilities() async {
    final snapshot = await _firestore.collection('facilities').get();
    return snapshot.docs.map((doc) => Facility.fromMap(doc.data(), doc.id)).toList();
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
        .map((snapshot) => snapshot.docs.map((doc) => InventoryItem.fromMap(doc.data(), doc.id)).toList());
  }

  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async {
    final snapshot = await _firestore
        .collection('inventory')
        .doc(facilityId)
        .collection('medicines')
        .get();
    return snapshot.docs.map((doc) => InventoryItem.fromMap(doc.data(), doc.id)).toList();
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
        .map((snapshot) => snapshot.docs.map((doc) => DailyUsageLog.fromMap(doc.data(), doc.id)).toList());
  }

  Future<List<DailyUsageLog>> getRecentLogs(String facilityId, {int days = 30}) async {
    final snapshot = await _firestore
        .collection('daily_usage_logs')
        .doc(facilityId)
        .collection('logs')
        .orderBy('date', descending: true)
        .limit(days)
        .get();
    return snapshot.docs.map((doc) => DailyUsageLog.fromMap(doc.data(), doc.id)).toList();
  }

  // --- LOGGING ---

  Future<void> logUsage({
    required String facilityId,
    required DateTime date,
    required String medicineName,
    required int quantity,
    required int patients,
  }) async {
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
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
        int index = medicines.indexWhere((m) => m['medicineName'] == medicineName);
        if (index >= 0) {
          medicines[index]['unitsDistributed'] += quantity;
        } else {
          medicines.add({'medicineName': medicineName, 'unitsDistributed': quantity});
        }
        
        transaction.update(logRef, {
          'medicines': medicines,
          'totalPatients': totalPatients + patients,
        });
      } else {
        transaction.set(logRef, {
          'date': Timestamp.fromDate(date),
          'medicines': [{'medicineName': medicineName, 'unitsDistributed': quantity}],
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
          (snapshot) => snapshot.docs.map((doc) => MedRequest.fromMap(doc.data(), doc.id)).toList());
    }
    return query.snapshots().map((snapshot) => snapshot.docs.map((doc) => MedRequest.fromMap(doc.data(), doc.id)).toList());
  }
  
  Future<void> addRequest(MedRequest request) async {
    await _firestore.collection('requests').add(request.toMap());
  }

  Future<void> updateRequestStatus(String requestId, RequestStatus status) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': status.toString(),
    });
  }

  Future<void> deleteRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).delete();
  }

  // --- CLEANUP & SEEDING ---

  Future<void> clearDatabase() async {
    // Note: This is for demo purposes to provide a clean state.
    // In production, you would never wipe collections like this.
    
    final collections = ['facilities', 'inventory', 'daily_usage_logs', 'requests'];
    
    for (var collection in collections) {
      final snapshot = await _firestore.collection(collection).get();
      List<Future> deleteFutures = [];
      
      for (var doc in snapshot.docs) {
        // For hierarchical collections, we need to delete sub-collections too
        if (collection == 'inventory') {
          final meds = await doc.reference.collection('medicines').get();
          for (var med in meds.docs) deleteFutures.add(med.reference.delete());
        } else if (collection == 'daily_usage_logs') {
          final logs = await doc.reference.collection('logs').get();
          for (var log in logs.docs) deleteFutures.add(log.reference.delete());
        } else if (collection == 'facilities') {
          // Cleanup legacy sub-collections from old schema
          final stocks = await doc.reference.collection('stocks').get();
          for (var s in stocks.docs) deleteFutures.add(s.reference.delete());
          final logs = await doc.reference.collection('usage_logs').get();
          for (var l in logs.docs) deleteFutures.add(l.reference.delete());
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
  
  Future<void> seedDemoData() async {
    // 1. Clear old data to avoid duplicates and schema conflicts
    await clearDatabase();

    // 2. Seed Admin
    try {
      await _auth.createUserWithEmailAndPassword(email: 'admin@mediflow.com', password: 'password123');
    } catch (e) {
      // Ignore if exists
    }

    // 3. Seed new facilities
    final List<Map<String, String>> demoFacilities = [
      {'name': 'Delhi Central Hospital', 'type': 'urban', 'email': 'delhi@mediflow.com', 'password': 'delhi@123'},
      {'name': 'Sonipat Rural Clinic', 'type': 'rural', 'email': 'sonipat@mediflow.com', 'password': 'sonipat@123'},
    ];

    for (var f in demoFacilities) {
      try {
        await signUpFacility(
          name: f['name']!,
          email: f['email']!,
          password: f['password']!,
          type: f['type'],
        );
      } catch (e) {
        print('Error seeding $f: $e');
      }
    }

    // 3. Seed Admin User
    try {
      await _auth.createUserWithEmailAndPassword(email: 'admin@mediflow.com', password: 'password123');
    } catch (e) {
      if (e is auth.FirebaseAuthException && e.code == 'email-already-in-use') {
        // Admin already seeded
      } else {
        print('Error seeding admin: $e');
      }
    }
  }
}
