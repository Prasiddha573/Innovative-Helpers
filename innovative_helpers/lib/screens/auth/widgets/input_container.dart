import 'package:flutter/material.dart';

import '../../../themes/colors.dart';

class InputContainer extends StatelessWidget {
  final List<Widget> children;
  const InputContainer({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.getBorderColor(context), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class InputDivider extends StatelessWidget {
  const InputDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.3, color: Colors.grey.shade400);
}
