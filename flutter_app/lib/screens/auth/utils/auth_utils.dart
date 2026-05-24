import 'package:flutter/material.dart';

/// Responsive helpers used by both login and signup screens.
class AuthUtils {
  static double getResponsiveHeight(BuildContext context, double pct) =>
      MediaQuery.of(context).size.height * pct;

  static double getResponsiveWidth(BuildContext context, double pct) =>
      MediaQuery.of(context).size.width * pct;

  static double getBottomInset(BuildContext context) =>
      MediaQuery.of(context).viewInsets.bottom;

  static List<Widget> buildBackgroundGradients(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    return [
      Positioned(
        top: -h * 0.15,
        right: -w * 0.1,
        child: Container(
          width: w * 0.5,
          height: w * 0.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [const Color(0xFF007AFF).withOpacity(0.08),
                  Colors.transparent],
            ),
          ),
        ),
      ),
      Positioned(
        bottom: -h * 0.1,
        left: -w * 0.1,
        child: Container(
          width: w * 0.4,
          height: w * 0.4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [const Color(0xFFFF9500).withOpacity(0.06),
                  Colors.transparent],
            ),
          ),
        ),
      ),
    ];
  }
}
