import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../models/ambulance_model.dart';
import '../../models/hazard_model.dart';
import '../../services/demo_data_service.dart';
import '../../services/firestore_service.dart';
import '../../services/overpass_service.dart';
import '../../services/toast_service.dart';
import '../../themes/colors.dart';
import '../../widgets/map_widget.dart';
import '../casualty/casualty_screen.dart';
import 'open_map_screen.dart';
import 'report_dialog.dart';

/// Home screen per blueprint section 7 / 8:
///   - compact map card (~20% h, ~90% w)
///   - "Open map" button below the card (live map in same screen scope)
///   - Report button (adds a hazard)
///   - separate Casualty shortcut
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _fs = FirestoreService();
  final _toast = ToastService();
  final _authCtrl = Get.find<AuthController>();

  OverpassResult? _osm;
  List<HazardModel> _hazards = [];
  List<AmbulanceModel> _ambulances = [];
  final List<HazardModel> _demoHazards = [];
  bool _loadingOsm = true;

  @override
  void initState() {
    super.initState();
    _loadOsm();
    _bindStreams();
    _seedDemoIfEmpty();
  }

  Future<void> _loadOsm() async {
    final r = await OverpassService.loadKavrepalanchok();
    if (!mounted) return;
    setState(() {
      _osm = r;
      _loadingOsm = false;
    });
  }

  void _bindStreams() {
    _fs.watchHazards().listen((list) {
      if (!mounted) return;
      setState(() => _hazards = list);
    });
    _fs.watchAmbulances().listen((list) {
      if (!mounted) return;
      setState(() => _ambulances = list);
    });
  }

  Future<void> _seedDemoIfEmpty() async {
    // Always available in-memory demo hazards / ambulances - blueprint section 8.
    final demoUid = _authCtrl.profile.value?.uid ?? 'demo-user';
    _demoHazards
      ..clear()
      ..addAll(DemoData.seedHazards(demoUid));
    // Push ambulances to Firestore so casualty workflow has data.
    for (final a in DemoData.seedAmbulances()) {
      _fs.upsertAmbulance(a);
    }
  }

  List<HazardModel> get _allHazards => [..._demoHazards, ..._hazards];

  Future<void> _openReportDialog() async {
    final user = _authCtrl.profile.value;
    if (user == null) {
      _toast.showErrorMessage('Sign in required to report a hazard');
      return;
    }
    final result = await Get.dialog<ReportResult>(
      ReportDialog(initialCenter: _center()),
      barrierDismissible: true,
    );
    if (result == null) return;
    final hazard = HazardModel(
      id: DemoData.newId(),
      type: result.type,
      lat: result.point.latitude,
      lng: result.point.longitude,
      reportedBy: user.uid,
      createdAt: DateTime.now(),
      note: result.note,
    );
    await _fs.upsertHazard(hazard);
    _toast.showSuccessMessage('${hazard.type.label} reported');
  }

  LatLng _center() => LatLng(AppConfig.defaultLat, AppConfig.defaultLng);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final cardHeight = screen.height * 0.38; // Increased height from 0.28 to 0.38
    final cardWidth = screen.width * 0.90;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _appBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              _greetingCard(),
              const SizedBox(height: 14),
              // Map Card with iOS style
              Center(
                child: _buildMapCard(cardHeight, cardWidth),
              ),
              const SizedBox(height: 20),
              _actionButtons(),
              const SizedBox(height: 20),
              _legend(cardWidth),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard(double height, double width) {
    return Container(
      width: width,
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
        child: Column(
          children: [
            // Map Container
            SizedBox(
              height: height,
              child: _loadingOsm
                  ? _loadingTile()
                  : TacticalMap(
                center: _center(),
                initialZoom: AppConfig.defaultZoom,
                roadLines: _osm == null
                    ? const []
                    : _osm!.roads
                    .map((f) => f.geometry)
                    .toList(),
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
                hazards: _allHazards,
              ),
            ),
            // Open Map Button integrated in card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.shade100,
                    width: 1,
                  ),
                ),
              ),
              child: _openMapButton(),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    centerTitle: false,
    title: Text(
      'Tactical Disaster Sim',
      style: GoogleFonts.quicksand(
        fontWeight: FontWeight.w800,
        fontSize: 18,
        color: AppColors.textColor,
      ),
    ),
  );

  Widget _greetingCard() => Obx(() {
    final user = _authCtrl.profile.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user == null
                      ? 'Welcome'
                      : 'Hello, ${user.name.split(' ').first}',
                  style: GoogleFonts.quicksand(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: AppColors.textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Kavrepalanchok • OSM live snapshot',
                  style: GoogleFonts.quicksand(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  });

  Widget _loadingTile() => Container(
    color: const Color(0xFFEFEFEF),
    child: const Center(child: CircularProgressIndicator()),
  );

  Widget _openMapButton() => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: ElevatedButton.icon(
      onPressed: () => Get.to(() => OpenMapScreen(
        osm: _osm,
        hazards: _allHazards,
      )),
      icon: const Icon(Icons.map_outlined, size: 20),
      label: Text(
        'Open Full Map',
        style: GoogleFonts.quicksand(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
  );

  Widget _actionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _modernActionButton(
              icon: Icons.report_problem_rounded,
              label: 'Report', // Changed from 'Report Hazard' to 'Report'
              color: AppColors.warningOrange,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
              ),
              onTap: _openReportDialog,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _modernActionButton(
              icon: Icons.medical_services_rounded,
              label: 'Casualty',
              color: AppColors.errorRed,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEF5350), Color(0xFFE53935)],
              ),
              onTap: () => Get.to(() => const CasualtyScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10), // Reduced height
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6), // Reduced padding
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18), // Reduced icon size
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.quicksand(
                    fontSize: 13, // Reduced font size
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withOpacity(0.9),
                size: 16, // Reduced icon size
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend(double width) => Container(
    width: width,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade200, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
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
        const SizedBox(height: 14),
        // Row 1: 3 items
        Row(
          children: [
            Expanded(child: _buildLegendItem('🏥', 'Hospital')),
            const SizedBox(width: 8),
            Expanded(child: _buildLegendItem('🏛️', 'Ward')),
            const SizedBox(width: 8),
            Expanded(child: _buildLegendItem('🌲', 'Forest')),
          ],
        ),
        const SizedBox(height: 8),
        // Row 2: 3 items
        Row(
          children: [
            Expanded(child: _buildLegendItem('🔥', 'Fire')),
            const SizedBox(width: 8),
            Expanded(child: _buildLegendItem('🌊', 'Flood')),
            const SizedBox(width: 8),
            Expanded(child: _buildLegendItem('🚧', 'Danger')),
          ],
        ),
        const SizedBox(height: 8),
        // Row 3: 2 items (Landslide and Ambulance) covering full width
        Row(
          children: [
            Expanded(child: _buildLegendItem('⛰️', 'Landslide')),
            const SizedBox(width: 8),
            Expanded(child: _buildLegendItem('🚑', 'Ambulance')),
          ],
        ),
      ],
    ),
  );

  Widget _buildLegendItem(String emoji, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
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
    if (pts.isEmpty) return _center();
    double sumLat = 0;
    double sumLng = 0;
    for (final p in pts) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / pts.length, sumLng / pts.length);
  }
}