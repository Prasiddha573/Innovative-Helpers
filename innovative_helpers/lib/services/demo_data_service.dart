import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/ambulance_model.dart';
import '../models/hazard_model.dart';

/// Hard-coded demo data inside Kavrepalanchok district so the app boots up
/// with a populated map even before Firebase or the Python backend are
/// reachable. Coordinates were chosen around Dhulikhel / Banepa / Panauti.
class DemoData {
  static const _uuid = Uuid();

  static List<AmbulanceModel> seedAmbulances() => [
        AmbulanceModel(
          id: 'amb-dhulikhel-hospital',
          stationName: 'Dhulikhel Hospital',
          lat: 27.6193,
          lng: 85.5444,
        ),
        AmbulanceModel(
          id: 'amb-banepa-ward',
          stationName: 'Banepa Ward 6',
          lat: 27.6308,
          lng: 85.5193,
        ),
        AmbulanceModel(
          id: 'amb-panauti-ward',
          stationName: 'Panauti Ward 4',
          lat: 27.5806,
          lng: 85.5176,
        ),
        AmbulanceModel(
          id: 'amb-panchkhal-ward',
          stationName: 'Panchkhal Ward 2',
          lat: 27.6736,
          lng: 85.6276,
        ),
      ];

  static List<HazardModel> seedHazards(String demoUid) => [
        HazardModel(
          id: 'demo-flood-roshi',
          type: HazardType.flood,
          lat: 27.5862,
          lng: 85.5350,
          reportedBy: demoUid,
          createdAt: DateTime.now(),
          persistent: true,
          note: 'Roshi Khola - seasonal flood corridor',
        ),
        HazardModel(
          id: 'demo-landslide-namobuddha',
          type: HazardType.landslide,
          lat: 27.5969,
          lng: 85.5828,
          reportedBy: demoUid,
          createdAt: DateTime.now(),
          persistent: true,
          note: 'Namobuddha ridge - landslide-prone',
        ),
        HazardModel(
          id: 'demo-forestfire-sun-koshi',
          type: HazardType.forestFire,
          lat: 27.7060,
          lng: 85.7320,
          reportedBy: demoUid,
          createdAt: DateTime.now(),
          persistent: true,
          note: 'Sunkoshi forest patch',
        ),
        HazardModel(
          id: 'demo-danger-mahabharat',
          type: HazardType.dangerZone,
          lat: 27.5455,
          lng: 85.6480,
          reportedBy: demoUid,
          createdAt: DateTime.now(),
          persistent: true,
          note: 'Mahabharat range - rockfall risk',
        ),
      ];

  /// Static forest centroids used to drop tree emojis (decorative).
  static List<LatLng> seedForestCentroids() => const [
        LatLng(27.7080, 85.7300),
        LatLng(27.6700, 85.6700),
        LatLng(27.5500, 85.6500),
        LatLng(27.6400, 85.5650),
      ];

  static String newId() => _uuid.v4();
}
