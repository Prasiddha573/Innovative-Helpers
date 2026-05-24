import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryBlue = Color(0xFF007AFF);
  static const Color primaryPurple = Color(0xFF6366F1);
  static const Color secondaryPurple = Color(0xFF8B5CF6);

  static const Color nameIconColor = Color(0xFF34C759);
  static const Color phoneIconColor = Color(0xFFDC241F);
  static const Color emailIconColor = Color(0xFF007AFF);
  static const Color passwordIconColor = Color(0xFFFF9500);
  static const Color confirmPasswordIconColor = Color(0xFF5856D6);

  static const Color successGreen = Color(0xFF34C759);
  static const Color errorRed = Color(0xFFFF3B30);
  static const Color warningOrange = Color(0xFFFF9500);

  // Hazard / route palette
  static const Color goldenRoute = Color(0xFFFFC107);
  static const Color skyBlueRoute = Color(0xFF38BDF8);
  static const Color floodBlue = Color(0xFF1976D2);
  static const Color fireRed = Color(0xFFE53935);
  static const Color landslideBrown = Color(0xFF8D6E63);
  static const Color forestGreen = Color(0xFF2E7D32);

  // Facebook default avatar gray
  static const Color facebookAvatarGray = Color(0xFFDFE3EE);
  static const Color facebookAvatarSilhouette = Color(0xFF8A8D91);

  static const Color backgroundColor = Colors.white;
  static const Color textColor = Colors.black87;
  static const Color hintTextColor = Color(0xFF666666);
  static const Color borderColor = Color(0xFFE5E5E5);

  static const List<Color> buttonGradient = [
    Color(0xFF6366F1),
    Color(0xFF8B5CF6),
  ];
  static const List<Color> textGradient = [
    Color(0xFF6366F1),
    Color(0xFFFF6B95),
  ];

  static Color getHintTextColor(BuildContext context) =>
      Colors.grey.shade700;

  static Color getBorderColor(BuildContext context) =>
      Colors.grey.shade300;
}
