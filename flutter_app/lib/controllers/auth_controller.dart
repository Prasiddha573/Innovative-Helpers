import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../models/user_model.dart';

/// Holds the currently authenticated user's profile pulled from Firestore.
class AuthController extends GetxController {
  final Rxn<UserModel> profile = Rxn<UserModel>();

  /// Load the current user's profile document from the `users` collection.
  Future<void> initializeUserSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      profile.value = null;
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        profile.value = UserModel.fromMap(user.uid, doc.data() ?? {});
      } else {
        profile.value = UserModel(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          phone: '',
        );
      }
    } catch (_) {
      profile.value = null;
    }
  }

  void clearUserSession() {
    profile.value = null;
  }
}
