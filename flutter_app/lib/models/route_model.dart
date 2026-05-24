import 'package:latlong2/latlong.dart';

/// Backend route response. Contains the primary (shortest) and optional
/// secondary (fallback) path - used for the dual-path demo overlay.
class RouteModel {
  final List<LatLng> primary;
  final List<LatLng> secondary;
  final double primaryCostKm;
  final double secondaryCostKm;
  final String algorithmPrimary;
  final String algorithmSecondary;

  RouteModel({
    required this.primary,
    required this.secondary,
    required this.primaryCostKm,
    required this.secondaryCostKm,
    this.algorithmPrimary = 'astar',
    this.algorithmSecondary = 'dijkstra',
  });

  static RouteModel empty() => RouteModel(
        primary: const [],
        secondary: const [],
        primaryCostKm: 0,
        secondaryCostKm: 0,
      );

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    List<LatLng> _decode(List? raw) {
      if (raw == null) return const [];
      return raw
          .whereType<List>()
          .map((pair) => LatLng(
                (pair[0] as num).toDouble(),
                (pair[1] as num).toDouble(),
              ))
          .toList();
    }

    return RouteModel(
      primary: _decode(json['primary'] as List?),
      secondary: _decode(json['secondary'] as List?),
      primaryCostKm: ((json['primary_cost_km'] ?? 0) as num).toDouble(),
      secondaryCostKm: ((json['secondary_cost_km'] ?? 0) as num).toDouble(),
      algorithmPrimary: (json['algorithm_primary'] ?? 'astar') as String,
      algorithmSecondary: (json['algorithm_secondary'] ?? 'dijkstra') as String,
    );
  }
}
