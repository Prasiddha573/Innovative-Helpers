import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../themes/colors.dart';

class PhoneInputField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String? Function(String?)? validator;

  const PhoneInputField({
    super.key,
    required this.controller,
    required this.hintText,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.phoneIconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.phone_outlined,
                color: AppColors.phoneIconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              style: GoogleFonts.quicksand(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textColor,
              ),
              cursorColor: AppColors.primaryBlue,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: GoogleFonts.quicksand(
                  color: AppColors.getHintTextColor(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
                helperText: ' ',
                errorStyle: GoogleFonts.quicksand(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.errorRed,
                ),
                contentPadding: const EdgeInsets.only(top: 15),
                isDense: true,
                counterText: '',
              ),
              validator: validator,
            ),
          ),
        ],
      ),
    );
  }
}
