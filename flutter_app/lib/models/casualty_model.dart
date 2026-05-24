import 'package:latlong2/latlong.dart';

enum CasualtyStatus { pending, dispatched, completed }

extension CasualtyStatusX on CasualtyStatus {
  String get key => toString().split('.').last;
  static CasualtyStatus fromKey(String k) =>
      CasualtyStatus.values.firstWhere((e) => e.key == k,
          orElse: () => CasualtyStatus.pending);
}

class CasualtyModel {
  final String id;
  final double lat;
  final double lng;
  final String reportedBy;
  final DateTime createdAt;
  final CasualtyStatus status;
  final String? assignedAmbulanceId;

  CasualtyModel({
    required this.id,
    required this.lat,
    required this.lng,
    required this.reportedBy,
    required this.createdAt,
    this.status = CasualtyStatus.pending,
    this.assignedAmbulanceId,
  });

  LatLng get latLng => LatLng(lat, lng);

  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'lat': lat,
        'lng': lng,
        'reportedBy': reportedBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'status': status.key,
        'assignedAmbulanceId': assignedAmbulanceId,
      };

  factory CasualtyModel.fromMap(Map<String, dynamic> data) => CasualtyModel(
        id: (data['id'] ?? '') as String,
        lat: (data['lat'] as num).toDouble(),
        lng: (data['lng'] as num).toDouble(),
        reportedBy: (data['reportedBy'] ?? '') as String,
        createdAt: DateTime.tryParse((data['createdAt'] ?? '') as String) ??
            DateTime.now(),
        status: CasualtyStatusX.fromKey((data['status'] ?? 'pending') as String),
        assignedAmbulanceId: data['assignedAmbulanceId'] as String?,
      );
}
