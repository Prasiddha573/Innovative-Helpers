import 'package:flutter/material.dart';

import '../themes/colors.dart';

/// Default Facebook-style silhouette avatar - flat gray circle with a
/// rounded white person silhouette. No profile picture upload is supported.
class FacebookAvatar extends StatelessWidget {
  final double size;
  final BorderSide? border;
  const FacebookAvatar({super.key, this.size = 40, this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.facebookAvatarGray,
        shape: BoxShape.circle,
        border: border != null
            ? Border.fromBorderSide(border!)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _FacebookSilhouettePainter(),
      ),
    );
  }
}

class _FacebookSilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..color = AppColors.facebookAvatarSilhouette;

    // Head - top circle.
    canvas.drawCircle(Offset(w * 0.5, h * 0.38), w * 0.17, paint);

    // Body - rounded rectangle (the classic FB ‘shoulders’ shape).
    final rect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.92),
      width: w * 0.66,
      height: h * 0.55,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(w * 0.33),
        topRight: Radius.circular(w * 0.33),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
