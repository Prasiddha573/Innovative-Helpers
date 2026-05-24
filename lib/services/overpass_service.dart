import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

/// Loads OSM/Overpass features restricted to the Kavrepalanchok district
/// bounding box. Categories pulled (per blueprint section 3 & 11):
///   - roads (highway=*) - as polylines and graph edges
///   - hospitals (amenity=hospital)
///   - wards (admin_level=8/9 boundaries OR name~"ward")
///   - forests (landuse=forest, natural=wood)
class OverpassFeature {
  final String id;
  final String kind; // road | hospital | ward | forest
  final String? name;
  final List<LatLng> geometry;

  OverpassFeature({
    required this.id,
    required this.kind,
    required this.geometry,
    this.name,
  });
}

class OverpassResult {
  final List<OverpassFeature> roads;
  final List<OverpassFeature> hospitals;
  final List<OverpassFeature> wards;
  final List<OverpassFeature> forests;

  OverpassResult({
    required this.roads,
    required this.hospitals,
    required this.wards,
    required this.forests,
  });

  bool get isEmpty =>
      roads.isEmpty && hospitals.isEmpty && wards.isEmpty && forests.isEmpty;
}

class OverpassService {
  /// Try the live Overpass API first; on failure fall back to the bundled
  /// cached snapshot for Kavrepalanchok shipped under `assets/data/`.
  static Future<OverpassResult> loadKavrepalanchok({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      final live = await _fetchLive(timeout);
      if (!live.isEmpty) return live;
    } catch (_) {
      // ignore and fall through to bundled snapshot
    }
    return _loadBundled();
  }

  static Future<OverpassResult> _fetchLive(Duration timeout) async {
    final s = AppConfig.bboxSouth;
    final w = AppConfig.bboxWest;
    final n = AppConfig.bboxNorth;
    final e = AppConfig.bboxEast;

    // The query is intentionally restricted to Kavrepalanchok district bbox.
    final query = '''
[out:json][timeout:25];
(
  way["highway"]($s,$w,$n,$e);
  node["amenity"="hospital"]($s,$w,$n,$e);
  way["amenity"="hospital"]($s,$w,$n,$e);
  relation["boundary"="administrative"]["admin_level"~"8|9"]($s,$w,$n,$e);
  way["landuse"="forest"]($s,$w,$n,$e);
  way["natural"="wood"]($s,$w,$n,$e);
);
out body geom;
''';

    final response = await http
        .post(
          Uri.parse(AppConfig.overpassUrl),
          body: {'data': query},
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Overpass HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseOverpassJson(json);
  }

  static Future<OverpassResult> _loadBundled() async {
    final raw = await rootBundle
        .loadString('assets/data/kavrepalanchok_demo.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return _parseOverpassJson(json);
  }

  static OverpassResult _parseOverpassJson(Map<String, dynamic> json) {
    final elements = (json['elements'] as List?) ?? const [];
    final roads = <OverpassFeature>[];
    final hospitals = <OverpassFeature>[];
    final wards = <OverpassFeature>[];
    final forests = <OverpassFeature>[];

    for (final el in elements) {
      final m = (el as Map).cast<String, dynamic>();
      final tags = ((m['tags'] ?? {}) as Map).cast<String, dynamic>();
      final id = '${m['type']}/${m['id']}';
      final name = tags['name'] as String?;
      final geom = _extractGeometry(m);

      if (geom.isEmpty) continue;

      if (tags.containsKey('highway')) {
        roads.add(OverpassFeature(
          id: id,
          kind: 'road',
          geometry: geom,
          name: name,
        ));
      } else if (tags['amenity'] == 'hospital') {
        hospitals.add(OverpassFeature(
          id: id,
          kind: 'hospital',
          geometry: geom,
          name: name ?? 'Hospital',
        ));
      } else if (tags['boundary'] == 'administrative') {
        wards.add(OverpassFeature(
          id: id,
          kind: 'ward',
          geometry: geom,
          name: name ?? 'Ward',
        ));
      } else if (tags['landuse'] == 'forest' || tags['natural'] == 'wood') {
        forests.add(OverpassFeature(
          id: id,
          kind: 'forest',
          geometry: geom,
          name: name ?? 'Forest',
        ));
      }
    }

    return OverpassResult(
      roads: roads,
      hospitals: hospitals,
      wards: wards,
      forests: forests,
    );
  }

  static List<LatLng> _extractGeometry(Map<String, dynamic> el) {
    // node element
    if (el['type'] == 'node' && el['lat'] != null && el['lon'] != null) {
      return [LatLng((el['lat'] as num).toDouble(),
          (el['lon'] as num).toDouble())];
    }
    // way element with embedded geometry (Overpass `out body geom`)
    if (el['geometry'] is List) {
      return (el['geometry'] as List)
          .map((p) => LatLng(
              (p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()))
          .toList();
    }
    // relation member geometries
    if (el['members'] is List) {
      final points = <LatLng>[];
      for (final mb in el['members'] as List) {
        if (mb is Map && mb['geometry'] is List) {
          for (final p in mb['geometry'] as List) {
            points.add(LatLng(
                (p['lat'] as num).toDouble(),
                (p['lon'] as num).toDouble()));
          }
        }
      }
      return points;
    }
    return const [];
  }
}
