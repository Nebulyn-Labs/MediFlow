import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/notification.dart';
import 'package:med_supply_prototype/services/firebase_service.dart';
import 'package:med_supply_prototype/views/shared/sidebar_layout.dart';

class _FakeFirebaseService implements FirebaseService {
  int streamInventoryCallCount = 0;
  int streamNotificationsCallCount = 0;
  String? lastInventoryFacilityId;
  String? lastNotificationsFacilityId;

  @override
  Stream<List<InventoryItem>> streamInventory(String facilityId) {
    streamInventoryCallCount++;
    lastInventoryFacilityId = facilityId;
    return Stream.value(const []);
  }

  @override
  Stream<List<NotificationModel>> streamNotifications(String facilityId) {
    streamNotificationsCallCount++;
    lastNotificationsFacilityId = facilityId;
    return Stream.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({
  required _FakeFirebaseService firebase,
  required String facilityId,
}) {
  return ProviderScope(
    overrides: [
      firebaseServiceProvider.overrideWithValue(firebase),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/facility/$facilityId/overview',
        routes: [
          GoRoute(
            path: '/facility/:id/overview',
            builder: (context, state) => SidebarLayout(
              role: 'facility',
              facilityId: state.pathParameters['id'],
              child: const Text('body'),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('sidebar hover does not open new Firestore listeners (#322)',
      (tester) async {
    final firebase = _FakeFirebaseService();

    await tester.pumpWidget(_app(firebase: firebase, facilityId: 'fac-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(firebase.streamInventoryCallCount, 1);
    expect(firebase.streamNotificationsCallCount, 1);
    expect(firebase.lastInventoryFacilityId, 'fac-1');

    final mouseRegion =
        tester.widgetList<MouseRegion>(find.byType(MouseRegion)).firstWhere(
              (region) => region.onEnter != null && region.onExit != null,
            );
    mouseRegion.onEnter!(const PointerEnterEvent());
    await tester.pump();
    mouseRegion.onExit!(const PointerExitEvent());
    await tester.pump();

    expect(firebase.streamInventoryCallCount, 1);
    expect(firebase.streamNotificationsCallCount, 1);
  });

  testWidgets(
      'sidebar binds a new listener when the facility id changes (#322)',
      (tester) async {
    final firebase = _FakeFirebaseService();

    await tester.pumpWidget(_app(firebase: firebase, facilityId: 'fac-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(firebase.streamInventoryCallCount, 1);
    expect(firebase.lastInventoryFacilityId, 'fac-1');

    await tester.pumpWidget(_app(firebase: firebase, facilityId: 'fac-2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(firebase.streamInventoryCallCount, 2);
    expect(firebase.lastInventoryFacilityId, 'fac-2');
    expect(firebase.lastNotificationsFacilityId, 'fac-2');
  });
}
