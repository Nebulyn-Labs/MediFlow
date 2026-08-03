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
