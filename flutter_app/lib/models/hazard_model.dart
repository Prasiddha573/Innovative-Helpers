import 'package:latlong2/latlong.dart';

/// Hazard categories supported on the home map.
enum HazardType { forestFire, flood, landslide, dangerZone }

extension HazardTypeX on HazardType {
  String get label {
    switch (this) {
      case HazardType.forestFire:
        return 'Forest Fire';
      case HazardType.flood:
        return 'Flood';
      case HazardType.landslide:
        return 'Landslide Risk';
      case HazardType.dangerZone:
        return 'Danger Zone';
    }
  }

  String get emoji {
    switch (this) {
      case HazardType.forestFire:
        return '🔥';
      case HazardType.flood:
        return '🌊';
      case HazardType.landslide:
        return '⛰️';
      case HazardType.dangerZone:
        return '🚧';
    }
  }

  String get firestoreKey {
    switch (this) {
      case HazardType.forestFire:
        return 'forest_fire';
      case HazardType.flood:
        return 'flood';
      case HazardType.landslide:
        return 'landslide';
      case HazardType.dangerZone:
        return 'danger_zone';
    }
  }

  static HazardType fromKey(String key) {
    switch (key) {
      case 'forest_fire':
        return HazardType.forestFire;
      case 'flood':
        return HazardType.flood;
      case 'landslide':
        return HazardType.landslide;
      case 'danger_zone':
      default:
        return HazardType.dangerZone;
    }
  }
}

class HazardModel {
  final String id;
  final HazardType type;
  final double lat;
  final double lng;
  final String reportedBy; // uid of user
  final DateTime createdAt;
  final bool persistent;
  final String? note;

  HazardModel({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.reportedBy,
    required this.createdAt,
    this.persistent = false,
    this.note,
  });

  LatLng get latLng => LatLng(lat, lng);

  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'type': type.firestoreKey,
        'lat': lat,
        'lng': lng,
        'reportedBy': reportedBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'persistent': persistent,
        'note': note,
      };

  factory HazardModel.fromMap(Map<String, dynamic> data) => HazardModel(
        id: (data['id'] ?? '') as String,
        type: HazardTypeX.fromKey((data['type'] ?? 'danger_zone') as String),
        lat: (data['lat'] as num).toDouble(),
        lng: (data['lng'] as num).toDouble(),
        reportedBy: (data['reportedBy'] ?? '') as String,
        createdAt: DateTime.tryParse((data['createdAt'] ?? '') as String) ??
            DateTime.now(),
        persistent: (data['persistent'] ?? false) as bool,
        note: data['note'] as String?,
      );
}
