import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../models/ambulance_model.dart';
import '../../models/casualty_model.dart';
import '../../models/hazard_model.dart';
import '../../services/demo_data_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/overpass_service.dart';
import '../../services/toast_service.dart';
import '../../themes/colors.dart';
import '../../widgets/map_widget.dart';

/// Casualty screen with full-screen map
class CasualtyScreen extends StatefulWidget {
  const CasualtyScreen({super.key});

  @override
  State<CasualtyScreen> createState() => _CasualtyScreenState();
}

class _CasualtyScreenState extends State<CasualtyScreen> {
  final _toast = ToastService();
  final _fs = FirestoreService();
  final _mapCtrl = MapController();
  final _authCtrl = Get.find<AuthController>();

  OverpassResult? _osm;
  List<AmbulanceModel> _ambulances = [];
  List<HazardModel> _hazards = [];

  bool _confirmingPin = false;
  LatLng? _casualtyPoint;
  LatLng? _selectedPoint;
  AmbulanceModel? _dispatchedAmbulance;
  LatLng? _ambulancePosition;

  // Route data stored locally
  List<LatLng> _routePoints = [];
  List<LatLng> _alternativeRoutePoints = [];
  double _routeDistance = 0.0;
  double _routeDuration = 0.0;

  Timer? _animTimer;
  int _animIndex = 0;
  int _totalAnimationFrames = 60;
  _Phase _phase = _Phase.idle;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await LocationService.getCurrentOrDefault();
    final osm = await OverpassService.loadKavrepalanchok();
    if (!mounted) return;
    setState(() {
      _osm = osm;
      _casualtyPoint = null;
      _selectedPoint = null;
    });

    _fs.watchAmbulances().listen((list) {
      if (!mounted) return;
      final list2 = list.isEmpty ? DemoData.seedAmbulances() : list;
      setState(() => _ambulances = list2);
    });

    _fs.watchHazards().listen((list) {
      if (!mounted) return;
      setState(() => _hazards = list);
    });

    for (final a in DemoData.seedAmbulances()) {
      _fs.upsertAmbulance(a);
    }
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Hazard helpers
  // ---------------------------------------------------------------------------

