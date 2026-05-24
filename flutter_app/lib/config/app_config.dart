/// APPLICATION CONFIGURATION CONSTANTS
class AppConfig {
  // Python backend base URL (Flask). When running on Android emulator, host
  // localhost is reachable at 10.0.2.2. For real devices, use your LAN IP.
  // Override via --dart-define=BACKEND_URL=http://192.168.1.10:5000
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );

  // Overpass public API endpoint
  static const String overpassUrl = 'https://overpass-api.de/api/interpreter';

  // Kavrepalanchok district approximate bounding box (south, west, north, east)
  // This box covers the district reasonably for OSM queries.
  static const double bboxSouth = 27.45;
  static const double bboxWest = 85.40;
  static const double bboxNorth = 27.95;
  static const double bboxEast = 85.95;

  // Map default center (Dhulikhel area - district headquarters)
  static const double defaultLat = 27.6210;
  static const double defaultLng = 85.5439;
  static const double defaultZoom = 12.0;

  // Animation frame rate for ambulance movement
  static const int ambulanceFps = 12;
}
