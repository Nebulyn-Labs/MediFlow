import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

final routingServiceProvider = Provider((ref) => RoutingService());

/// The result of a routing call: an ordered list of road-accurate [points]
/// plus optional route metadata when a real routing API was used.
class RouteResult {
  /// Road-accurate polyline coordinates (or a straight-line fallback).
  final List<LatLng> points;

  /// Road distance in kilometres, or `null` when only the straight-line
  /// fallback was available and no API distance was returned.
  final double? distanceKm;

  /// Estimated travel duration in seconds, or `null` when the API did not
  /// provide duration data (straight-line fallback case).
  final double? durationSeconds;

  const RouteResult({
    required this.points,
    this.distanceKm,
    this.durationSeconds,
  });

  /// Convenience: whether this result carries real road-routing metadata
  /// (as opposed to a straight-line fallback with no distance/duration).
  bool get hasRoadData => distanceKm != null && durationSeconds != null;
}

/// Converts a sequence of stop coordinates into a road-accurate polyline.
///
/// ### Inputs
/// - [getRoute]: a `start` and `end` [LatLng] pair.
/// - [getMultiStopRoute]: an ordered list of [LatLng] stops (typically
///   produced by `OptimizationService.calculateMultiStopRoutes`).
///
/// ### Outputs
/// - A [RouteResult] containing a list of [LatLng] points describing the
///   road path. For [getMultiStopRoute], consecutive per-segment routes are
///   concatenated, de-duplicating a shared boundary point where one
///   segment's last point equals the next segment's first point.
///   `distanceKm` and `durationSeconds` are the summed totals across all
///   segments when road data is available.
///
/// ### Algorithm assumptions
/// - **Provider order:** OpenRouteService (ORS) is preferred when an API
///   key is configured (`orsKey`, currently hardcoded to `null` and
///   therefore always skipped at runtime), falling back to the public
///   OSRM demo server, and finally to a straight-line fallback route
///   (`[start, end]`) if both external services fail or time out (5 s each).
/// - **Coordinate validation:** requests are only sent to ORS/OSRM when
///   both points are within valid latitude/longitude bounds and are not
///   known placeholder coordinates (`(0, 0)` or `(-1, -1)`, used
///   elsewhere in the codebase to mean "location not set"). This avoids
///   wasting external API calls on facilities with incomplete geodata.
/// - **Route caching:** routes are stored in an in-memory cache bounded to
///   100 entries (`_maxCacheSize`). When a cache miss occurs, failed segment
///   requests fall back to a straight line without retries, so a multi-stop
///   route can mix real road polylines and straight-line segments.
class RoutingService {
  static const String _osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';
  static const String _orsBaseUrl =
      'https://api.openrouteservice.org/v2/directions/driving-car';

  // Cache for storing previously fetched routes
  final Map<String, RouteResult> _routeCache = {};
  static const int _maxCacheSize = 100;

