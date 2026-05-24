import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../models/hazard_model.dart';
import '../../themes/colors.dart';

class ReportResult {
  final HazardType type;
  final LatLng point;
  final String? note;
  ReportResult({required this.type, required this.point, this.note});
}

class ReportDialog extends StatefulWidget {
  final LatLng initialCenter;
  const ReportDialog({super.key, required this.initialCenter});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  HazardType _type = HazardType.flood;
  late LatLng _picked;
  final _noteCtrl = TextEditingController();
  final _mapCtrl = MapController();

  @override
  void initState() {
    super.initState();
    _picked = widget.initialCenter;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      backgroundColor: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        height: media.height * 0.82,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report a hazard',
                style: GoogleFonts.quicksand(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap on the map to set the hazard location',
                style: GoogleFonts.quicksand(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: HazardType.values
                    .map((t) => ChoiceChip(
                          label:
                              Text('${t.emoji}  ${t.label}'),
                          selected: _type == t,
                          onSelected: (_) =>
                              setState(() => _type = t),
                          selectedColor: AppColors.primaryPurple
                              .withOpacity(0.18),
                          labelStyle: GoogleFonts.quicksand(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _type == t
                                ? AppColors.primaryPurple
                                : AppColors.textColor,
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: _picked,
                      initialZoom: 12,
                      onTap: (tapPos, point) =>
                          setState(() => _picked = point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.tactical_disaster_simulation',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: _picked,
                          width: 40,
                          height: 40,
                          child: Text(_type.emoji,
                              style: const TextStyle(fontSize: 32)),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  hintText: 'Optional note',
                  hintStyle: GoogleFonts.quicksand(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  filled: true,
                  fillColor: const Color(0xFFF6F6F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Get.back(
                          result: ReportResult(
                        type: _type,
                        point: _picked,
                        note: _noteCtrl.text.trim().isEmpty
                            ? null
                            : _noteCtrl.text.trim(),
                      )),
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
