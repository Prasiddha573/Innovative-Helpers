import 'package:latlong2/latlong.dart';

class AmbulanceModel {
  final String id;
  final String stationName; // ward or hospital name
  final double lat;
  final double lng;
  final bool available;
  final String? lockedFor; // casualty id while dispatched

  AmbulanceModel({
    required this.id,
    required this.stationName,
    required this.lat,
    required this.lng,
    this.available = true,
    this.lockedFor,
  });

  LatLng get latLng => LatLng(lat, lng);

  AmbulanceModel copyWith({
    double? lat,
    double? lng,
    bool? available,
    String? lockedFor,
  }) =>
      AmbulanceModel(
        id: id,
        stationName: stationName,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        available: available ?? this.available,
        lockedFor: lockedFor,
      );

  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'stationName': stationName,
        'lat': lat,
        'lng': lng,
        'available': available,
        'lockedFor': lockedFor,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

  factory AmbulanceModel.fromMap(Map<String, dynamic> data) => AmbulanceModel(
        id: (data['id'] ?? '') as String,
        stationName: (data['stationName'] ?? '') as String,
        lat: (data['lat'] as num).toDouble(),
        lng: (data['lng'] as num).toDouble(),
        available: (data['available'] ?? true) as bool,
        lockedFor: data['lockedFor'] as String?,
      );
}