  /// Returns true if [point] is within 30 m of any hazard.
  bool _isPointNearHazard(LatLng point) {
    const distance = Distance();
    for (final hazard in _hazards) {
      if (distance.as(LengthUnit.Meter, point, hazard.latLng) < 30) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if any sampled point along [points] is within 30 m of a hazard.
  /// Samples every 5th point for performance.
  bool _routeHasHazard(List<LatLng> points) {
    const distance = Distance();
    for (int i = 0; i < points.length; i += 5) {
      for (final hazard in _hazards) {
        if (distance.as(LengthUnit.Meter, points[i], hazard.latLng) < 30) {
          return true;
        }
      }
    }
    // Also always check the last point
    if (points.isNotEmpty) {
      for (final hazard in _hazards) {
        if (distance.as(LengthUnit.Meter, points.last, hazard.latLng) < 30) {
          return true;
        }
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Routing – strict hazard avoidance with multiple alternatives
  // ---------------------------------------------------------------------------

  /// Fetches a route from [from] to [to] with STRICT hazard avoidance.
  /// Tries multiple routing engines and strategies in order:
  ///   1. OSRM alternatives (direct routes)
  ///   2. GraphHopper (different road graph)
  ///   3. OSRM with grid-based waypoint detours
  ///   4. OSRM with perpendicular detours
  ///   5. Vroom vehicle routing (if available)
  ///
  /// NEVER returns a direct displacement or straight-line path.
  /// Only returns actual routed paths that avoid hazards.
  Future<Map<String, dynamic>> _fetchSafeRoute(LatLng from, LatLng to) async {
    debugPrint('🛣️ Fetching safe route from $from to $to');

    // ── Strategy 1: OSRM alternatives (direct routes) ───────────────────────
    debugPrint('📍 Strategy 1: Trying OSRM direct routes...');
    var result = await _tryOsrmDirectRoutes(from, to);
    if (result != null) {
      _toast.showInfoMessage('✅ Safe route found via OSRM');
      return result;
    }

    // ── Strategy 2: GraphHopper routing ──────────────────────────────────────
    debugPrint('📍 Strategy 2: Trying GraphHopper routing...');
    result = await _tryGraphHopperRoute(from, to);
    if (result != null) {
      _toast.showInfoMessage('✅ Safe route found via GraphHopper');
      return result;
    }

    // ── Strategy 3: OSRM with grid-based waypoint detours ────────────────────
    debugPrint('📍 Strategy 3: Trying OSRM with grid waypoints...');
    result = await _tryGridBasedRoute(from, to);
    if (result != null) {
      _toast.showInfoMessage('✅ Safe route found via grid detours');
      return result;
    }

    // ── Strategy 4: OSRM with perpendicular detours ───────────────────────────
    debugPrint('📍 Strategy 4: Trying OSRM with perpendicular detours...');
    result = await _tryPerpendicularDetourRoutes(from, to);
    if (result != null) {
      _toast.showInfoMessage('✅ Safe route found via perpendicular detours');
      return result;
    }

    // ── Strategy 5: Vroom vehicle routing (if available) ─────────────────────
    debugPrint('📍 Strategy 5: Trying Vroom vehicle routing...');
    result = await _tryVroomRoute(from, to);
    if (result != null) {
      _toast.showInfoMessage('✅ Safe route found via Vroom routing');
      return result;
    }

    // ── All strategies exhausted ────────────────────────────────────────────
    _toast.showErrorMessage('⚠️ No safe route found after all strategies');
    throw Exception(
      'Unable to find safe route after 5 strategies. '
          'All hazards block available paths or services unavailable.',
    );
  }

  /// Strategy 1: Collect OSRM alternatives and return shortest hazard-free.
  Future<Map<String, dynamic>?> _tryOsrmDirectRoutes(
      LatLng from,
      LatLng to,
      ) async {
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};'
          '${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson&steps=true&alternatives=3';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null) {
          final candidates = <Map<String, dynamic>>[];
          for (final route in data['routes'] as List) {
            final coords = route['geometry']['coordinates'] as List;
            final points = coords
                .map((c) =>
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                .toList();
            candidates.add({
              'points': points,
              'distance': (route['distance'] as num).toDouble(),
              'duration': (route['duration'] as num).toDouble(),
            });
          }

          // Filter to hazard-free routes
          final safeRoutes = candidates
              .where((r) => !_routeHasHazard(r['points'] as List<LatLng>))
              .toList();

          if (safeRoutes.isNotEmpty) {
            // Return shortest safe route
            safeRoutes.sort((a, b) =>
                (a['distance'] as double)
                    .compareTo(b['distance'] as double));
            debugPrint(
              'OSRM: Found safe route (${((safeRoutes.first['distance'] as double) / 1000).toStringAsFixed(2)} km)',
            );
            return safeRoutes.first;
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM direct routes failed: $e');
    }
    return null;
  }

  /// Strategy 2: Try GraphHopper routing (different road graph than OSRM).
  Future<Map<String, dynamic>?> _tryGraphHopperRoute(
      LatLng from,
      LatLng to,
      ) async {
    try {
      final url = 'https://graphhopper.com/api/1/route'
          '?point=${from.latitude},${from.longitude}'
          '&point=${to.latitude},${to.longitude}'
          '&vehicle=car'
          '&locale=en'
          '&points_encoded=false'
          '&key=8c5c9e7b-1234-5678-9abc-def012345678'; // Replace with actual key

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['paths'] != null && (data['paths'] as List).isNotEmpty) {
          final path = (data['paths'] as List).first;
          final points = path['points']['coordinates'] as List;
          final routePoints = points
              .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
              .toList();

          if (!_routeHasHazard(routePoints)) {
            debugPrint(
              'GraphHopper: Found safe route (${(path['distance'] as num) / 1000} km)',
            );
            return {
              'points': routePoints,
              'distance': (path['distance'] as num).toDouble(),
              'duration': (path['time'] as num).toDouble() / 1000,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('GraphHopper routing failed: $e');
    }
    return null;
  }

  /// Strategy 3: Generate grid-based waypoints around hazard zones and route through them.
  Future<Map<String, dynamic>?> _tryGridBasedRoute(
      LatLng from,
      LatLng to,
      ) async {
    try {
      final waypoints = _generateGridWaypoints(from, to);
      if (waypoints.isEmpty) return null;

      // Build waypoint string for OSRM
      final waypointStr = [from, ...waypoints, to]
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');

      final url = 'https://router.project-osrm.org/route/v1/driving/$waypointStr'
          '?overview=full&geometries=geojson&steps=true';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = (data['routes'] as List).first;
          final coords = route['geometry']['coordinates'] as List;
          final points = coords
              .map((c) =>
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();

          if (!_routeHasHazard(points)) {
            debugPrint(
              'Grid-based: Found safe route (${(route['distance'] as num) / 1000} km)',
            );
            return {
              'points': points,
              'distance': (route['distance'] as num).toDouble(),
              'duration': (route['duration'] as num).toDouble(),
            };
          }
        }
      }
    } catch (e) {
      debugPrint('Grid-based routing failed: $e');
    }
    return null;
  }

  /// Generate grid-based waypoints perpendicular to the main route.
  /// Returns waypoints that force routing to go around hazard zones.
  List<LatLng> _generateGridWaypoints(LatLng from, LatLng to, {int numWaypoints = 3, double metersOffset = 200}) {
    final waypoints = <LatLng>[];
    final segmentDistance = _calculateHaversineDistance(from, to);
    if (segmentDistance < 100) return waypoints;

    for (int i = 1; i <= numWaypoints; i++) {
      final t = i / (numWaypoints + 1);
      final midPoint = LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      );

      // Alternate left/right perpendicular offsets
      final side = i % 2 == 0 ? 1.0 : -1.0;
      final offset = _perpendicularOffset(from, to, midPoint, metersOffset * side);
      waypoints.add(offset);
    }
    return waypoints;
  }

  /// Strategy 4: Try perpendicular detours around detected blocking hazards.
  Future<Map<String, dynamic>?> _tryPerpendicularDetourRoutes(
      LatLng from,
      LatLng to,
      ) async {
    final detourRoutes = <Map<String, dynamic>>[];

    for (final hazard in _hazards) {
      // Try both perpendicular sides (left +60 m, right −60 m).
      for (final side in [1.0, -1.0]) {
        final waypoint =
        _perpendicularOffset(from, to, hazard.latLng, 60.0 * side);

        try {
          final url = 'https://router.project-osrm.org/route/v1/driving/'
              '${from.longitude},${from.latitude};'
              '${waypoint.longitude},${waypoint.latitude};'
              '${to.longitude},${to.latitude}'
              '?overview=full&geometries=geojson&steps=true';

          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 8));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['routes'] != null &&
                (data['routes'] as List).isNotEmpty) {
              final route = (data['routes'] as List).first;
              final coords = route['geometry']['coordinates'] as List;
              final points = coords
                  .map((c) =>
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                  .toList();

              if (!_routeHasHazard(points)) {
                detourRoutes.add({
                  'points': points,
                  'distance': (route['distance'] as num).toDouble(),
                  'duration': (route['duration'] as num).toDouble(),
                });
              }
            }
          }
        } catch (e) {
          debugPrint('Perpendicular detour failed (side=$side): $e');
        }
      }
    }

    if (detourRoutes.isNotEmpty) {
      detourRoutes.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));
      debugPrint(
        'Perpendicular detours: Found safe route (${((detourRoutes.first['distance'] as double) / 1000).toStringAsFixed(2)} km)',
      );
      return detourRoutes.first;
    }

    return null;
  }

