import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

class LocationService {
  /// Best-effort GPS fetch. Falls back to the configured default centre
  /// (Dhulikhel, Kavrepalanchok) if permissions are denied or unavailable.
  static Future<LatLng> getCurrentOrDefault() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return _fallback();

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return _fallback();
        }
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return _fallback();
    }
  }

  static LatLng _fallback() =>
      LatLng(AppConfig.defaultLat, AppConfig.defaultLng);
}
