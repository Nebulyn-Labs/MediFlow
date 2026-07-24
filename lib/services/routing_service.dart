import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

final routingServiceProvider = Provider((ref) => RoutingService());

class RoutingService {
  static const String _osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';
  static const String _orsBaseUrl =
      'https://api.openrouteservice.org/v2/directions/driving-car';
  
  // Cache for storing previously fetched routes
  final Map<String, List<LatLng>> _routeCache = {};
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

  /// Returns a simple straight-line fallback route.
  List<LatLng> _fallbackRoute(LatLng start, LatLng end) {
    return [start, end];
  }

  String _generateCacheKey(LatLng start, LatLng end) {
    String format(double value) => value.toStringAsFixed(6);

     return '${format(start.latitude)},${format(start.longitude)}'
       '_'
       '${format(end.latitude)},${format(end.longitude)}';
  }

  /// Stores a route in the cache while keeping the cache size bounded.
  void _cacheRoute(String key, List<LatLng> route) {
       if (_routeCache.length >= _maxCacheSize) {
        _routeCache.remove(_routeCache.keys.first);
      }

    _routeCache[key] = route;
  }


  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    const String? orsKey = null;

    // Validate coordinates before making external API requests.
    if (!_canGenerateRoute(start, end)) {
      debugPrint(
        'RoutingService: Invalid or placeholder coordinates detected. '
        'Skipping external routing request.',
      );
      return _fallbackRoute(start, end);
    }

    final cacheKey = _generateCacheKey(start, end);

    if (_routeCache.containsKey(cacheKey)) {
      debugPrint('RoutingService: Returning cached route.');
      return _routeCache[cacheKey]!;
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
          final data = jsonDecode(response.body);

          if (data['features'] != null && data['features'].isNotEmpty) {
            final List<dynamic> coords =
                data['features'][0]['geometry']['coordinates'];

            debugPrint(
              'RoutingService: ORS Success. ${coords.length} points found.',
            );

            final route = coords
                .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();

            _cacheRoute(cacheKey, route);

             debugPrint('RoutingService: Route cached (ORS).');

            return route;
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
        final data = jsonDecode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List<dynamic> coords =
              data['routes'][0]['geometry']['coordinates'];

          debugPrint(
            'RoutingService: OSRM Success. ${coords.length} points found.',
          );

          final route = coords
              .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
              .toList();
          
          _cacheRoute(cacheKey, route);

          debugPrint('RoutingService: Route cached (OSRM).');

          return route;
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
    final route = _fallbackRoute(start, end);

    _cacheRoute(cacheKey, route);

    return route;
  }

  Future<List<LatLng>> getMultiStopRoute(List<LatLng> stops) async {
    if (stops.isEmpty) return [];
    if (stops.length == 1) return stops;

    List<LatLng> fullRoute = [];
    for (int i = 0; i < stops.length - 1; i++) {
      final segment = await getRoute(stops[i], stops[i + 1]);
      if (segment.isNotEmpty) {
        if (fullRoute.isNotEmpty && fullRoute.last == segment.first) {
          fullRoute.addAll(segment.skip(1));
        } else {
          fullRoute.addAll(segment);
        }
      }
    }
    return fullRoute;
  }
}
