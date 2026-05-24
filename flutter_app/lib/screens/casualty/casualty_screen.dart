import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  LatLng? _draggablePinPosition;
  bool _isDragging = false;
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
      _draggablePinPosition = pos;
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

  Future<void> _startConfirmFlow() async {
    HapticFeedback.lightImpact();
    setState(() {
      _confirmingPin = true;
      _phase = _Phase.confirming;
      _draggablePinPosition = _casualtyPoint;
    });
    _toast.showInfoMessage('Drag the pin to set casualty location');
  }

  Future<void> _onConfirm() async {
    if (_draggablePinPosition == null) return;
    HapticFeedback.mediumImpact();

    setState(() {
      _casualtyPoint = _draggablePinPosition;
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

    final amb = await _pickNearestAmbulance(_casualtyPoint!);
    if (amb == null) {
      _toast.showErrorMessage('No ambulance is currently available');
      setState(() => _phase = _Phase.idle);
      return;
    }

    final locked = amb.copyWith(available: false, lockedFor: casualtyId);
    await _fs.upsertAmbulance(locked);

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
    _toast.showInfoMessage('Ambulance dispatched from ${amb.stationName}');
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
    HapticFeedback.heavyImpact();
    if (_phase == _Phase.movingToCasualty) {
      final hosp = _nearestHospital(_casualtyPoint!);
      if (hosp == null) {
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

  Future<void> _cancelDispatch() async {
    HapticFeedback.lightImpact();
    _animTimer?.cancel();
    if (_dispatchedAmbulance != null) {
      final freed = _dispatchedAmbulance!.copyWith(available: true);
      await _fs.upsertAmbulance(freed);
    }
    setState(() {
      _dispatchedAmbulance = null;
      _activeRoute = RouteModel.empty();
      _ambulancePosition = null;
      _phase = _Phase.idle;
      _confirmingPin = false;
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
      _activeRoute = RouteModel.empty();
      _ambulancePosition = null;
      _phase = _Phase.idle;
    });
    HapticFeedback.heavyImpact();
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Full screen map
          _buildFullScreenMap(),

          // Draggable pin overlay
          if (_confirmingPin && _draggablePinPosition != null)
            _buildDraggablePin(),

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
        'Casualty Response',
        style: GoogleFonts.quicksand(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textColor,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Get.back(),
        color: AppColors.textColor,
      ),
    );
  }

  Widget _buildFullScreenMap() {
    return TacticalMap(
      controller: _mapCtrl,
      center: _casualtyPoint ?? LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
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
      onTap: null,
    );
  }

  Widget _buildDraggablePin() {
    return Positioned.fill(
      child: GestureDetector(
        onPanUpdate: (details) {
          final screenSize = MediaQuery.of(context).size;
          final latSpan = 0.01;
          final lngSpan = 0.01 * (screenSize.width / screenSize.height);

          final latDelta = -(details.delta.dy / screenSize.height) * latSpan;
          final lngDelta = (details.delta.dx / screenSize.width) * lngSpan;

          final newLat = (_draggablePinPosition!.latitude + latDelta)
              .clamp(-90.0, 90.0);
          final newLng = (_draggablePinPosition!.longitude + lngDelta)
              .clamp(-180.0, 180.0);

          setState(() {
            _draggablePinPosition = LatLng(newLat, newLng);
            _isDragging = true;
          });
        },
        onPanEnd: (details) {
          setState(() {
            _isDragging = false;
          });
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _isDragging ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 32,
                    color: Colors.blue,
                  ),
                ),
              ),
              if (_isDragging)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Release to drop pin',
                    style: GoogleFonts.quicksand(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons() {
    final hasAvailableAmbulances = _ambulances.any((a) => a.available);

    // When confirming pin location - show Cancel and Confirm buttons
    if (_confirmingPin) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildSmallButton(
            icon: Icons.close_rounded,
            label: 'Cancel',
            onTap: () => setState(() => _confirmingPin = false),
            isPrimary: false,
          ),
          const SizedBox(width: 10),
          _buildSmallButton(
            icon: Icons.check_circle_rounded,
            label: 'Confirm',
            onTap: _onConfirm,
            isPrimary: true,
          ),
        ],
      );
    }

    // When dispatch is in progress
    if (_phase != _Phase.idle) {
      return _buildSmallButton(
        icon: _getStatusIcon(),
        label: _getStatusText(),
        onTap: _phase == _Phase.dispatching ? _cancelDispatch : null,
        isPrimary: true,
      );
    }

    // Default state - ready to call ambulance
    return _buildSmallButton(
      icon: Icons.emergency_rounded,
      label: hasAvailableAmbulances ? 'Call Ambulance' : 'No Ambulances',
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
                size: 16,
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
    double progress = (_animIndex / 30).clamp(0.0, 1.0);
    switch (_phase) {
      case _Phase.dispatching:
        return 'Dispatching...';
      case _Phase.movingToCasualty:
        final eta = ((1 - progress) * 30).toInt();
        return eta > 0 ? 'ETA: ${eta}s' : 'Arriving';
      case _Phase.movingToHospital:
        final eta = ((1 - progress) * 30).toInt();
        return eta > 0 ? 'ETA: ${eta}s' : 'Arriving';
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

  Color _getStatusColor() {
    switch (_phase) {
      case _Phase.dispatching:
        return AppColors.primaryBlue;
      case _Phase.movingToCasualty:
        return AppColors.errorRed;
      case _Phase.movingToHospital:
        return AppColors.primaryPurple;
      default:
        return Colors.grey;
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