import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ambulance_model.dart';
import '../models/casualty_model.dart';
import '../models/hazard_model.dart';

/// Thin wrapper around the Firestore collections defined in the blueprint:
///   users, hazards, casualties, ambulances, routes
class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // -------- Hazards --------
  CollectionReference<Map<String, dynamic>> get _hazards =>
      _db.collection('hazards');

  Future<void> upsertHazard(HazardModel h) async {
    await _hazards.doc(h.id).set(h.toFirestoreMap());
  }

  Future<void> removeHazard(String id) async {
    await _hazards.doc(id).delete();
  }

  Stream<List<HazardModel>> watchHazards() {
    return _hazards.snapshots().map((snap) => snap.docs
        .map((d) => HazardModel.fromMap(d.data()))
        .toList(growable: false));
  }

  // -------- Casualties --------
  CollectionReference<Map<String, dynamic>> get _casualties =>
      _db.collection('casualties');

  Future<void> upsertCasualty(CasualtyModel c) async {
    await _casualties.doc(c.id).set(c.toFirestoreMap());
  }

  Stream<List<CasualtyModel>> watchCasualties() {
    return _casualties.snapshots().map((snap) => snap.docs
        .map((d) => CasualtyModel.fromMap(d.data()))
        .toList(growable: false));
  }

  // -------- Ambulances --------
  CollectionReference<Map<String, dynamic>> get _ambulances =>
      _db.collection('ambulances');

  Future<void> upsertAmbulance(AmbulanceModel a) async {
    await _ambulances.doc(a.id).set(a.toFirestoreMap());
  }

  Stream<List<AmbulanceModel>> watchAmbulances() {
    return _ambulances.snapshots().map((snap) => snap.docs
        .map((d) => AmbulanceModel.fromMap(d.data()))
        .toList(growable: false));
  }

  // -------- Routes --------
  CollectionReference<Map<String, dynamic>> get _routes =>
      _db.collection('routes');

  Future<void> saveRoute({
    required String id,
    required List<List<double>> primary,
    required List<List<double>> secondary,
    required String state,
  }) async {
    await _routes.doc(id).set({
      'id': id,
      'primary': primary,
      'secondary': secondary,
      'state': state,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
