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
    final cardHeight = screen.height * 0.20;
    final cardWidth = screen.width * 0.90;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              _greetingCard(),
              const SizedBox(height: 14),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: cardHeight,
                    width: cardWidth,
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
                                    .map((f) =>
                                        _centroid(f.geometry))
                                    .toList(),
                            hospitals: _osm == null
                                ? const []
                                : _osm!.hospitals
                                    .map((f) =>
                                        _centroid(f.geometry))
                                    .toList(),
                            wards: _osm == null
                                ? const []
                                : _osm!.wards
                                    .map((f) =>
                                        _centroid(f.geometry))
                                    .toList(),
                            hazards: _allHazards,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _openMapButton(cardWidth),
              const SizedBox(height: 18),
              _actionButtons(cardWidth),
              const SizedBox(height: 18),
              _legend(cardWidth),
            ],
          ),
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

  Widget _openMapButton(double width) => SizedBox(
        width: width,
        height: 46,
        child: ElevatedButton.icon(
          onPressed: () => Get.to(() => OpenMapScreen(
                osm: _osm,
                hazards: _allHazards,
              )),
          icon: const Icon(Icons.map_outlined),
          label: Text(
            'Open Map',
            style: GoogleFonts.quicksand(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            elevation: 3,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  Widget _actionButtons(double width) => Padding(
        padding: EdgeInsets.symmetric(horizontal: (1 - 0.9) * 200),
        child: Row(
          children: [
            Expanded(
              child: _bigAction(
                icon: Icons.report_problem_rounded,
                label: 'Report',
                color: AppColors.warningOrange,
                onTap: _openReportDialog,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _bigAction(
                icon: Icons.medical_services_rounded,
                label: 'Casualty',
                color: AppColors.errorRed,
                onTap: () => Get.to(() => const CasualtyScreen()),
              ),
            ),
          ],
        ),
      );

  Widget _bigAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.quicksand(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _legend(double width) => Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Map legend',
                style: GoogleFonts.quicksand(
                    fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: const [
                _LegendChip(emoji: '🏥', label: 'Hospital'),
                _LegendChip(emoji: '🏛️', label: 'Ward'),
                _LegendChip(emoji: '🌲', label: 'Forest'),
                _LegendChip(emoji: '🔥', label: 'Fire'),
                _LegendChip(emoji: '🌊', label: 'Flood'),
                _LegendChip(emoji: '⛰️', label: 'Landslide'),
                _LegendChip(emoji: '🚧', label: 'Danger'),
                _LegendChip(emoji: '🚑', label: 'Ambulance'),
              ],
            ),
          ],
        ),
      );

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

class _LegendChip extends StatelessWidget {
  final String emoji;
  final String label;
  const _LegendChip({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.quicksand(
                fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
