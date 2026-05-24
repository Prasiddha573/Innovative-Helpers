import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/route_model.dart';

/// Talks to the Python backend that runs A* + Dijkstra on the OSM road graph.
class RoutingService {
  /// POST /route   body: { from:[lat,lng], to:[lat,lng], hazards:[...] }
  /// returns RouteModel with primary (A*) and secondary (Dijkstra) paths.
  static Future<RouteModel> findRoute({
    required LatLng from,
    required LatLng to,
    List<Map<String, dynamic>> hazards = const [],
  }) async {
    final uri = Uri.parse('${AppConfig.backendUrl}/route');
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'from': [from.latitude, from.longitude],
              'to': [to.latitude, to.longitude],
              'hazards': hazards,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return _straightLine(from, to);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return RouteModel.fromJson(json);
    } catch (_) {
      return _straightLine(from, to);
    }
  }

  /// POST /nearest_ambulance body: { casualty:[lat,lng] }
  /// returns { ambulance_id, lat, lng }
  static Future<Map<String, dynamic>?> findNearestAmbulance({
    required LatLng casualty,
    required List<Map<String, dynamic>> ambulances,
  }) async {
    final uri = Uri.parse('${AppConfig.backendUrl}/nearest_ambulance');
    try {
      final response = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'casualty': [casualty.latitude, casualty.longitude],
                'ambulances': ambulances,
              }))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Offline-safe fallback: render a straight-line primary and a slightly
  /// offset secondary so the UI still works when the backend is unreachable.
  static RouteModel _straightLine(LatLng from, LatLng to) {
    final mid = LatLng(
      (from.latitude + to.latitude) / 2,
      (from.longitude + to.longitude) / 2,
    );
    final detour = LatLng(
      mid.latitude + 0.004,
      mid.longitude + 0.004,
    );
    final dKm = const Distance().as(LengthUnit.Kilometer, from, to);
    return RouteModel(
      primary: [from, to],
      secondary: [from, detour, to],
      primaryCostKm: dKm,
      secondaryCostKm: dKm * 1.2,
    );
  }
}
