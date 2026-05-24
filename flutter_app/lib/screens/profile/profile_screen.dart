import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../services/auth_service.dart';
import '../../services/toast_service.dart';
import '../../themes/colors.dart';
import '../../widgets/facebook_avatar.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authCtrl = Get.find<AuthController>();
    final authService = Get.find<AuthService>();
    final toast = Get.find<ToastService>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Profile',
          style: GoogleFonts.quicksand(
            fontWeight: FontWeight.w800,
            color: AppColors.textColor,
          ),
        ),
      ),
      body: Obx(() {
        final user = authCtrl.profile.value;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Default Facebook-style silhouette avatar (no upload, ever).
              const FacebookAvatar(size: 116),
              const SizedBox(height: 18),
              Text(
                user?.name.isNotEmpty == true ? user!.name : '—',
                style: GoogleFonts.quicksand(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? '',
                style: GoogleFonts.quicksand(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              _infoTile(
                icon: Icons.email_rounded,
                color: AppColors.emailIconColor,
                title: 'Email',
                value: user?.email ?? '—',
              ),
              const SizedBox(height: 10),
              _infoTile(
                icon: Icons.phone_rounded,
                color: AppColors.phoneIconColor,
                title: 'Phone',
                value: user?.phone.isNotEmpty == true ? user!.phone : '—',
              ),
              const SizedBox(height: 10),
              _infoTile(
                icon: Icons.badge_rounded,
                color: AppColors.nameIconColor,
                title: 'Role',
                value: (user?.role ?? 'reporter').toUpperCase(),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await authService.signOut();
                    authCtrl.clearUserSession();
                    toast.showSuccessMessage('Signed out');
                    Get.offAll(() => LoginScreen());
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(
                    'Sign Out',
                    style: GoogleFonts.quicksand(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.errorRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.quicksand(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.quicksand(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
