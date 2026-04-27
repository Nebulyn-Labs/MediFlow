import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Uses free OSRM API to get real road routes between two points.
class RoutingService {
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  /// Fetches actual road geometry between two coordinates.
  /// Returns a list of LatLng points tracing the road.
  /// Falls back to a straight line if the API fails.
  static Future<List<LatLng>> getRoute(LatLng from, LatLng to) async {
    try {
      final url = '$_baseUrl/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final coords = routes[0]['geometry']['coordinates'] as List;
          return coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
        }
      }
    } catch (e) {
      print('OSRM routing failed: $e');
    }
    // Fallback: straight line
    return [from, to];
  }
}
