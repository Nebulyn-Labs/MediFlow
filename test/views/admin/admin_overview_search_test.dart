import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/models/daily_usage_log.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/services/ai_service.dart';
import 'package:med_supply_prototype/views/admin/admin_overview.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _FakeAIService implements AIService {
  @override
  Future<List<Map<String, dynamic>>> generateSmartAlerts(
          List<InventoryItem> inventory) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirebaseService implements FirebaseService {
  final List<Facility> facilities;
  final List<InventoryItem> medicines;

  _FakeFirebaseService({
    required this.facilities,
    required this.medicines,
  });

  @override
  Future<List<Facility>> getFacilities({List<String>? regions}) async => facilities;

  @override
  User? get currentUser => null;

  @override
  FirebaseFirestore get firestore => throw UnimplementedError();

  @override
  Future<List<InventoryItem>> getInventoryOnce(String facilityId) async => [];

  @override
  Stream<List<MedRequest>> streamRequests(String? facilityId) =>
      Stream.value([]);

  @override
  Stream<List<MedRequest>> streamRequestsForFacilities(List<String> facilityIds) =>
      Stream.value([]);

  @override
  Future<PaginatedMedicinesResult> getPaginatedMedicines({
    int pageSize = 20,
    DocumentSnapshot? startAfter,
  }) async =>
      PaginatedMedicinesResult(
        medicines: medicines,
        lastDocument: null,
        hasMore: false,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Facility facility1;
  late Facility facility2;
  late InventoryItem med1;

  setUp(() {
    facility1 = Facility(
      id: 'fac-delhi',
      name: 'Delhi Central Clinic',
      email: 'delhi@mediflow.com',
      type: FacilityType.urban,
      region: 'North District',
      latitude: 28.6,
      longitude: 77.2,
      createdAt: DateTime(2026, 1, 1),
    );

    facility2 = Facility(
      id: 'fac-rampur',
      name: 'Rampur Sub-Center',
      email: 'rampur@mediflow.com',
      type: FacilityType.rural,
      region: 'East Sector',
      latitude: 28.7,
      longitude: 77.3,
      createdAt: DateTime(2026, 1, 1),
    );

    med1 = InventoryItem(
      id: 'med-1',
      medicineName: 'Amoxicillin 250mg',
      batchId: 'B-100',
      arrivalDate: DateTime(2026, 1, 1),
      expiryDate: DateTime(2027, 1, 1),
      initialQuantity: 1000,
      remainingQuantity: 500,
      unit: 'capsules',
      lastUpdated: DateTime(2026, 1, 1),
    );
  });

  Widget pump(FirebaseService firebase) {
    return ProviderScope(
      overrides: [
        firebaseServiceProvider.overrideWithValue(firebase),
        aiServiceProvider.overrideWithValue(_FakeAIService()),
      ],
      child: const MaterialApp(home: AdminOverview()),
    );
  }

  testWidgets(
      'AdminOverview global search filters facilities and medicines by query',
      (WidgetTester tester) async {
    final fakeFirebase = _FakeFirebaseService(
      facilities: [facility1, facility2],
      medicines: [med1],
    );

    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(pump(fakeFirebase));
    await tester.pumpAndSettle();

    // Verify initial rendering of facilities and medicines
    expect(find.text('Delhi Central Clinic'), findsOneWidget);
    expect(find.text('Rampur Sub-Center'), findsOneWidget);
    expect(find.text('Amoxicillin 250mg'), findsOneWidget);

    // Enter search query for "Delhi"
    final searchInput = find.byType(TextField);
    expect(searchInput, findsOneWidget);
    await tester.enterText(searchInput, 'Delhi');
    await tester.pumpAndSettle();

    // "Delhi Central Clinic" should match, "Rampur Sub-Center" should not
    expect(find.text('Delhi Central Clinic'), findsOneWidget);
    expect(find.text('Rampur Sub-Center'), findsNothing);

    // Enter search query for region "East Sector"
    await tester.enterText(searchInput, 'East Sector');
    await tester.pumpAndSettle();

    // "Rampur Sub-Center" should match, "Delhi Central Clinic" should not
    expect(find.text('Rampur Sub-Center'), findsOneWidget);
    expect(find.text('Delhi Central Clinic'), findsNothing);

    // Enter non-matching search query
    await tester.enterText(searchInput, 'NonExistentFacility');
    await tester.pumpAndSettle();

    expect(find.text('No facilities match your search query.'), findsOneWidget);

    // Clear search using clear button
    final clearButton = find.byIcon(Icons.clear);
    expect(clearButton, findsOneWidget);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    // Both facilities should be restored
    expect(find.text('Delhi Central Clinic'), findsOneWidget);
    expect(find.text('Rampur Sub-Center'), findsOneWidget);
  });
}
