import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../themes/colors.dart';
import '../../widgets/facebook_avatar.dart';
import '../casualty/casualty_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';

/// Bottom navigation per blueprint section 7:
///   tabs = [Home, Casualty, profile-icon]
/// The profile control uses the default Facebook-style silhouette avatar
/// instead of the literal text "Profile".
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  final _pages = const [
    HomeScreen(),
    CasualtyScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(
                  selected: _index == 0,
                  iconBuilder: (active) => Icon(
                    Icons.home_rounded,
                    size: 26,
                    color: active ? AppColors.primaryPurple : Colors.grey,
                  ),
                  label: 'Home',
                  onTap: () => setState(() => _index = 0),
                ),
                _navItem(
                  selected: _index == 1,
                  iconBuilder: (active) => Icon(
                    Icons.medical_services_rounded,
                    size: 26,
                    color: active ? Colors.red : Colors.grey,
                  ),
                  label: 'Casualty',
                  onTap: () => setState(() => _index = 1),
                ),
                _navItem(
                  selected: _index == 2,
                  // Facebook-style default avatar (no text label).
                  iconBuilder: (active) => FacebookAvatar(
                    size: 30,
                    border: active
                        ? const BorderSide(
                            color: AppColors.primaryPurple, width: 2)
                        : null,
                  ),
                  label: '',
                  onTap: () => setState(() => _index = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required bool selected,
    required Widget Function(bool active) iconBuilder,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconBuilder(selected),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.quicksand(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primaryPurple : Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
