/// Authentication form validators - same rules as smart-room-system so the
/// auth UX is identical (email, name, Nepali phone, strong password).
class AuthValidators {
  static String? validateFullName(String? value) {
    if (value == null || value.isEmpty) return 'Please Enter Your Full Name';
    if (!RegExp(r'^[a-zA-Z ]+$').hasMatch(value)) {
      return 'Name Should Contain Only Letters And Spaces';
    }
    if (value.length < 2) return 'Name Must Be At Least 2 Characters';
    return null;
  }

  static String? validateNepaliPhone(String? value) {
    if (value == null || value.isEmpty) return 'Please Enter Your Phone Number';
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length != 10) return 'Phone Number Must Be Exactly 10 Digits';
    if (!cleaned.startsWith('97') && !cleaned.startsWith('98')) {
      return 'Phone Number Must Start With 97 Or 98';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please Enter Your Email Address';
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(value)) {
      return 'Please Enter A Valid Email Address';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please Enter A Password';
    if (value.length < 8) return 'Password Must Be At Least 8 Characters';
    if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d@$!%*#?&]+$').hasMatch(value)) {
      return 'Password Must Contain Both Letters And Numbers';
    }
    return null;
  }

  static String? validateConfirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please Confirm Your Password';
    if (value != original) return 'Passwords Do Not Match';
    return null;
  }
}
