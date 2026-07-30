import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/facility.dart';
import '../models/inventory_item.dart';
import '../models/daily_usage_log.dart';
import '../models/request.dart';
import '../models/audit_log.dart';
import 'simulation_service.dart';

final firebaseServiceProvider = Provider((ref) {
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

  Future login(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  Future sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('logPasswordResetRequest');
      await callable.call({'email': email});
    } catch (e) {
      debugPrint('Failed to log password reset request: $e');
    }
  }

  Future signUpFacility({
    required String name,
    required String email,
    required String password,
    String? type,
    double? fixedLat,
    double? fixedLng,
    String? fixedRegion,
  }) async {
    final String facilityId =
        email.toLowerCase().replaceAll('@', '_').replaceAll('.', '_');

    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } catch (e) {
      debugPrint('Auth skip/fail for $email: $e');
      try {
        await _auth.signInWithEmailAndPassword(
            email: email, password: password);
      } catch (loginErr) {
        debugPrint('Sign in fallback failed for $email: $loginErr');
      }
    }

    final profile = _simulation.generateRealisticProfile(type: type);

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

    final String? uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _firestore.collection('users').doc(uid).set({
        'email': email,
        'role': 'facility_head',
        'facilityId': facilityId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

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

  Future updateFacility(String id, Map<String, dynamic> data) async {
    await _firestore.collection('facilities').doc(id).update(data);
  }

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
        final pathSegments = doc.reference.path.split('/');
        final facId = pathSegments.length >= 2 ? pathSegments[1] : '';
        return InventoryItem.fromMap(doc.data(), doc.id, facilityId: facId);
      }).toList();
    });
  }

  Future restock(
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
      } else {
        throw Exception(
            'Inventory document not found for medicine: $medicineName');
      }
    });
  }

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

  Future logUsage({
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
      final invDoc = await transaction.get(invRef);
      if (!invDoc.exists) {
        throw Exception(
            'Inventory document not found for medicine: $medicineName');
      }

      int remaining = invDoc.data()?['remainingQuantity'] ?? 0;
      int actualDeduction = min(quantity, remaining);
      transaction.update(invRef, {
        'remainingQuantity': remaining - actualDeduction,
        'lastUpdated': Timestamp.now(),
      });

      final logDoc = await transaction.get(logRef);
      if (logDoc.exists) {
        List<dynamic> medicines = logDoc.data()?['medicines'] ?? [];
        int totalPatients = logDoc.data()?['totalPatients'] ?? 0;

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
      return query.where('facilityId', isEqualTo: facilityId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => MedRequest.fromMap(doc.data(), doc.id))
              .toList());
    }
    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => MedRequest.fromMap(doc.data(), doc.id))
        .toList());
  }

  Future addRequest(MedRequest request) async {
    await _firestore.collection('requests').add(request.toMap());
  }

  Future updateRequestStatus(
      String requestId, RequestStatus status) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': status.name,
    });
  }

  Future updateRequestQuantity(String requestId, int quantity) async {
    await _firestore.collection('requests').doc(requestId).update({
      'quantity': quantity,
    });
  }

  Future deleteRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).delete();
  }

  // --- CHANGE 1: Updated disposeInventory to throw on missing doc, record wastage, and clear alert ---
  Future<void> disposeInventory(String facilityId, String medicineName) async {
    final medicineId = medicineName.toLowerCase().replaceAll(' ', '_');
    final invRef = _firestore
        .collection('inventory')
        .doc(facilityId)
        .collection('medicines')
        .doc(medicineId);

    await _firestore.runTransaction((transaction) async {
      final invDoc = await transaction.get(invRef);
      
      // Throw exception if document does not exist, matching restock() behavior
      if (!invDoc.exists) {
        throw Exception('Inventory document not found for medicine: $medicineName');
      }

      final data = invDoc.data()!;
      final remainingQuantity = data['remainingQuantity'] ?? 0;
      final unit = data['unit'] ?? 'units';
      final batchId = data['batchId'] ?? '';

      // 1. Zero out the inventory
      transaction.update(invRef, {
        'remainingQuantity': 0,
        'lastUpdated': Timestamp.now(),
      });

      // 2. Record the wastage/disposal durably
      final wastageRef = _firestore.collection('wastage_logs').doc();
      transaction.set(wastageRef, {
        'facilityId': facilityId,
        'medicineName': medicineName,
        'batchId': batchId,
        'quantityDestroyed': remainingQuantity,
        'unit': unit,
        'timestamp': Timestamp.now(),
        'reason': 'Marked for disposal via alerts page',
      });
    });

    // 3. After successful transaction, clear the corresponding alert so it doesn't show up again
    final alertQuery = await _firestore
        .collection('alerts')
        .where('facilityId', isEqualTo: facilityId)
        .where('medicineName', isEqualTo: medicineName)
        .limit(1)
        .get();
    
    for (final doc in alertQuery.docs) {
      await doc.reference.delete();
    }
  }

  Future<List<Map<String, dynamic>>> getAlertsOnce(String facilityId) async {
    final snapshot = await _firestore
        .collection('alerts')
        .where('facilityId', isEqualTo: facilityId)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future clearDatabase() async {
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
        if (collection == 'facilities' || collection == 'requests') {
          final callable = FirebaseFunctions.instance.httpsCallable('adminDeleteResource');
          deleteFutures.add(callable.call({
            'resourceType': collection,
            'resourceId': doc.id,
          }));
        } else {
          deleteFutures.add(doc.reference.delete());
        }

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

      final String? adminUid = _auth.currentUser?.uid;
      if (adminUid != null) {
        await _firestore.collection('users').doc(adminUid).set({
          'email': 'admin@mediflow.com',
          'role': 'admin',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

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

      return null;
    } catch (e) {
      return 'Critical error: $e';
    }
  }

  // --- AUDIT LOGS ---

  Future<PaginatedAuditLogsResult> getPaginatedAuditLogs({
    int pageSize = 20,
    DocumentSnapshot? startAfter,
    String? actionFilter,
  }) async {
    try {
      Query query = _firestore.collection('audit_logs');
      if (actionFilter != null && actionFilter.isNotEmpty && actionFilter != 'All') {
        query = query.where('action', isEqualTo: actionFilter);
      }
      query = query.orderBy('timestamp', descending: true).limit(pageSize);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final logs = snapshot.docs
          .map((doc) => AuditLog.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      return PaginatedAuditLogsResult(
        logs: logs,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == pageSize,
      );
    } catch (e) {
      throw Exception('Error fetching audit logs: $e');
    }
  }
}
