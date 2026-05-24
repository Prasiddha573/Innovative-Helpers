/// USER MODEL - mirrors the `users` Firestore collection
/// Only stores: email, name, phone (per blueprint section 12). Profile
/// picture uses a default Facebook-style avatar rendered client-side.
class UserModel {
  final String uid;
  final String name;
  final String phone;
  final String email;
  final String role; // 'reporter' | 'responder' | 'admin'

  UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.email,
    this.role = 'reporter',
  });

  Map<String, dynamic> toFirestoreMap() => {
        'uid': uid,
        'name': name.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'role': role,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) =>
      UserModel(
        uid: uid,
        name: (data['name'] ?? '') as String,
        phone: (data['phone'] ?? '') as String,
        email: (data['email'] ?? '') as String,
        role: (data['role'] ?? 'reporter') as String,
      );
}
