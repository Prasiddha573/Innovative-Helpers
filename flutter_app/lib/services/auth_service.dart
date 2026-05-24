import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../models/user_model.dart';
import 'toast_service.dart';

/// Firebase Authentication wrapper. Stores only email/name/phone in the
/// `users` collection - profile picture stays as the default avatar.
class AuthService extends GetxService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ToastService _toast = ToastService();

  Future<User?> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    try {
      // Pre-check duplicate email (Firebase Auth also catches this on creation,
      // but we surface the message early.)
      final existing = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        _toast.showErrorMessage('Email Already Exists');
        return null;
      }

      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('User creation failed');
      }

      final profile = UserModel(
        uid: user.uid,
        name: fullName.trim(),
        phone: phone.trim(),
        email: email.trim(),
      );
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(profile.toFirestoreMap());

      try {
        await user.sendEmailVerification();
      } catch (_) {}

      _toast.showSuccessMessage('Account Created Successfully!');
      return user;
    } on FirebaseAuthException catch (e) {
      _handleSignupError(e);
      return null;
    } catch (_) {
      _toast.showErrorMessage('An Unexpected Error Occurred');
      return null;
    }
  }

  Future<User?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return credential.user;
    } on FirebaseAuthException catch (e) {
      _handleLoginError(e);
      return null;
    } catch (_) {
      _toast.showErrorMessage('An Unexpected Error Occurred');
      return null;
    }
  }

  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
      return true;
    } on FirebaseAuthException catch (e) {
      _handleResetError(e);
      return false;
    } catch (_) {
      _toast.showErrorMessage('Failed To Send Reset Email');
      return false;
    }
  }

  Future<void> signOut() => _firebaseAuth.signOut();

  User? get currentUser => _firebaseAuth.currentUser;
  bool get isLoggedIn => _firebaseAuth.currentUser != null;

  void _handleSignupError(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        _toast.showErrorMessage('Please Check Your Connection');
        break;
      case 'too-many-requests':
        _toast.showErrorMessage('Too Many Attempts');
        break;
      case 'email-already-in-use':
        _toast.showErrorMessage('Email Is Already Registered');
        break;
      case 'weak-password':
        _toast.showErrorMessage('Use A Stronger Password');
        break;
      case 'invalid-email':
        _toast.showErrorMessage('Invalid Email Address');
        break;
      default:
        _toast.showErrorMessage('Registration Failed');
    }
  }

  void _handleLoginError(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        _toast.showErrorMessage('Please Check Your Connection');
        break;
      case 'too-many-requests':
        _toast.showErrorMessage('Too Many Attempts');
        break;
      case 'user-not-found':
        _toast.showErrorMessage('No Account Found With This Email');
        break;
      case 'wrong-password':
      case 'invalid-credential':
        _toast.showErrorMessage('Incorrect Email Or Password');
        break;
      case 'invalid-email':
        _toast.showErrorMessage('Invalid Email Address');
        break;
      case 'user-disabled':
        _toast.showErrorMessage('Account Has Been Disabled');
        break;
      default:
        _toast.showErrorMessage('Login Failed');
    }
  }

  void _handleResetError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        _toast.showErrorMessage('Invalid Email Address');
        break;
      case 'user-not-found':
        _toast.showErrorMessage('No Account Found With This Email');
        break;
      default:
        _toast.showErrorMessage('Failed To Send Reset Email');
    }
  }
}