  /// Strategy 5: Try Vroom vehicle routing (optimization-based).
  /// Requires Vroom service running at http://localhost:3000 or configured URL.
  Future<Map<String, dynamic>?> _tryVroomRoute(
      LatLng from,
      LatLng to,
      ) async {
    try {
      const vroomUrl = 'http://localhost:3000'; // Configure for your Vroom service
      const vroomApiKey = 'your_vroom_api_key_here'; // Optional

      // Build Vroom request payload
      final payload = {
        'vehicles': [
          {
            'id': 1,
            'start': [from.longitude, from.latitude],
            'end': [to.longitude, to.latitude],
          }
        ],
        'jobs': [
          {
            'id': 1,
            'location': [to.longitude, to.latitude],
          }
        ],
      };

      final response = await http
          .post(
        Uri.parse('$vroomUrl/route?key=$vroomApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = (data['routes'] as List).first;
          final geometry = route['geometry'];

          if (geometry is String && geometry.isNotEmpty) {
            // Decode polyline
            final points = _decodePolyline(geometry);
            if (points.isNotEmpty && !_routeHasHazard(points)) {
              debugPrint(
                'Vroom: Found safe route (${route['distance'] / 1000} km)',
              );
              return {
                'points': points,
                'distance': (route['distance'] as num).toDouble(),
                'duration': (route['duration'] as num).toDouble(),
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Vroom routing failed: $e');
    }
    return null;
  }

  /// Decode polyline string (common in routing APIs).
  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0, lng = 0;

    while (index < encoded.length) {
      int result = 0;
      int shift = 0;

      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      int deltaLat = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lat += deltaLat;

      result = 0;
      shift = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      int deltaLng = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lng += deltaLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  /// Returns a [LatLng] that is [offsetMeters] metres perpendicular to the
  /// [from]→[to] bearing, centred on [near].
  /// Positive [offsetMeters] → left of the route; negative → right.
  LatLng _perpendicularOffset(
      LatLng from,
      LatLng to,
      LatLng near,
      double offsetMeters,
      ) {
    final dLon = (to.longitude - from.longitude) * pi / 180;
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;

    // Forward bearing of the route in radians.
    final bearing = atan2(
      sin(dLon) * cos(lat2),
      cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon),
    );

    // 90° perpendicular.
    final perpBearing = bearing + pi / 2;

    const R = 6371000.0; // Earth radius in metres.
    final d = offsetMeters / R;

    final lat = near.latitude * pi / 180;
    final lon = near.longitude * pi / 180;

    final newLat =
    asin(sin(lat) * cos(d) + cos(lat) * sin(d) * cos(perpBearing));
    final newLon = lon +
        atan2(
          sin(perpBearing) * sin(d) * cos(lat),
          cos(d) - sin(lat) * sin(newLat),
        );

    return LatLng(newLat * 180 / pi, newLon * 180 / pi);
  }

  // ---------------------------------------------------------------------------
  // Distance helpers
  // ---------------------------------------------------------------------------

  double _calculateHaversineDistance(LatLng from, LatLng to) {
    const d = Distance();
    return d.as(LengthUnit.Meter, from, to);
  }

  double _calculatePathDistance(List<LatLng> path) {
    if (path.length < 2) return 0.0;
    double total = 0;
    for (int i = 0; i < path.length - 1; i++) {
      total += _calculateHaversineDistance(path[i], path[i + 1]);
    }
    return total;
  }

  // ---------------------------------------------------------------------------
  // Pin / confirm flow
  // ---------------------------------------------------------------------------

  Future<void> _startConfirmFlow() async {
    HapticFeedback.lightImpact();
    setState(() {
      _confirmingPin = true;
      _phase = _Phase.confirming;
      _selectedPoint = null;
    });
    _mapCtrl.move(
      LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
      AppConfig.defaultZoom + 1,
    );
    _toast.showInfoMessage('Tap on map to place casualty location');
  }

  void _onMapTap(LatLng point) {
    if (!_confirmingPin) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedPoint = point);
    _toast.showInfoMessage('Location set');
  }

  Future<void> _onConfirm() async {
    if (_selectedPoint == null) {
      _toast.showErrorMessage('Please tap on map to select a location first');
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _casualtyPoint = _selectedPoint;
      _confirmingPin = false;
      _phase = _Phase.dispatching;
    });

    // Persist casualty
    final casualtyId = DemoData.newId();
    final casualty = CasualtyModel(
      id: casualtyId,
      lat: _casualtyPoint!.latitude,
      lng: _casualtyPoint!.longitude,
      reportedBy: _authCtrl.profile.value?.uid ?? 'unknown',
      createdAt: DateTime.now(),
    );
    await _fs.upsertCasualty(casualty);

    // Find nearest available ambulance
    final amb = await _findNearestAmbulanceWithOSRM(_casualtyPoint!);
    if (amb == null) {
      _toast.showErrorMessage('No ambulance is currently available');
      setState(() => _phase = _Phase.idle);
      return;
    }

    final locked = amb.copyWith(available: false, lockedFor: casualtyId);
    await _fs.upsertAmbulance(locked);

    // Fetch safe route
    try {
      final routeData = await _fetchSafeRoute(amb.latLng, _casualtyPoint!);

      setState(() {
        _dispatchedAmbulance = locked;
        _ambulancePosition = amb.latLng;
        _routePoints = routeData['points'] as List<LatLng>;
        _alternativeRoutePoints = [];
        _routeDistance = routeData['distance'] as double;
        _routeDuration = routeData['duration'] as double;
        _phase = _Phase.movingToCasualty;
        _animIndex = 0;
        _totalAnimationFrames = _calculateOptimalFrames(_routePoints);
      });

      _startAnimation();

      final distKm = (_routeDistance / 1000).toStringAsFixed(2);
      final durMin = (_routeDuration / 60).toStringAsFixed(0);
      _toast.showInfoMessage(
        'Ambulance dispatched from ${amb.stationName}\n'
            'Distance: $distKm km | ETA: $durMin min',
      );
    } catch (e) {
      _toast.showErrorMessage('Failed to find safe route: $e');
      final freed = locked.copyWith(available: true, lockedFor: null);
      await _fs.upsertAmbulance(freed);
      setState(() => _phase = _Phase.idle);
    }
  }

  // ---------------------------------------------------------------------------
  // Ambulance & hospital finders
  // ---------------------------------------------------------------------------

  Future<AmbulanceModel?> _findNearestAmbulanceWithOSRM(
      LatLng casualty) async {
    final available = _ambulances.where((a) => a.available).toList();
    if (available.isEmpty) return null;
    if (available.length == 1) return available.first;

    try {
      AmbulanceModel? nearest;
      double shortest = double.infinity;

      for (final amb in available) {
        try {
          final routeData = await _fetchSafeRoute(amb.latLng, casualty);
          final dist = routeData['distance'] as double;
          if (dist < shortest) {
            shortest = dist;
            nearest = amb;
          }
        } catch (_) {
          continue;
        }
      }
      return nearest ?? _haversineNearest(available, casualty);
    } catch (_) {
      return _haversineNearest(available, casualty);
    }
  }

  AmbulanceModel _haversineNearest(List<AmbulanceModel> list, LatLng to) {
    const d = Distance();
    list.sort((a, b) => d
        .as(LengthUnit.Meter, a.latLng, to)
        .compareTo(d.as(LengthUnit.Meter, b.latLng, to)));
    return list.first;
  }

  Future<LatLng?> _findNearestHospitalWithOSRM(LatLng from) async {
    final hospitals = (_osm?.hospitals ?? [])
        .map((f) => _centroid(f.geometry))
        .toList();

    if (hospitals.isEmpty) return null;
    if (hospitals.length == 1) return hospitals.first;

    try {
      LatLng? nearest;
      double shortest = double.infinity;

      for (final hosp in hospitals) {
        try {
          final routeData = await _fetchSafeRoute(from, hosp);
          final dist = routeData['distance'] as double;
          if (dist < shortest) {
            shortest = dist;
            nearest = hosp;
          }
        } catch (_) {
          continue;
        }
      }
      return nearest ?? _nearestHospitalHaversine(from);
    } catch (_) {
      return _nearestHospitalHaversine(from);
    }
  }

  LatLng? _nearestHospitalHaversine(LatLng from) {
    final pts =
    (_osm?.hospitals ?? []).map((f) => _centroid(f.geometry)).toList();
    if (pts.isEmpty) return null;
    const d = Distance();
    pts.sort((a, b) => d
        .as(LengthUnit.Meter, a, from)
        .compareTo(d.as(LengthUnit.Meter, b, from)));
    return pts.first;
  }

  // ---------------------------------------------------------------------------
  // Animation
  // ---------------------------------------------------------------------------

  int _calculateOptimalFrames(List<LatLng> path) {
    final totalDistance = _calculatePathDistance(path);
    if (totalDistance == 0) return 60;
    final base = (totalDistance / 500) * 60;
    return base.clamp(30, 300).toInt();
  }

  void _startAnimation() {
    _animTimer?.cancel();
    final path = _routePoints;

    if (path.length < 2) {
      _toast.showErrorMessage('Route path is too short for animation');
      return;
    }

    final fps = AppConfig.ambulanceFps;
    final totalFrames = _totalAnimationFrames;
    _animIndex = 0;

    _animTimer = Timer.periodic(
      Duration(milliseconds: 1000 ~/ fps),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        _animIndex++;
        final t = (_animIndex / totalFrames).clamp(0.0, 1.0);
        final pos = _interpolateAlongPath(path, t);

        if (pos != null) {
          setState(() => _ambulancePosition = pos);
          if (_animIndex % 3 == 0 && mounted) {
            try {
              _mapCtrl.move(pos, _mapCtrl.camera.zoom);
            } catch (_) {}
          }
        }

        if (t >= 1.0) {
          timer.cancel();
          _onArrived();
        }
      },
    );
  }

  Future<void> _onArrived() async {
    HapticFeedback.heavyImpact();

    if (_phase == _Phase.movingToCasualty) {
      final hosp = await _findNearestHospitalWithOSRM(_casualtyPoint!);
      if (hosp == null) {
        await _release();
        return;
      }

      try {
        final routeData = await _fetchSafeRoute(_casualtyPoint!, hosp);

        setState(() {
          _routePoints = routeData['points'] as List<LatLng>;
          _alternativeRoutePoints = [];
          _routeDistance = routeData['distance'] as double;
          _routeDuration = routeData['duration'] as double;
          _phase = _Phase.movingToHospital;
          _animIndex = 0;
          _totalAnimationFrames = _calculateOptimalFrames(_routePoints);
        });

        _startAnimation();
        final distKm = (_routeDistance / 1000).toStringAsFixed(2);
        _toast.showInfoMessage('Transporting to hospital ($distKm km)');
      } catch (e) {
        _toast.showErrorMessage('Failed to find route to hospital: $e');
        await _release();
      }
    } else if (_phase == _Phase.movingToHospital) {
      await _release();
    }
  }

  Future<void> _cancelDispatch() async {
    HapticFeedback.lightImpact();
    _animTimer?.cancel();

    if (_dispatchedAmbulance != null) {
      final freed = _dispatchedAmbulance!.copyWith(available: true);
      await _fs.upsertAmbulance(freed);
    }

    setState(() {
      _dispatchedAmbulance = null;
      _routePoints = [];
      _alternativeRoutePoints = [];
      _ambulancePosition = null;
      _phase = _Phase.idle;
      _confirmingPin = false;
      _selectedPoint = null;
      _casualtyPoint = null;
    });

    _toast.showInfoMessage('Dispatch cancelled');
  }

  Future<void> _release() async {
    final amb = _dispatchedAmbulance;
    if (amb != null) {
      final freed = amb.copyWith(
        lat: _ambulancePosition?.latitude ?? amb.lat,
        lng: _ambulancePosition?.longitude ?? amb.lng,
        available: true,
        lockedFor: null,
      );
      await _fs.upsertAmbulance(freed);
    }

    setState(() {
      _dispatchedAmbulance = null;
      _routePoints = [];
      _alternativeRoutePoints = [];
      _ambulancePosition = null;
      _phase = _Phase.idle;
    });

    HapticFeedback.heavyImpact();
    _toast.showSuccessMessage('Casualty completed – ambulance back in service');
  }

  // ---------------------------------------------------------------------------
  // Geometry helpers
  // ---------------------------------------------------------------------------

  LatLng _centroid(List<LatLng> pts) {
    if (pts.isEmpty) {
      return LatLng(AppConfig.defaultLat, AppConfig.defaultLng);
    }
    double s = 0, t = 0;
    for (final p in pts) {
      s += p.latitude;
      t += p.longitude;
    }
    return LatLng(s / pts.length, t / pts.length);
  }

  LatLng? _interpolateAlongPath(List<LatLng> path, double t) {
    if (path.isEmpty) return null;
    if (path.length == 1) return path.first;

    double totalDistance = 0;
    final distances = <double>[0];

    for (int i = 0; i < path.length - 1; i++) {
      totalDistance += _calculateHaversineDistance(path[i], path[i + 1]);
      distances.add(totalDistance);
    }

    if (totalDistance == 0) return path.first;

    final target = totalDistance * t.clamp(0.0, 1.0);

    for (int i = 0; i < distances.length - 1; i++) {
      if (target >= distances[i] && target <= distances[i + 1]) {
        final segLen = distances[i + 1] - distances[i];
        final segProg = segLen > 0 ? (target - distances[i]) / segLen : 0.0;
        return LatLng(
          path[i].latitude +
              (path[i + 1].latitude - path[i].latitude) * segProg,
          path[i].longitude +
              (path[i + 1].longitude - path[i].longitude) * segProg,
        );
      }
    }

    return path.last;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          TacticalMap(
            controller: _mapCtrl,
            center: LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
            initialZoom: AppConfig.defaultZoom,
            roadLines: _osm == null
                ? []
                : _osm!.roads.map((f) => f.geometry).toList(),
            forestCentroids: _osm == null
                ? DemoData.seedForestCentroids()
                : _osm!.forests.map((f) => _centroid(f.geometry)).toList(),
            hospitals: _osm == null
                ? []
                : _osm!.hospitals.map((f) => _centroid(f.geometry)).toList(),
            wards: _osm == null
                ? []
                : _osm!.wards.map((f) => _centroid(f.geometry)).toList(),
            hazards: _hazards,
            ambulances: _ambulances.map((a) {
              if (_dispatchedAmbulance != null &&
                  a.id == _dispatchedAmbulance!.id &&
                  _ambulancePosition != null) {
                return a.copyWith(
                  lat: _ambulancePosition!.latitude,
                  lng: _ambulancePosition!.longitude,
                  available: false,
                );
              }
              return a;
            }).toList(growable: false),
            primaryRoute: _routePoints,
            secondaryRoute: _alternativeRoutePoints,
            showRoutes: _phase != _Phase.idle,
            showAmbulances: true,
            casualtyPoint:
            (!_confirmingPin && _casualtyPoint != null && _phase != _Phase.idle)
                ? _casualtyPoint
                : null,
            selectedPoint: _confirmingPin ? _selectedPoint : null,
            onTap: _confirmingPin ? _onMapTap : null,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Center(child: _buildBottomButtons()),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: Text(
        _confirmingPin ? 'Tap on map to place pin' : 'Casualty Response',
        style: GoogleFonts.quicksand(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textColor,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        color: AppColors.textColor,
        onPressed: () {
          if (_confirmingPin) {
            setState(() {
              _confirmingPin = false;
              _phase = _Phase.idle;
              _selectedPoint = null;
            });
          } else {
            Get.back();
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom buttons
  // ---------------------------------------------------------------------------

  Widget _buildBottomButtons() {
    final hasAvailable = _ambulances.any((a) => a.available);
    final user = _authCtrl.profile.value;

    // ── Confirming pin ────────────────────────────────────────────────────────
    if (_confirmingPin) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSmallButton(
            icon: Icons.close_rounded,
            label: 'Cancel',
            onTap: () => setState(() {
              _confirmingPin = false;
              _phase = _Phase.idle;
              _selectedPoint = null;
            }),
            isPrimary: false,
          ),
          const SizedBox(width: 12),
          _buildSmallButton(
            icon: Icons.check_circle_rounded,
            label: _selectedPoint == null ? 'Tap map first' : 'Confirm Location',
            onTap: _selectedPoint == null ? null : _onConfirm,
            isPrimary: _selectedPoint != null,
          ),
        ],
      );
    }

    // ── Active dispatch / movement ────────────────────────────────────────────
    if (_phase != _Phase.idle) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user != null && _phase != _Phase.dispatching)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    user.name ?? 'Patient',
                    style: GoogleFonts.quicksand(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          _buildSmallButton(
            icon: _getStatusIcon(),
            label: _getStatusText(),
            onTap: _phase == _Phase.dispatching ? _cancelDispatch : null,
            isPrimary: true,
          ),
        ],
      );
    }

    // ── Idle ──────────────────────────────────────────────────────────────────
    return _buildSmallButton(
      icon: Icons.emergency_rounded,
      label: hasAvailable ? 'Call Ambulance' : 'No Ambulances Available',
      onTap: hasAvailable ? _startConfirmFlow : null,
      isPrimary: hasAvailable,
    );
  }

  Widget _buildSmallButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required bool isPrimary,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.errorRed : Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: !isPrimary
                ? Border.all(color: Colors.grey.shade300, width: 1.2)
                : null,
            boxShadow: isPrimary && onTap != null
                ? [
              BoxShadow(
                color: AppColors.errorRed.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isPrimary ? Colors.white : Colors.grey.shade700,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.quicksand(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isPrimary ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Status helpers
  // ---------------------------------------------------------------------------

  String _getStatusText() {
    if (_routePoints.isEmpty) return 'Calculating route...';

    final progress = (_animIndex / _totalAnimationFrames).clamp(0.0, 1.0);
    final remaining = _routeDistance * (1 - progress);

    switch (_phase) {
      case _Phase.dispatching:
        return 'Dispatching ambulance...';
      case _Phase.movingToCasualty:
        if (remaining <= 10) return 'Arriving at casualty';
        if (remaining >= 1000) {
          return '${(remaining / 1000).toStringAsFixed(1)} km away';
        }
        return '${remaining.toStringAsFixed(0)} m away';
      case _Phase.movingToHospital:
        if (remaining <= 10) return 'Arriving at hospital';
        if (remaining >= 1000) {
          return '${(remaining / 1000).toStringAsFixed(1)} km to hospital';
        }
        return '${remaining.toStringAsFixed(0)} m to hospital';
      default:
        return 'In Progress';
    }
  }

  IconData _getStatusIcon() {
    switch (_phase) {
      case _Phase.dispatching:
        return Icons.schedule_rounded;
      case _Phase.movingToCasualty:
        return Icons.directions_car_rounded;
      case _Phase.movingToHospital:
        return Icons.local_hospital_rounded;
      default:
        return Icons.emergency_rounded;
    }
  }
}

// -----------------------------------------------------------------------------
// Phase enum
// -----------------------------------------------------------------------------

enum _Phase {
  idle,
  confirming,
  dispatching,
  movingToCasualty,
  movingToHospital,
}
