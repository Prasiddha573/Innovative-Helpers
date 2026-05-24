import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../models/ambulance_model.dart';
import '../../models/casualty_model.dart';
import '../../models/hazard_model.dart';
import '../../models/route_model.dart';
import '../../services/demo_data_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/overpass_service.dart';
import '../../services/routing_service.dart';
import '../../services/toast_service.dart';
import '../../themes/colors.dart';
import '../../widgets/map_widget.dart';

/// Casualty screen per blueprint §9 & §10.
///   - map takes 75% of height
///   - call ambulance flow: confirm pin → find nearest available ambulance
///   - lock ambulance, animate along route, then go to nearest hospital
///   - shows the dual-path overlay (golden + sky-blue) while dispatched
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

  // Dispatch state
  bool _confirmingPin = false;
  LatLng? _casualtyPoint;
  AmbulanceModel? _dispatchedAmbulance;
  LatLng? _ambulancePosition;
  RouteModel _activeRoute = RouteModel.empty();
  Timer? _animTimer;
  int _animIndex = 0;
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
      _casualtyPoint = pos;
    });
    _fs.watchAmbulances().listen((list) {
      if (!mounted) return;
      // Merge with seeded demo ambulances if Firestore is empty.
      final list2 = list.isEmpty ? DemoData.seedAmbulances() : list;
      setState(() => _ambulances = list2);
    });
    _fs.watchHazards().listen((list) {
      if (!mounted) return;
      setState(() => _hazards = list);
    });
    // Push seeds if not already there.
    for (final a in DemoData.seedAmbulances()) {
      _fs.upsertAmbulance(a);
    }
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  Future<void> _startConfirmFlow() async {
    setState(() {
      _confirmingPin = true;
      _phase = _Phase.confirming;
    });
    _toast.showInfoMessage('Drag the pin to the exact casualty location');
  }

  Future<void> _onConfirm() async {
    if (_casualtyPoint == null) return;
    setState(() {
      _confirmingPin = false;
      _phase = _Phase.dispatching;
    });

    // 1. Persist the casualty.
    final casualtyId = DemoData.newId();
    final casualty = CasualtyModel(
      id: casualtyId,
      lat: _casualtyPoint!.latitude,
      lng: _casualtyPoint!.longitude,
      reportedBy: _authCtrl.profile.value?.uid ?? 'unknown',
      createdAt: DateTime.now(),
    );
    await _fs.upsertCasualty(casualty);

    // 2. Pick the nearest *available* ambulance. Try Python backend; if it
    //    fails fall back to Haversine.
    final amb = await _pickNearestAmbulance(_casualtyPoint!);
    if (amb == null) {
      _toast.showErrorMessage('No ambulance is currently available');
      setState(() => _phase = _Phase.idle);
      return;
    }

    // 3. Lock the ambulance.
    final locked = amb.copyWith(available: false, lockedFor: casualtyId);
    await _fs.upsertAmbulance(locked);

    // 4. Ask the Python backend for the dual paths.
    final route = await RoutingService.findRoute(
      from: amb.latLng,
      to: _casualtyPoint!,
      hazards: _hazards
          .map((h) => {
                'lat': h.lat,
                'lng': h.lng,
                'type': h.type.firestoreKey,
              })
          .toList(),
    );

    setState(() {
      _dispatchedAmbulance = locked;
      _ambulancePosition = amb.latLng;
      _activeRoute = route;
      _phase = _Phase.movingToCasualty;
      _animIndex = 0;
    });
    _startAnimation();
    _toast.showInfoMessage(
        'Ambulance dispatched from ${amb.stationName}');
  }

  Future<AmbulanceModel?> _pickNearestAmbulance(LatLng casualty) async {
    final available = _ambulances.where((a) => a.available).toList();
    if (available.isEmpty) return null;
    final payload = available
        .map((a) => {
              'id': a.id,
              'lat': a.lat,
              'lng': a.lng,
            })
        .toList();
    final result = await RoutingService.findNearestAmbulance(
      casualty: casualty,
      ambulances: payload,
    );
    if (result != null && result['ambulance_id'] != null) {
      final id = result['ambulance_id'] as String;
      return available.firstWhere((a) => a.id == id,
          orElse: () => _haversineNearest(available, casualty));
    }
    return _haversineNearest(available, casualty);
  }

  AmbulanceModel _haversineNearest(
      List<AmbulanceModel> list, LatLng to) {
    const d = Distance();
    list.sort((a, b) => d
        .as(LengthUnit.Meter, a.latLng, to)
        .compareTo(d.as(LengthUnit.Meter, b.latLng, to)));
    return list.first;
  }

  void _startAnimation() {
    _animTimer?.cancel();
    final fps = AppConfig.ambulanceFps;
    _animTimer =
        Timer.periodic(Duration(milliseconds: 1000 ~/ fps), (timer) {
      if (!mounted) return;
      final path = _activeRoute.primary;
      if (path.length < 2) {
        timer.cancel();
        return;
      }
      // Move forward along the primary route. We move ~3% of total path per
      // step so a typical demo finishes within ~5 s.
      _animIndex++;
      final t = (_animIndex / 30).clamp(0.0, 1.0);
      final pos = _interpolate(path, t);
      setState(() => _ambulancePosition = pos);
      if (t >= 1.0) {
        timer.cancel();
        _onArrived();
      }
    });
  }

  Future<void> _onArrived() async {
    if (_phase == _Phase.movingToCasualty) {
      // Compute path from casualty → nearest hospital.
      final hosp = _nearestHospital(_casualtyPoint!);
      if (hosp == null) {
        // No hospital data → release ambulance and complete.
        await _release();
        return;
      }
      final route2 = await RoutingService.findRoute(
        from: _casualtyPoint!,
        to: hosp,
        hazards: _hazards
            .map((h) => {
                  'lat': h.lat,
                  'lng': h.lng,
                  'type': h.type.firestoreKey,
                })
            .toList(),
      );
      setState(() {
        _activeRoute = route2;
        _phase = _Phase.movingToHospital;
        _animIndex = 0;
      });
      _startAnimation();
      _toast.showInfoMessage('Transporting to nearest hospital');
    } else if (_phase == _Phase.movingToHospital) {
      await _release();
    }
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
      _activeRoute = RouteModel.empty();
      _ambulancePosition = null;
      _phase = _Phase.idle;
    });
    _toast.showSuccessMessage('Casualty completed - ambulance back in service');
  }

  LatLng? _nearestHospital(LatLng from) {
    final pts = (_osm?.hospitals ?? const [])
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

  LatLng _interpolate(List<LatLng> path, double t) {
    if (path.length < 2) return path.first;
    // Compute cumulative segment lengths in metres.
    const d = Distance();
    final lengths = <double>[];
    double total = 0;
    for (int i = 0; i < path.length - 1; i++) {
      final l = d.as(LengthUnit.Meter, path[i], path[i + 1]);
      lengths.add(l);
      total += l;
    }
    final target = total * t;
    double acc = 0;
    for (int i = 0; i < lengths.length; i++) {
      if (acc + lengths[i] >= target) {
        final frac = (target - acc) / lengths[i];
        final a = path[i];
        final b = path[i + 1];
        return LatLng(a.latitude + (b.latitude - a.latitude) * frac,
            a.longitude + (b.longitude - a.longitude) * frac);
      }
      acc += lengths[i];
    }
    return path.last;
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final mapHeight = h * 0.75;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Casualty Response',
          style: GoogleFonts.quicksand(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textColor,
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: mapHeight,
            child: Stack(
              children: [
                TacticalMap(
                  controller: _mapCtrl,
                  center: _casualtyPoint ??
                      LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
                  initialZoom: AppConfig.defaultZoom,
                  roadLines: _osm == null
                      ? const []
                      : _osm!.roads.map((f) => f.geometry).toList(),
                  forestCentroids: _osm == null
                      ? DemoData.seedForestCentroids()
                      : _osm!.forests
                          .map((f) => _centroid(f.geometry))
                          .toList(),
                  hospitals: _osm == null
                      ? const []
                      : _osm!.hospitals
                          .map((f) => _centroid(f.geometry))
                          .toList(),
                  wards: _osm == null
                      ? const []
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
                  primaryRoute: _activeRoute.primary,
                  secondaryRoute: _activeRoute.secondary,
                  showRoutes: _phase != _Phase.idle,
                  showAmbulances: true,
                  onTap: _confirmingPin
                      ? (p) => setState(() => _casualtyPoint = p)
                      : null,
                ),
                // Casualty pin overlay (centered when confirming)
                if (_casualtyPoint != null)
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Icon(
                          Icons.location_on,
                          size: _confirmingPin ? 56 : 0,
                          color: AppColors.errorRed,
                        ),
                      ),
                    ),
                  ),
                if (_confirmingPin)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _confirmCard(),
                  ),
              ],
            ),
          ),
          Expanded(child: _bottomPanel()),
        ],
      ),
    );
  }

  Widget _confirmCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              'Confirm Casualty Location',
              style: GoogleFonts.quicksand(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the map to refine, then confirm.',
              style: GoogleFonts.quicksand(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _confirmingPin = false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.errorRed,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _onConfirm,
                    child: const Text('Confirm & Dispatch'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _bottomPanel() => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        color: Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _phaseBanner(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _phase == _Phase.idle ? _startConfirmFlow : null,
                icon: const Icon(Icons.local_hospital_rounded),
                label: Text(
                  _phase == _Phase.idle
                      ? 'Call an Ambulance'
                      : 'Dispatch in progress',
                  style: GoogleFonts.quicksand(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.errorRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _phaseBanner() {
    String label;
    Color color;
    switch (_phase) {
      case _Phase.idle:
        label = 'No active casualty';
        color = Colors.grey.shade700;
        break;
      case _Phase.confirming:
        label = 'Awaiting location confirmation';
        color = AppColors.warningOrange;
        break;
      case _Phase.dispatching:
        label = 'Calculating shortest route…';
        color = AppColors.primaryBlue;
        break;
      case _Phase.movingToCasualty:
        label = 'Ambulance en-route to casualty';
        color = AppColors.errorRed;
        break;
      case _Phase.movingToHospital:
        label = 'Transporting casualty to hospital';
        color = AppColors.primaryPurple;
        break;
    }
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.quicksand(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Phase {
  idle,
  confirming,
  dispatching,
  movingToCasualty,
  movingToHospital,
}
