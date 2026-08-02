import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:med_supply_prototype/services/routing_service.dart';

void main() {
  group('RoutingService Unit Tests', () {
    late RoutingService routingService;

    setUp(() {
      routingService = RoutingService();
    });

    test('returns straight-line fallback for placeholder coordinate (0, 0)', () async {
      final start = const LatLng(0.0, 0.0);
      final end = const LatLng(28.61, 77.21);

      final route = await routingService.getRoute(start, end);

      expect(route, equals([start, end]));
    });

    test('returns straight-line fallback for placeholder coordinate (-1, -1)', () async {
      final start = const LatLng(28.61, 77.21);
      final end = const LatLng(-1.0, -1.0);

      final route = await routingService.getRoute(start, end);

      expect(route, equals([start, end]));
    });

    test('returns straight-line fallback for invalid out-of-bounds latitude/longitude', () async {
      final start = const LatLng(95.0, 77.21); // invalid lat > 90
      final end = const LatLng(28.61, 200.0);  // invalid lng > 180

      final route = await routingService.getRoute(start, end);

      expect(route, equals([start, end]));
    });

    test('getMultiStopRoute returns empty list for empty stops', () async {
      final route = await routingService.getMultiStopRoute([]);
      expect(route, isEmpty);
    });

    test('getMultiStopRoute returns single stop for 1 stop', () async {
      final stop = const LatLng(28.61, 77.21);
      final route = await routingService.getMultiStopRoute([stop]);
      expect(route, equals([stop]));
    });

    test('getMultiStopRoute generates segments for multiple valid stops', () async {
      final stops = [
        const LatLng(28.6139, 77.2090),
        const LatLng(28.7041, 77.1025),
        const LatLng(28.5355, 77.3910),
      ];

      final route = await routingService.getMultiStopRoute(stops);

      expect(route.isNotEmpty, isTrue);
      expect((route.first.latitude - stops.first.latitude).abs(), lessThan(0.01));
      expect((route.last.latitude - stops.last.latitude).abs(), lessThan(0.01));
    });
  });
}
