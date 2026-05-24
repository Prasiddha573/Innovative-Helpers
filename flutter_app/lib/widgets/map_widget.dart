import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/ambulance_model.dart';
import '../models/hazard_model.dart';
import '../themes/colors.dart';

/// Shared OSM/flutter_map widget. Renders:
///   - OpenStreetMap raster tiles
///   - forest centroids (🌲 emojis - swap to fire/water when overlapped)
///   - hospital markers
///   - ward markers
///   - hazards (flood/fire/landslide/danger zone)
///   - ambulances (when [showAmbulances] is true)
///   - casualty point (when provided)
///   - emergency route overlays (golden primary + sky-blue secondary)
class TacticalMap extends StatelessWidget {
  final MapController? controller;
  final LatLng center;
  final double initialZoom;
  final List<List<LatLng>> roadLines;
  final List<LatLng> forestCentroids;
  final List<LatLng> hospitals;
  final List<LatLng> wards;
  final List<HazardModel> hazards;
  final List<AmbulanceModel> ambulances;
  final List<LatLng> primaryRoute;
  final List<LatLng> secondaryRoute;
  final void Function(LatLng latLng)? onTap;
  final bool showAmbulances;
  final bool showRoutes;
  final void Function(HazardModel)? onHazardTap;
  final LatLng? casualtyPoint;
  final LatLng? selectedPoint;

  const TacticalMap({
    super.key,
    this.controller,
    required this.center,
    this.initialZoom = AppConfig.defaultZoom,
    this.roadLines = const [],
    this.forestCentroids = const [],
    this.hospitals = const [],
    this.wards = const [],
    this.hazards = const [],
    this.ambulances = const [],
    this.primaryRoute = const [],
    this.secondaryRoute = const [],
    this.onTap,
    this.showAmbulances = false,
    this.showRoutes = false,
    this.onHazardTap,
    this.casualtyPoint,
    this.selectedPoint,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: initialZoom,
        minZoom: 6,
        maxZoom: 19,
        onTap: onTap == null ? null : (tapPos, point) {
          onTap!(point);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.tactical_disaster_simulation',
          maxZoom: 19,
        ),
        if (roadLines.isNotEmpty)
          PolylineLayer(
            polylines: roadLines
                .map((pts) => Polyline(
              points: pts,
              color: Colors.grey.shade400,
              strokeWidth: 1.5,
            ))
                .toList(),
          ),
        if (showRoutes && secondaryRoute.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: secondaryRoute,
                color: AppColors.skyBlueRoute,
                strokeWidth: 4.0,
              ),
            ],
          ),
        if (showRoutes && primaryRoute.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: primaryRoute,
                color: AppColors.goldenRoute,
                strokeWidth: 5.0,
                pattern: const StrokePattern.dotted(),
              ),
            ],
          ),
        MarkerLayer(markers: _buildMarkers()),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Forests - render as tree emoji unless overlapped by fire/flood hazard.
    for (final f in forestCentroids) {
      final overlap = _nearbyHazard(f);
      String emoji = '🌲';
      if (overlap == HazardType.forestFire) emoji = '🔥';
      if (overlap == HazardType.flood) emoji = '🌊';
      markers.add(_emojiMarker(f, emoji, 26));
    }

    // Hospitals
    for (final h in hospitals) {
      markers.add(_emojiMarker(h, '🏥', 28));
    }

    // Wards
    for (final w in wards) {
      markers.add(_emojiMarker(w, '🏛️', 22));
    }

    // Selected Point (during confirmation - shows at tapped location)
    if (selectedPoint != null) {
      markers.add(Marker(
        point: selectedPoint!,
        width: 40,
        height: 40,
        child: const Icon(
          Icons.place_rounded,
          color: Colors.red,
          size: 36,
        ),
      ));
    }

    // Casualty Point (after confirmation) - simple red pin only
    if (casualtyPoint != null && selectedPoint == null) {
      markers.add(Marker(
        point: casualtyPoint!,
        width: 40,
        height: 40,
        child: const Icon(
          Icons.place_rounded,
          color: Colors.red,
          size: 36,
        ),
      ));
    }

    // Hazards
    for (final hz in hazards) {
      markers.add(Marker(
        point: hz.latLng,
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: onHazardTap == null ? null : () => onHazardTap!(hz),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
              ),
              Text(hz.type.emoji, style: const TextStyle(fontSize: 22)),
            ],
          ),
        ),
      ));
    }

    // Ambulances
    if (showAmbulances) {
      for (final a in ambulances) {
        markers.add(Marker(
          point: a.latLng,
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: a.available ? Colors.white : Colors.amber,
                  border: Border.all(
                    color: a.available ? Colors.red : Colors.deepOrange,
                    width: 2,
                  ),
                ),
              ),
              const Text('🚑', style: TextStyle(fontSize: 18)),
            ],
          ),
        ));
      }
    }

    return markers;
  }

  HazardType? _nearbyHazard(LatLng point) {
    const distance = Distance();
    for (final h in hazards) {
      if (distance.as(LengthUnit.Meter, point, h.latLng) < 700) {
        return h.type;
      }
    }
    return null;
  }

  Marker _emojiMarker(LatLng p, String emoji, double size) => Marker(
    point: p,
    width: size + 6,
    height: size + 6,
    child: Center(child: Text(emoji, style: TextStyle(fontSize: size))),
  );
}