import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_config.dart';
import '../../models/hazard_model.dart';
import '../../services/firestore_service.dart';
import '../../services/overpass_service.dart';
import '../../services/toast_service.dart';
import '../../themes/colors.dart';
import '../../widgets/map_widget.dart';

/// Full-screen live map (blueprint §7). Same scope as Home - emergency
/// route overlays are explicitly hidden here; only background layers,
/// hazard markers, water/fire emoji and red risk dots are visible.
class OpenMapScreen extends StatefulWidget {
  final OverpassResult? osm;
  final List<HazardModel> hazards;

  const OpenMapScreen({
    super.key,
    required this.osm,
    required this.hazards,
  });

  @override
  State<OpenMapScreen> createState() => _OpenMapScreenState();
}

class _OpenMapScreenState extends State<OpenMapScreen> {
  final _fs = FirestoreService();
  final _toast = ToastService();

  Future<void> _confirmRemoval(HazardModel h) async {
    final ok = await Get.dialog<bool>(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity(0.1),
                    ),
                  ),
                  Text(h.type.emoji,
                      style: const TextStyle(fontSize: 40)),
                  Positioned(
                    left: -2,
                    top: 24,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                      child: const Icon(
                        Icons.remove,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Remove ${h.type.label}?',
                style: GoogleFonts.quicksand(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Only your own hazard reports can be removed.',
                textAlign: TextAlign.center,
                style: GoogleFonts.quicksand(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(result: false),
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
                      onPressed: () => Get.back(result: true),
                      child: const Text('Remove'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierColor: Colors.black.withOpacity(0.55),
    );
    if (ok == true) {
      // Demo persistent hazards cannot be deleted from Firestore (they are
      // local seeds). Live user reports flow through Firestore normally.
      if (h.id.startsWith('demo-')) {
        _toast.showInfoMessage('Demo hazard cannot be removed');
        return;
      }
      await _fs.removeHazard(h.id);
      _toast.showSuccessMessage('${h.type.label} removed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final osm = widget.osm;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'Live Map',
          style: GoogleFonts.quicksand(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textColor,
          ),
        ),
      ),
      body: TacticalMap(
        center:
            LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
        roadLines: osm == null
            ? const []
            : osm.roads.map((f) => f.geometry).toList(),
        forestCentroids: osm == null
            ? const []
            : osm.forests.map((f) => _centroid(f.geometry)).toList(),
        hospitals: osm == null
            ? const []
            : osm.hospitals.map((f) => _centroid(f.geometry)).toList(),
        wards: osm == null
            ? const []
            : osm.wards.map((f) => _centroid(f.geometry)).toList(),
        hazards: widget.hazards,
        // Blueprint §7: emergency overlays hidden in the default map view.
        showRoutes: false,
        showAmbulances: false,
        onHazardTap: _confirmRemoval,
      ),
    );
  }

  LatLng _centroid(List<LatLng> pts) {
    if (pts.isEmpty) {
      return LatLng(AppConfig.defaultLat, AppConfig.defaultLng);
    }
    double sumLat = 0, sumLng = 0;
    for (final p in pts) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / pts.length, sumLng / pts.length);
  }
}
