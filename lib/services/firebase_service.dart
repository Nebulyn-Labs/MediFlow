import 'dart:async';
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
import '../models/notification.dart' as import_notification;
import 'simulation_service.dart';

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService(
      FirebaseFirestore.instance, auth.FirebaseAuth.instance);
});

class FirebaseService {
  final FirebaseFirestore _firestore;
  final auth.FirebaseAuth _auth;
  final bool isDebugMode;
  late final SimulationService _simulation;

  int _pendingWriteCount = 0;
  final _pendingWriteCountController = StreamController<int>.broadcast();

  /// Emits true while there are locally-queued writes waiting to sync.
  /// Counts writes issued through [_logUsageOffline] specifically, rather
  /// than watching a Firestore query, since our writes fan out across two
  /// docs (inventory + log) and a query-based approach can't reliably tell
  /// "queued by us" apart from "just slow to resolve".
  Stream<bool> get hasPendingWritesStream async* {
    yield _pendingWriteCount > 0;
    yield* _pendingWriteCountController.stream.map((c) => c > 0).distinct();
  }

  /// Attempts to flush any queued offline writes, with a timeout so the
  /// caller (e.g. a "Force Sync" button) gets honest feedback instead of
  /// hanging forever while offline.
  Future<bool> forceSyncPendingWrites() async {
    try {
      await _firestore
          .waitForPendingWrites()
          .timeout(const Duration(seconds: 5));
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  FirebaseService(this._firestore, this._auth,
      {this.isDebugMode = kDebugMode}) {
    _simulation = SimulationService(_firestore);
  }

  // --- AUTH & FACILITY ---

  Future<auth.UserCredential> login(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  Future<void> sendPasswordReset(String email) async {
    String status = 'success';
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      status = 'failure';
      debugPrint('Failed to send password reset email: $e');
    }

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('logPasswordResetRequest');
      await callable.call({'email': email, 'status': status});
    } catch (e) {
      debugPrint('Failed to log password reset request: $e');
    }
  }

  Future<void> signUpFacility({
    required String name,
    required String email,
    required String password,
    String? type,
    double? fixedLat,
    double? fixedLng,
    String? fixedRegion,
    String? customFacilityId,
  }) async {
    // 1. Generate facility ID (use custom ID, or fallback strategy)
    final String facilityId;
    if (customFacilityId != null) {
      facilityId = customFacilityId;
    } else if (email.isNotEmpty && email.contains('@')) {
      facilityId =
          email.toLowerCase().replaceAll('@', '_').replaceAll('.', '_');
    } else {
      facilityId = _firestore.collection('facilities').doc().id;
    }

    // 2. Authenticate User (create account or fallback to sign-in)
    auth.UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } catch (e) {
      debugPrint('Auth create failed for $email: $e');
      try {
        credential = await _auth.signInWithEmailAndPassword(
            email: email, password: password);
      } catch (loginErr) {
        debugPrint('Sign in fallback failed for $email: $loginErr');
        rethrow;
      }
    }

    final String? uid = credential.user?.uid;
    if (uid == null) {
      throw Exception('Failed to obtain user UID for $email');
    }

    // 3. Generate Profile
    final profile = _simulation.generateRealisticProfile(type: type);

    // 4. Create Facility Document
    final facility = Facility(
      id: facilityId,
      name: name,
      email: email,
      type: type ?? profile['type']?.toString() ?? 'urban',
      region: fixedRegion ?? profile['region']?.toString() ?? '',
      latitude: fixedLat ?? (profile['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: fixedLng ?? (profile['longitude'] as num?)?.toDouble() ?? 0.0,
      createdAt: profile['createdAt'] is Timestamp
          ? (profile['createdAt'] as Timestamp).toDate()
          : (profile['createdAt'] is DateTime
              ? profile['createdAt'] as DateTime
              : DateTime.now()),
    );

    await _firestore
        .collection('facilities')
        .doc(facilityId)
        .set(facility.toMap());

    // Register role in the 'users' collection for RBAC
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'role': 'facility_head',
      'facilityId': facilityId,
      'createdAt': FieldValue.serverTimestamp(),
    });

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

  /// Looks up a facility by user email address.
  /// Does NOT rely on email-derived document IDs.
  /// Queries the facilities collection by the stored 'email' field.
  Future<Facility?> getFacilityByEmail(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) return null;
    final lowerEmail = cleanEmail.toLowerCase();

    // 1. Check if authenticated user has a facilityId in their user document
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();
        if (userDoc.exists) {
          final userFacId = userDoc.data()?['facilityId']?.toString();
          if (userFacId != null && userFacId.isNotEmpty) {
            final fac = await getFacility(userFacId);
            if (fac != null && fac.email.trim().toLowerCase() == lowerEmail) {
              return fac;
            }
          }
        }
      } catch (e) {
        debugPrint('Error reading user profile for facility lookup: $e');
      }
    }

    // 2. Query facilities collection by normalized email
    final lowerSnapshot = await _firestore
        .collection('facilities')
        .where('email', isEqualTo: lowerEmail)
        .limit(1)
        .get();
    if (lowerSnapshot.docs.isNotEmpty) {
      final doc = lowerSnapshot.docs.first;
      return Facility.fromMap(doc.data(), doc.id);
    }

    // 3. Fallback: query facilities collection by exact raw email string
    if (lowerEmail != cleanEmail) {
      final exactSnapshot = await _firestore
          .collection('facilities')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();
      if (exactSnapshot.docs.isNotEmpty) {
        final doc = exactSnapshot.docs.first;
        return Facility.fromMap(doc.data(), doc.id);
      }
    }

    return null;
  }

  Future<void> updateFacility(String id, Map<String, dynamic> data) async {
    await _firestore.collection('facilities').doc(id).update(data);
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

  /// Streams the entire collectionGroup of medicines across all facilities.
  /// Used for map overlays where live updates of all facilities are needed.
  Stream<List<InventoryItem>> streamAllMedicines() {
    return _firestore
        .collectionGroup('medicines')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final pathSegments = doc.reference.path.split('/');
              final facId = pathSegments.length >= 2 ? pathSegments[1] : '';
              return InventoryItem.fromMap(
                doc.data(),
                doc.id,
                facilityId: facId,
              );
            }).toList());
  }

  /// Fetches one page of medicines from the global collectionGroup, ordered
  /// by medicineName ascending, using startAfterDocument cursor pagination.
  /// Pass the previous page's [lastDocument] as [startAfter] to get the next
  /// page. Mirrors [getPaginatedLogs] in structure.
  Future<PaginatedMedicinesResult> getPaginatedMedicines({
    int pageSize = 20,
    DocumentSnapshot? startAfter,
  }) async {
    // Note: Firestore orderBy() automatically excludes documents missing the 'medicineName' field.
    // In our schema, 'medicineName' is a required field for all inventory items,
    // so this is intentional and safe. Documents without medicineName represent malformed data.
    Query query = _firestore
        .collectionGroup('medicines')
        .orderBy('medicineName')
        .limit(pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final medicines = snapshot.docs.map((doc) {
      // Path is inventory/{facilityId}/medicines/{medicineId}
      final pathSegments = doc.reference.path.split('/');
      final facId = pathSegments.length >= 2 ? pathSegments[1] : '';
      return InventoryItem.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
        facilityId: facId,
      );
    }).toList();

    return PaginatedMedicinesResult(
      medicines: medicines,
      lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Future<List<InventoryItem>> getAllMedicinesOnce() async {
    final snapshot = await _firestore.collectionGroup('medicines').get();
    return snapshot.docs.map((doc) {
      final pathSegments = doc.reference.path.split('/');
      final facId = pathSegments.length >= 2 ? pathSegments[1] : '';
      return InventoryItem.fromMap(doc.data(), doc.id, facilityId: facId);
    }).toList();
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
        int current =
            (invDoc.data()?['remainingQuantity'] as num?)?.toInt() ?? 0;
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

  /// Returns daily usage logs for [facilityId] whose [date] falls within the
  /// last [days] calendar days (i.e. `date >= now - days`).
  ///
  /// Unlike a plain `.limit(days)`, this is a true time-window query so
  /// callers that expect "the last 30 days of data" receive exactly that,
  /// regardless of how frequently the facility logs data.
  ///
  /// A safety cap of 500 documents is applied to avoid unbounded reads on
  /// high-throughput facilities; raise it if a use-case genuinely needs more.
  Future<List<DailyUsageLog>> getRecentLogs(String facilityId,
      {int days = 30}) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: days)),
    );
    final snapshot = await _firestore
        .collection('daily_usage_logs')
        .doc(facilityId)
        .collection('logs')
        .where('date', isGreaterThanOrEqualTo: cutoff)
        .orderBy('date', descending: true)
        .limit(500)
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

    try {
      await _runLogUsageTransaction(
        logRef: logRef,
        invRef: invRef,
        date: date,
        medicineName: medicineName,
        quantity: quantity,
        patients: patients,
      );
    } on FirebaseException catch (e) {
      // Transactions require a server round trip, so this is the real signal
      // for "device is offline" — not a connectivity_plus guess, which can
      // lag or misreport captive portals.
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        await _logUsageOffline(
          logRef: logRef,
          invRef: invRef,
          date: date,
          medicineName: medicineName,
          quantity: quantity,
          patients: patients,
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> _runLogUsageTransaction({
    required DocumentReference logRef,
    required DocumentReference invRef,
    required DateTime date,
    required String medicineName,
    required int quantity,
    required int patients,
  }) async {
    await _firestore.runTransaction((transaction) async {
      // ── Phase 1: ALL READS FIRST ──────────────────────────────────────────
      final invDoc = await transaction.get(invRef);
      final logDoc = await transaction.get(logRef);

      // ── Phase 2: BUSINESS LOGIC ───────────────────────────────────────────
      if (!invDoc.exists) {
        throw Exception(
            'Inventory document not found for medicine: $medicineName');
      }

      final int remaining = ((invDoc.data()
                  as Map<String, dynamic>?)?['remainingQuantity'] as num?)
              ?.toInt() ??
          0;
      final int actualDeduction = min(quantity, remaining);

      // Firestore returns unmodifiable maps; rebuild as mutable copies.
      final rawList =
          ((logDoc.data() as Map<String, dynamic>?)?['medicines'] as List?) ??
              [];
      final List<Map<String, dynamic>> medicines = rawList
          .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      final int totalPatients =
          ((logDoc.data() as Map<String, dynamic>?)?['totalPatients'] as num?)
                  ?.toInt() ??
              0;

      final int index =
          medicines.indexWhere((m) => m['medicineName'] == medicineName);
      if (index >= 0) {
        medicines[index] = {
          ...medicines[index],
          'unitsDistributed':
              (medicines[index]['unitsDistributed'] as int) + actualDeduction,
        };
      } else {
        medicines.add({
          'medicineName': medicineName,
          'unitsDistributed': actualDeduction,
        });
      }

      // ── Phase 3: ALL WRITES LAST ──────────────────────────────────────────
      transaction.update(invRef, {
        'remainingQuantity': remaining - actualDeduction,
        'lastUpdated': Timestamp.now(),
      });

      if (logDoc.exists) {
        transaction.update(logRef, {
          'medicines': medicines,
          'totalPatients': totalPatients + patients,
        });
      } else {
        transaction.set(logRef, {
          'date': Timestamp.fromDate(date),
          'medicines': [
            {
              'medicineName': medicineName,
              'unitsDistributed': actualDeduction,
            }
          ],
          'totalPatients': patients,
        });
      }
    });
  }

  /// Offline fallback for [logUsage]. Transactions can't run offline (they
  /// need a server round trip), so this reads from Firestore's local cache
  /// instead — which still works offline — and writes through a [WriteBatch],
  /// which Firestore queues locally and commits automatically on reconnect.
  ///
  /// This intentionally duplicates the read-modify-write logic from the
  /// transaction above rather than sharing it, since transaction.get() and
  /// a plain DocumentReference.get() return different snapshot types.
  Future<void> _logUsageOffline({
    required DocumentReference logRef,
    required DocumentReference invRef,
    required DateTime date,
    required String medicineName,
    required int quantity,
    required int patients,
  }) async {
    _pendingWriteCountController.add(++_pendingWriteCount);
    try {
      final invDoc = await invRef.get();
      final logDoc = await logRef.get();

      if (!invDoc.exists) {
        throw Exception(
            'Inventory document not found for medicine: $medicineName');
      }

      final int remaining = ((invDoc.data()
                  as Map<String, dynamic>?)?['remainingQuantity'] as num?)
              ?.toInt() ??
          0;
      final int actualDeduction = min(quantity, remaining);

      final rawList =
          ((logDoc.data() as Map<String, dynamic>?)?['medicines'] as List?) ??
              [];
      final List<Map<String, dynamic>> medicines = rawList
          .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      final int totalPatients =
          ((logDoc.data() as Map<String, dynamic>?)?['totalPatients'] as num?)
                  ?.toInt() ??
              0;

      final int index =
          medicines.indexWhere((m) => m['medicineName'] == medicineName);
      if (index >= 0) {
        medicines[index] = {
          ...medicines[index],
          'unitsDistributed':
              (medicines[index]['unitsDistributed'] as int) + actualDeduction,
        };
      } else {
        medicines.add({
          'medicineName': medicineName,
          'unitsDistributed': actualDeduction,
        });
      }

      final batch = _firestore.batch();
      batch.update(invRef, {
        'remainingQuantity': remaining - actualDeduction,
        'lastUpdated': Timestamp.now(),
      });
      if (logDoc.exists) {
        batch.update(logRef, {
          'medicines': medicines,
          'totalPatients': totalPatients + patients,
        });
      } else {
        batch.set(logRef, {
          'date': Timestamp.fromDate(date),
          'medicines': [
            {'medicineName': medicineName, 'unitsDistributed': actualDeduction}
          ],
          'totalPatients': patients,
        });
      }

      // Don't await commit() to completion — while offline it won't resolve
      // until reconnect, and blocking here would hang the caller the same
      // way the previous PR's Force Sync button hung.
      unawaited(batch.commit().whenComplete(() {
        _pendingWriteCountController.add(--_pendingWriteCount);
      }));
    } catch (e) {
      _pendingWriteCountController.add(--_pendingWriteCount);
      rethrow;
    }
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

  Future<List<MedRequest>> getRequestsOnce([String? facilityId]) async {
    var query = _firestore.collection('requests');
    final snapshot = facilityId != null
        ? await query.where('facilityId', isEqualTo: facilityId).get()
        : await query.get();
    return snapshot.docs
        .map((doc) => MedRequest.fromMap(doc.data(), doc.id))
        .toList();
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

  Future<List<Map<String, dynamic>>> getAlertsOnce(String facilityId) async {
    final snapshot = await _firestore
        .collection('alerts')
        .where('facilityId', isEqualTo: facilityId)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Stream<List<Map<String, dynamic>>> streamAlerts(String facilityId) {
    return _firestore
        .collection('alerts')
        .where('facilityId', isEqualTo: facilityId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  // --- NOTIFICATIONS ---

  Stream<List<import_notification.NotificationModel>> streamNotifications(
      String facilityId) {
    return _firestore
        .collection('notifications')
        .doc(facilityId)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => import_notification.NotificationModel.fromMap(
                doc.data(), doc.id))
            .toList());
  }

  Future<void> markNotificationRead(
      String facilityId, String notificationId) async {
    await _firestore
        .collection('notifications')
        .doc(facilityId)
        .collection('items')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // --- CLEANUP & SEEDING ---

  Future<void> clearDatabase() async {
    // Note: This is for demo purposes to provide a clean state.
    // In production, you would never wipe collections like this.
    if (!isDebugMode) {
      throw Exception('Database wiping is disabled in production builds.');
    }

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
          final callable =
              FirebaseFunctions.instance.httpsCallable('adminDeleteResource');
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
    if (!isDebugMode) {
      return 'Seeding demo data is disabled in production builds.';
    }
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

      // 3. Seed new facility documents immediately
      for (var f in demoFacilities) {
        try {
          final String facilityId = (f['email']?.toString() ?? '')
              .toLowerCase()
              .replaceAll('@', '_')
              .replaceAll('.', '_');
          final profile =
              _simulation.generateRealisticProfile(type: f['type']?.toString());
          final facility = Facility(
            id: facilityId,
            name: f['name']?.toString() ?? '',
            email: f['email']?.toString() ?? '',
            type: f['type']?.toString() ?? (profile['type'] as String),
            region: f['region']?.toString() ?? (profile['region'] as String),
            latitude: (f['lat'] as num?)?.toDouble() ??
                (profile['latitude'] as num).toDouble(),
            longitude: (f['lng'] as num?)?.toDouble() ??
                (profile['longitude'] as num).toDouble(),
            createdAt: (profile['createdAt'] as Timestamp).toDate(),
          );
          await _firestore
              .collection('facilities')
              .doc(facilityId)
              .set(facility.toMap());
        } catch (e) {
          debugPrint('Error setting facility doc for ${f['name']}: $e');
        }
      }

      // 4. Seed sample requests IMMEDIATELY so Route Optimization has data right away
      final String f1Id = (demoFacilities[0]['email']?.toString() ?? '')
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Rampur (Rural)
      final String f2Id = (demoFacilities[1]['email']?.toString() ?? '')
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Modinagar (Urban)
      final String f3Id = (demoFacilities[2]['email']?.toString() ?? '')
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Loni (Urban)
      final String f4Id = (demoFacilities[3]['email']?.toString() ?? '')
          .toLowerCase()
          .replaceAll('@', '_')
          .replaceAll('.', '_'); // Ghaziabad (Urban)
      final String f5Id = (demoFacilities[4]['email']?.toString() ?? '')
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

      // 5. Run full user registration & simulation logs
      for (var f in demoFacilities) {
        try {
          await signUpFacility(
            name: f['name']?.toString() ?? '',
            email: f['email']?.toString() ?? '',
            password: f['password']?.toString() ?? '',
            type: f['type']?.toString(),
            fixedLat: (f['lat'] as num?)?.toDouble(),
            fixedLng: (f['lng'] as num?)?.toDouble(),
            fixedRegion: f['region']?.toString(),
          );
        } catch (e) {
          debugPrint('Error signing up facility $f: $e');
        }
      }

      // Always sign back in as admin so global permissions (isAdmin()) work
      try {
        await _auth.signInWithEmailAndPassword(
            email: 'admin@mediflow.com', password: 'password123');
      } catch (e) {
        debugPrint('Failed to sign back in as admin: $e');
      }

      return null; // Success
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

      if (actionFilter != null &&
          actionFilter.isNotEmpty &&
          actionFilter != 'All') {
        query = query.where('action', isEqualTo: actionFilter);
      }

      query = query.orderBy('timestamp', descending: true).limit(pageSize);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final logs = snapshot.docs
          .map((doc) =>
              AuditLog.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      final hasMore = snapshot.docs.length == pageSize;
      final lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;

      return PaginatedAuditLogsResult(
        logs: logs,
        lastDocument: lastDocument,
        hasMore: hasMore,
      );
    } catch (e) {
      throw Exception('Error fetching audit logs: $e');
    }
  }
}
