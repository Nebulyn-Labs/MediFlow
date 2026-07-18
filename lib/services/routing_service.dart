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

            return coords
                .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();
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

          return coords
              .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
              .toList();
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
}