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
    final screenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Full-screen map
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

          // Casualty pin overlay
          if (_casualtyPoint != null && _confirmingPin)
            IgnorePointer(
              child: Center(
                child: _buildCasualtyPin(),
              ),
            ),

          // Left side - In Progress card
          if (_phase != _Phase.idle || _dispatchedAmbulance != null)
            Positioned(
              left: 16,
              top: 100,
              child: _buildLeftCard(),
            ),

          // Right side - Confirm Location card
          if (_confirmingPin)
            Positioned(
              right: 16,
              top: 100,
              child: _buildRightCard(),
            ),

          // Bottom - Action buttons
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0),
                    Colors.black.withOpacity(0.9),
                  ],
                ),
              ),
              child: _buildButtonsRow(),
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
      title: Text(
        'Casualty Response',
        style: GoogleFonts.quicksand(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textColor,
        ),
      ),
      centerTitle: false,
    );
  }

  Widget _buildCasualtyPin() {
    return AnimatedScale(
      scale: _confirmingPin ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on,
            size: 56,
            color: AppColors.errorRed,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 8,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Tap to reposition',
              style: GoogleFonts.quicksand(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftCard() {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.local_hospital_rounded,
                  color: AppColors.errorRed,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'In Progress',
                style: GoogleFonts.quicksand(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_dispatchedAmbulance != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.local_hospital_rounded,
                        color: AppColors.errorRed,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _dispatchedAmbulance!.stationName,
                          style: GoogleFonts.quicksand(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildProgressIndicator(),
                ],
              ),
            ),
          ],
          if (_phase == _Phase.dispatching) ...[
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Finding ambulance',
                  style: GoogleFonts.quicksand(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    double progress = 0;
    String label = '';

    if (_activeRoute.primary.isNotEmpty) {
      progress = (_animIndex / 30).clamp(0.0, 1.0);
      if (_phase == _Phase.movingToCasualty) {
        label = 'To Casualty: ${(progress * 100).toStringAsFixed(0)}%';
      } else if (_phase == _Phase.movingToHospital) {
        label = 'To Hospital: ${(progress * 100).toStringAsFixed(0)}%';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Text(
            label,
            style: GoogleFonts.quicksand(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade400,
            ),
          ),
        if (label.isNotEmpty) const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: Colors.grey.shade700,
            valueColor: AlwaysStoppedAnimation<Color>(
              _phase == _Phase.movingToHospital
                  ? AppColors.primaryPurple
                  : AppColors.errorRed,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightCard() {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.location_on,
                  color: AppColors.primaryBlue,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Confirm Location',
                style: GoogleFonts.quicksand(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tap map to adjust',
            style: GoogleFonts.quicksand(
              fontSize: 9,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 10),
          if (_casualtyPoint != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location:',
                    style: GoogleFonts.quicksand(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_casualtyPoint!.latitude.toStringAsFixed(4)}\n${_casualtyPoint!.longitude.toStringAsFixed(4)}',
                    style: GoogleFonts.quicksand(
                      fontSize: 8,
                      color: Colors.grey.shade300,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildButtonsRow() {
    final isDisabled = _phase != _Phase.idle;

    if (_confirmingPin) {
      // Confirmation buttons
      return Row(
        children: [
          Expanded(
            child: _buildButton(
              label: 'Cancel',
              onPressed: () => setState(() => _confirmingPin = false),
              isPrimary: false,
              icon: Icons.close_rounded,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildButton(
              label: 'Confirm',
              onPressed: _onConfirm,
              isPrimary: true,
              icon: Icons.check_circle_rounded,
              color: Color(0xFF4CAF50),
            ),
          ),
        ],
      );
    } else if (isDisabled) {
      // Dispatch in progress button - centered
      return Center(
        child: SizedBox(
          width: 280,
          child: _buildButton(
            label: 'Dispatch in Progress',
            onPressed: null,
            isPrimary: true,
            icon: Icons.schedule_rounded,
            color: Color(0xFF2196F3),
          ),
        ),
      );
    } else {
      // Call ambulance button - centered
      return Center(
        child: SizedBox(
          width: 280,
          child: _buildButton(
            label: 'Call Ambulance',
            onPressed: _startConfirmFlow,
            isPrimary: true,
            icon: Icons.emergency,
            color: AppColors.errorRed,
          ),
        ),
      );
    }
  }

  Widget _buildButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: isPrimary && onPressed != null
            ? LinearGradient(
          colors: [
            color,
            color.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
            : null,
        color: isPrimary && onPressed == null
            ? color.withOpacity(0.4)
            : !isPrimary
            ? Colors.white.withOpacity(0.08)
            : null,
        border: !isPrimary
            ? Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1.5,
        )
            : null,
        boxShadow: isPrimary && onPressed != null
            ? [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isPrimary
                    ? Colors.white
                    : Colors.white.withOpacity(0.6),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isPrimary
                      ? Colors.white
                      : Colors.white.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
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