  /// Validates whether the latitude and longitude fall within
  /// valid geographic ranges.
  bool _isValidCoordinate(LatLng point) {
    return point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  /// Detects placeholder coordinates that should not trigger
  /// routing API requests.
  bool _isPlaceholderCoordinate(LatLng point) {
    return (point.latitude == 0.0 && point.longitude == 0.0) ||
        (point.latitude == -1.0 && point.longitude == -1.0);
  }

  /// Determines whether routing can be generated.
  bool _canGenerateRoute(LatLng start, LatLng end) {
    return _isValidCoordinate(start) &&
        _isValidCoordinate(end) &&
        !_isPlaceholderCoordinate(start) &&
        !_isPlaceholderCoordinate(end);
  }

  /// Returns a simple straight-line fallback [RouteResult] with no road data.
  RouteResult _fallbackRoute(LatLng start, LatLng end) {
    return RouteResult(points: [start, end]);
  }

  String _generateCacheKey(LatLng start, LatLng end) {
    String format(double value) => value.toStringAsFixed(6);

    return '${format(start.latitude)},${format(start.longitude)}'
        '_'
        '${format(end.latitude)},${format(end.longitude)}';
  }

  /// Stores a route in the cache while keeping the cache size bounded.
  void _cacheRoute(String key, RouteResult route) {
    if (_routeCache.length >= _maxCacheSize) {
      _routeCache.remove(_routeCache.keys.first);
    }
    _routeCache[key] = route;
  }

  Future<RouteResult> getRoute(LatLng start, LatLng end) async {
    final String? orsKey = null;

    // Validate coordinates before making external API requests.
    if (!_canGenerateRoute(start, end)) {
      debugPrint(
        'RoutingService: Invalid or placeholder coordinates detected. '
        'Skipping external routing request.',
      );
      return _fallbackRoute(start, end);
    }

    final cacheKey = _generateCacheKey(start, end);
    final cachedRoute = _routeCache[cacheKey];
    if (cachedRoute != null) {
      debugPrint('RoutingService: Returning cached route.');
      return cachedRoute;
    }

    // 1. Try OpenRouteService (ORS) if API key exists
    if (orsKey != null && orsKey.isNotEmpty) {
      try {
        final url =
            '$_orsBaseUrl?api_key=$orsKey&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}';

        debugPrint('RoutingService: Requesting ORS: $url');

        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final rawData = jsonDecode(response.body);
          if (rawData is Map<String, dynamic>) {
            final features = rawData['features'];
            if (features is List && features.isNotEmpty) {
              final firstFeature = features[0];
              if (firstFeature is Map) {
                final geometry = firstFeature['geometry'];
                if (geometry is Map && geometry['coordinates'] is List) {
                  final List<dynamic> coords = geometry['coordinates'] as List;

                  debugPrint(
                    'RoutingService: ORS Success. ${coords.length} points found.',
                  );

                  final route = coords
                      .whereType<List>()
                      .map((c) => LatLng(
                          (c[1] as num).toDouble(), (c[0] as num).toDouble()))
                      .toList();

                  // ORS reports distance in metres and duration in seconds.
                  final properties = firstFeature['properties'];
                  final summary =
                      properties is Map ? properties['summary'] : null;
                  final distance = summary is Map ? summary['distance'] : null;
                  final duration = summary is Map ? summary['duration'] : null;

                  final result = RouteResult(
                    points: route,
                    distanceKm:
                        distance is num ? distance.toDouble() / 1000.0 : null,
                    durationSeconds:
                        duration is num ? duration.toDouble() : null,
                  );

                  _cacheRoute(cacheKey, result);

                  debugPrint('RoutingService: Route cached (ORS).');

                  return result;
                }
              }
            }
          }
        } else {
          debugPrint(
            'RoutingService: ORS Failed with status ${response.statusCode}',
          );
        }
      } catch (e, stackTrace) {
        debugPrint('RoutingService: ORS routing error: $e');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    // 2. Fallback to OSRM
    try {
      final url =
          '$_osrmBaseUrl/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';

      debugPrint('RoutingService: Requesting OSRM: $url');

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final rawData = jsonDecode(response.body);
        if (rawData is Map<String, dynamic>) {
          final routes = rawData['routes'];
          if (routes is List && routes.isNotEmpty) {
            final firstRoute = routes[0];
            if (firstRoute is Map) {
              final geometry = firstRoute['geometry'];
              if (geometry is Map && geometry['coordinates'] is List) {
                final List<dynamic> coords = geometry['coordinates'] as List;

                debugPrint(
                  'RoutingService: OSRM Success. ${coords.length} points found.',
                );

                final route = coords
                    .whereType<List>()
                    .map((c) => LatLng(
                        (c[1] as num).toDouble(), (c[0] as num).toDouble()))
                    .toList();

                // OSRM reports distance in metres and duration in seconds.
                final distance = firstRoute['distance'];
                final duration = firstRoute['duration'];

                final result = RouteResult(
                  points: route,
                  distanceKm:
                      distance is num ? distance.toDouble() / 1000.0 : null,
                  durationSeconds: duration is num ? duration.toDouble() : null,
                );

                _cacheRoute(cacheKey, result);

                debugPrint('RoutingService: Route cached (OSRM).');

                return result;
              }
            }
          }
        }
      } else {
        debugPrint(
          'RoutingService: OSRM Failed with status ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('RoutingService: OSRM routing error: $e');
      debugPrintStack(stackTrace: stackTrace);
    }

    // Final fallback
    debugPrint('RoutingService: Falling back to straight-line route.');

    return _fallbackRoute(start, end);
  }

  Future<RouteResult> getMultiStopRoute(List<LatLng> stops) async {
    if (stops.isEmpty) return const RouteResult(points: []);
    if (stops.length == 1) return RouteResult(points: stops);

    List<LatLng> fullRoute = [];
    double totalDistanceKm = 0;
    double totalDurationSeconds = 0;
    bool hasRoadDataForEverySegment = true;

    for (int i = 0; i < stops.length - 1; i++) {
      final segResult = await getRoute(stops[i], stops[i + 1]);
      if (segResult.points.isNotEmpty) {
        if (fullRoute.isNotEmpty && fullRoute.last == segResult.points.first) {
          fullRoute.addAll(segResult.points.skip(1));
        } else {
          fullRoute.addAll(segResult.points);
        }
      }
      if (segResult.hasRoadData) {
        totalDistanceKm += segResult.distanceKm!;
        totalDurationSeconds += segResult.durationSeconds!;
      } else {
        // Tracked as a flag rather than by nulling the running totals: a
        // later segment with road data would otherwise restart the sum from
        // zero and the partial figure would be reported as a road distance.
        hasRoadDataForEverySegment = false;
      }
    }

    return RouteResult(
      points: fullRoute,
      distanceKm: hasRoadDataForEverySegment ? totalDistanceKm : null,
      durationSeconds: hasRoadDataForEverySegment ? totalDurationSeconds : null,
    );
  }
}
