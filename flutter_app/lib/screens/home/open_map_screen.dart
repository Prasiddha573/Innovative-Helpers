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
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.red.withOpacity(0.15),
                          Colors.red.withOpacity(0.05),
                        ],
                      ),
                    ),
                  ),
                  Text(h.type.emoji,
                      style: const TextStyle(fontSize: 45)),
                  Positioned(
                    right: -5,
                    top: 20,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFEF5350), Color(0xFFE53935)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.remove,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Remove ${h.type.label}?',
                style: GoogleFonts.quicksand(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: AppColors.textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Only your own hazard reports can be removed.',
                textAlign: TextAlign.center,
                style: GoogleFonts.quicksand(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(result: false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.quicksand(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: AppColors.errorRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Get.back(result: true),
                      child: Text(
                        'Remove',
                        style: GoogleFonts.quicksand(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
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
    final screen = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Map Card with iOS style
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildMapCard(),
              ),
            ),
            // Bottom Legend Card
            _buildLegendCard(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: Colors.black),
      title: Text(
        'Live Map',
        style: GoogleFonts.quicksand(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textColor,
        ),
      ),
    );
  }

  Widget _buildMapCard() {
    final osm = widget.osm;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: TacticalMap(
          center: LatLng(AppConfig.defaultLat, AppConfig.defaultLng),
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
      ),
    );
  }

  Widget _buildLegendCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Map Legend',
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 1: 3 items (Hospital, Ward, Forest)
          Row(
            children: [
              Expanded(child: _buildLegendItem('🏥', 'Hospital')),
              const SizedBox(width: 6),
              Expanded(child: _buildLegendItem('🏛️', 'Ward')),
              const SizedBox(width: 6),
              Expanded(child: _buildLegendItem('🌲', 'Forest')),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: 3 items (Fire, Flood, Danger)
          Row(
            children: [
              Expanded(child: _buildLegendItem('🔥', 'Fire')),
              const SizedBox(width: 6),
              Expanded(child: _buildLegendItem('🌊', 'Flood')),
              const SizedBox(width: 6),
              Expanded(child: _buildLegendItem('🚧', 'Danger')),
            ],
          ),
          const SizedBox(height: 6),
          // Row 3: 2 items (Landslide and Ambulance) covering full width
          Row(
            children: [
              Expanded(
                flex: 1,
                child: _buildLegendItem('⛰️', 'Landslide'),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 1,
                child: _buildLegendItem('🚑', 'Ambulance'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String emoji, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.quicksand(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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