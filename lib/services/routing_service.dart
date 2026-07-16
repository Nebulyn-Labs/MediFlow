import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

final routingServiceProvider = Provider((ref) => RoutingService());

class RoutingService {
  static const String _osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';
  static const String _orsBaseUrl =
      'https://api.openrouteservice.org/v2/directions/driving-car';

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    const String? orsKey = null;

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
                'RoutingService: ORS Success. ${coords.length} points found.');
            return coords
                .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();
          }
        } else {
          debugPrint(
              'RoutingService: ORS Failed with status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('ORS routing error: $e');
      }
    }

    // 2. Fallback to OSRM (using GeoJSON to avoid polyline decoding issues)
    try {
      final url =
          '$_osrmBaseUrl/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
      debugPrint('RoutingService: Requesting OSRM (GeoJSON): $url');
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List<dynamic> coords =
              data['routes'][0]['geometry']['coordinates'];
          debugPrint(
              'RoutingService: OSRM Success. ${coords.length} points found.');
          // OSRM GeoJSON is [longitude, latitude]
          return coords
              .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
              .toList();
        }
      } else {
        debugPrint(
            'RoutingService: OSRM Failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('OSRM routing error: $e');
    }

    // 3. Absolute Fallback to straight line
    debugPrint('RoutingService: Falling back to straight line.');
    return [start, end];
  }
}
