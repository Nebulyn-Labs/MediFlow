import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:med_supply_prototype/services/routing_service.dart';

/// Returns canned per-segment results so `getMultiStopRoute` can be exercised
/// without touching ORS or OSRM.
class _StubRoutingService extends RoutingService {
  _StubRoutingService(this.segments);

  final List<RouteResult> segments;
  int _callCount = 0;

  @override
  Future<RouteResult> getRoute(LatLng start, LatLng end) async {
    return segments[_callCount++];
  }
}

RouteResult _roadLeg(double km, double seconds) => RouteResult(
      points: const [LatLng(1, 1), LatLng(2, 2)],
      distanceKm: km,
      durationSeconds: seconds,
    );

RouteResult _fallbackLeg() =>
    const RouteResult(points: [LatLng(1, 1), LatLng(2, 2)]);

void main() {
  group('RoutingService Unit Tests', () {
    late RoutingService routingService;

    setUp(() {
      routingService = RoutingService();
    });

    test('returns straight-line fallback for placeholder coordinate (0, 0)',
        () async {
      final start = const LatLng(0.0, 0.0);
      final end = const LatLng(28.61, 77.21);

      final route = await routingService.getRoute(start, end);

      expect(route.points, equals([start, end]));
    });

    test('returns straight-line fallback for placeholder coordinate (-1, -1)',
        () async {
      final start = const LatLng(28.61, 77.21);
      final end = const LatLng(-1.0, -1.0);

      final route = await routingService.getRoute(start, end);

      expect(route.points, equals([start, end]));
    });

    test(
        'returns straight-line fallback for invalid out-of-bounds latitude/longitude',
        () async {
      final start = const LatLng(95.0, 77.21); // invalid lat > 90
      final end = const LatLng(28.61, 200.0); // invalid lng > 180

      final route = await routingService.getRoute(start, end);

      expect(route.points, equals([start, end]));
    });

    test('getMultiStopRoute returns empty points for empty stops', () async {
      final route = await routingService.getMultiStopRoute([]);
      expect(route.points, isEmpty);
    });

    test('getMultiStopRoute returns single stop for 1 stop', () async {
      final stop = const LatLng(28.61, 77.21);
      final route = await routingService.getMultiStopRoute([stop]);
      expect(route.points, equals([stop]));
    });

    test('getMultiStopRoute generates segments for multiple valid stops',
        () async {
      final stops = [
        const LatLng(28.6139, 77.2090),
        const LatLng(28.7041, 77.1025),
        const LatLng(28.5355, 77.3910),
      ];

      final route = await routingService.getMultiStopRoute(stops);

      expect(route.points.isNotEmpty, isTrue);
      expect((route.points.first.latitude - stops.first.latitude).abs(),
          lessThan(0.01));
      expect((route.points.last.latitude - stops.last.latitude).abs(),
          lessThan(0.01));
    });
  });

  group('RoutingService.getMultiStopRoute', () {
    // Four stops produce three legs.
    final fourStops = const [
      LatLng(1, 1),
      LatLng(2, 2),
      LatLng(3, 3),
      LatLng(4, 4),
    ];

    test('sums distance and duration when every leg has road data', () async {
      final service = _StubRoutingService([
        _roadLeg(10, 600),
        _roadLeg(5, 300),
        _roadLeg(8, 480),
      ]);

      final result = await service.getMultiStopRoute(fourStops);

      expect(result.distanceKm, 23);
      expect(result.durationSeconds, 1380);
      expect(result.hasRoadData, isTrue);
    });

    test('withholds totals when a road leg follows a fallback leg', () async {
      final service = _StubRoutingService([
        _roadLeg(10, 600),
        _fallbackLeg(),
        _roadLeg(8, 480),
      ]);

      final result = await service.getMultiStopRoute(fourStops);

      expect(result.distanceKm, isNull);
      expect(result.durationSeconds, isNull);
      expect(result.hasRoadData, isFalse);
    });

    test('withholds totals when the final leg falls back', () async {
      final service = _StubRoutingService([
        _roadLeg(10, 600),
        _roadLeg(5, 300),
        _fallbackLeg(),
      ]);

      final result = await service.getMultiStopRoute(fourStops);

      expect(result.distanceKm, isNull);
      expect(result.hasRoadData, isFalse);
    });
  });
}
