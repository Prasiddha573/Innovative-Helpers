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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final pos = await LocationService.getCurrentOrDefault();
    final osm = await OverpassService.loadKavrepalanchok();
    if (!mounted) return;
    setState(() {
      _osm = osm;
      _casualtyPoint = null; // Start with no casualty point
      _selectedPoint = null; // Start with no selected point
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

  /// Fetch shortest path from OSRM API
  Future<Map<String, dynamic>> _fetchOSRMRoute(LatLng from, LatLng to) async {
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};'
          '${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson&steps=true&alternatives=false';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final coords = route['geometry']['coordinates'] as List;
          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toDouble();

          List<LatLng> points = coords.map((c) => LatLng(c[1], c[0])).toList();

          return {
            'points': points,
            'distance': distance,
            'duration': duration,
          };
        }
      }
    } catch (e) {
      debugPrint('OSRM API failed: $e');
    }

    return {
      'points': [from, to],
      'distance': _calculateHaversineDistance(from, to),
      'duration': 0,
    };
  }

  double _calculateHaversineDistance(LatLng from, LatLng to) {
    const d = Distance();
    return d.as(LengthUnit.Meter, from, to);
  }

  double _calculatePathDistance(List<LatLng> path) {
    if (path.length < 2) return 0.0;

    double totalDistance = 0;
    for (int i = 0; i < path.length - 1; i++) {
      totalDistance += _calculateHaversineDistance(path[i], path[i + 1]);
    }
    return totalDistance;
  }

  Future<void> _startConfirmFlow() async {
    HapticFeedback.lightImpact();

    setState(() {
      _confirmingPin = true;
      _phase = _Phase.confirming;
      _selectedPoint = null; // Start with no pin
    });

    // Center map on default location
    _mapCtrl.move(LatLng(AppConfig.defaultLat, AppConfig.defaultLng), AppConfig.defaultZoom + 1);

    _toast.showInfoMessage('Tap on map to place casualty location');
  }

  void _onMapTap(LatLng point) {
    if (!_confirmingPin) return;

    HapticFeedback.selectionClick();
    setState(() {
      _selectedPoint = point; // Pin appears exactly where user tapped
    });
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

    final casualtyId = DemoData.newId();
    final casualty = CasualtyModel(
      id: casualtyId,
      lat: _casualtyPoint!.latitude,
      lng: _casualtyPoint!.longitude,
      reportedBy: _authCtrl.profile.value?.uid ?? 'unknown',
      createdAt: DateTime.now(),
    );
    await _fs.upsertCasualty(casualty);

    final amb = await _findNearestAmbulanceWithOSRM(_casualtyPoint!);
    if (amb == null) {
      _toast.showErrorMessage('No ambulance is currently available');
      setState(() => _phase = _Phase.idle);
      return;
    }

    final locked = amb.copyWith(available: false, lockedFor: casualtyId);
    await _fs.upsertAmbulance(locked);

    final routeData = await _fetchOSRMRoute(amb.latLng, _casualtyPoint!);

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

    final distanceKm = (_routeDistance / 1000).toStringAsFixed(2);
    final durationMin = (_routeDuration / 60).toStringAsFixed(0);
    _toast.showInfoMessage(
        'Ambulance dispatched from ${amb.stationName}\n'
            'Distance: $distanceKm km | ETA: $durationMin min'
    );
  }

  int _calculateOptimalFrames(List<LatLng> path) {
    final totalDistance = _calculatePathDistance(path);
    if (totalDistance == 0) return 60;

    final baseFrames = (totalDistance / 500) * 60;
    return baseFrames.clamp(30, 300).toInt();
  }

  Future<AmbulanceModel?> _findNearestAmbulanceWithOSRM(LatLng casualty) async {
    final available = _ambulances.where((a) => a.available).toList();
    if (available.isEmpty) return null;
    if (available.length == 1) return available.first;

    try {
      AmbulanceModel? nearestAmbulance;
      double shortestDistance = double.infinity;

      for (final ambulance in available) {
        try {
          final routeData = await _fetchOSRMRoute(ambulance.latLng, casualty);
          final distance = routeData['distance'] as double;

          if (distance < shortestDistance) {
            shortestDistance = distance;
            nearestAmbulance = ambulance;
          }
        } catch (e) {
          debugPrint('OSRM route failed for ambulance: $e');
          continue;
        }
      }

      return nearestAmbulance ?? _haversineNearest(available, casualty);
    } catch (e) {
      debugPrint('OSRM distance calculation failed, using haversine: $e');
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
            } catch (e) {
              // Ignore map movement errors
            }
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

      final routeData = await _fetchOSRMRoute(_casualtyPoint!, hosp);

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

      final distanceKm = (_routeDistance / 1000).toStringAsFixed(2);
      _toast.showInfoMessage('Transporting to hospital ($distanceKm km)');
    } else if (_phase == _Phase.movingToHospital) {
      await _release();
    }
  }

  Future<LatLng?> _findNearestHospitalWithOSRM(LatLng from) async {
    final hospitals = (_osm?.hospitals ?? [])
        .map((f) => _centroid(f.geometry))
        .toList();

    if (hospitals.isEmpty) return null;
    if (hospitals.length == 1) return hospitals.first;

    try {
      LatLng? nearestHospital;
      double shortestDistance = double.infinity;

      for (final hospital in hospitals) {
        try {
          final routeData = await _fetchOSRMRoute(from, hospital);
          final distance = routeData['distance'] as double;

          if (distance < shortestDistance) {
            shortestDistance = distance;
            nearestHospital = hospital;
          }
        } catch (e) {
          continue;
        }
      }

      return nearestHospital ?? _nearestHospitalHaversine(from);
    } catch (e) {
      debugPrint('OSRM hospital calculation failed: $e');
      return _nearestHospitalHaversine(from);
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
      _casualtyPoint = null; // Clear casualty point on cancel
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
    _toast.showSuccessMessage('Casualty completed - ambulance back in service');
  }

  LatLng? _nearestHospitalHaversine(LatLng from) {
    final pts = (_osm?.hospitals ?? [])
        .map((f) => _centroid(f.geometry))
        .toList();
    if (pts.isEmpty) return null;

    const d = Distance();
    pts.sort((a, b) => d
        .as(LengthUnit.Meter, a, from)
        .compareTo(d.as(LengthUnit.Meter, b, from)));
    return pts.first;
  }

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
      final segmentDistance = _calculateHaversineDistance(path[i], path[i + 1]);
      totalDistance += segmentDistance;
      distances.add(totalDistance);
    }

    if (totalDistance == 0) return path.first;

    final targetDistance = totalDistance * t.clamp(0.0, 1.0);

    for (int i = 0; i < distances.length - 1; i++) {
      if (targetDistance >= distances[i] && targetDistance <= distances[i + 1]) {
        final segmentLength = distances[i + 1] - distances[i];
        final segmentProgress = segmentLength > 0
            ? (targetDistance - distances[i]) / segmentLength
            : 0.0;

        return LatLng(
          path[i].latitude + (path[i + 1].latitude - path[i].latitude) * segmentProgress,
          path[i].longitude + (path[i + 1].longitude - path[i].longitude) * segmentProgress,
        );
      }
    }

    return path.last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Full screen map with all tactical features
          TacticalMap(
            controller: _mapCtrl,
            center: LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
            initialZoom: AppConfig.defaultZoom,
            roadLines: _osm == null
                ? []
                : _osm!.roads.map((f) => f.geometry).toList(),
            forestCentroids: _osm == null
                ? DemoData.seedForestCentroids()
                : _osm!.forests
                .map((f) => _centroid(f.geometry))
                .toList(),
            hospitals: _osm == null
                ? []
                : _osm!.hospitals
                .map((f) => _centroid(f.geometry))
                .toList(),
            wards: _osm == null
                ? []
                : _osm!.wards
                .map((f) => _centroid(f.geometry))
                .toList(),
            hazards: _hazards,
            ambulances: _ambulances
                .map((a) {
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
            })
                .toList(growable: false),
            primaryRoute: _routePoints,
            secondaryRoute: _alternativeRoutePoints,
            showRoutes: _phase != _Phase.idle,
            showAmbulances: true,
            casualtyPoint: (!_confirmingPin && _casualtyPoint != null && _phase != _Phase.idle)
                ? _casualtyPoint
                : null, // Only show casualty point after confirmation
            selectedPoint: _confirmingPin ? _selectedPoint : null, // Only show selected point during confirmation
            onTap: _confirmingPin ? _onMapTap : null,
          ),

          // Bottom buttons
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Center(
              child: _buildBottomButtons(),
            ),
          ),
        ],
      ),
    );
  }

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
        color: AppColors.textColor,
      ),
    );
  }

  Widget _buildBottomButtons() {
    final hasAvailableAmbulances = _ambulances.any((a) => a.available);
    final user = _authCtrl.profile.value;

    if (_confirmingPin) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildSmallButton(
            icon: Icons.close_rounded,
            label: 'Cancel',
            onTap: () {
              setState(() {
                _confirmingPin = false;
                _phase = _Phase.idle;
                _selectedPoint = null;
              });
            },
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

    if (_phase != _Phase.idle) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user != null && _phase != _Phase.dispatching)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

    return _buildSmallButton(
      icon: Icons.emergency_rounded,
      label: hasAvailableAmbulances ? 'Call Ambulance' : 'No Ambulances Available',
      onTap: hasAvailableAmbulances ? _startConfirmFlow : null,
      isPrimary: hasAvailableAmbulances,
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
            border: !isPrimary ? Border.all(color: Colors.grey.shade300, width: 1.2) : null,
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

  String _getStatusText() {
    if (_routePoints.isEmpty) return 'Calculating route...';

    final progress = (_animIndex / _totalAnimationFrames).clamp(0.0, 1.0);
    final remainingDistance = _routeDistance * (1 - progress);

    switch (_phase) {
      case _Phase.dispatching:
        return 'Dispatching ambulance...';
      case _Phase.movingToCasualty:
        if (remainingDistance <= 10) return 'Arriving at casualty';
        if (remainingDistance >= 1000) {
          return '${(remainingDistance / 1000).toStringAsFixed(1)} km away';
        }
        return '${remainingDistance.toStringAsFixed(0)}m away';
      case _Phase.movingToHospital:
        if (remainingDistance <= 10) return 'Arriving at hospital';
        if (remainingDistance >= 1000) {
          return '${(remainingDistance / 1000).toStringAsFixed(1)} km to hospital';
        }
        return '${remainingDistance.toStringAsFixed(0)}m to hospital';
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

enum _Phase {
  idle,
  confirming,
  dispatching,
  movingToCasualty,
  movingToHospital,
}