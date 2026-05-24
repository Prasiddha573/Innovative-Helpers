import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../controllers/show_password_controller.dart';
import '../../../themes/colors.dart';

class CustomInputField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final String hintText;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final bool isPassword;
  final bool isConfirmPassword;

  const CustomInputField({
    super.key,
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.hintText,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.isPassword = false,
    this.isConfirmPassword = false,
  });

  @override
  Widget build(BuildContext context) {
    final showPasswordController = Get.find<ShowPasswordController>();
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _iconBox(),
          const SizedBox(width: 12),
          Expanded(
            child: isPassword
                ? _passwordField(showPasswordController, context)
                : _normalField(context),
          ),
        ],
      ),
    );
  }

  Widget _iconBox() => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      );

  Widget _normalField(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textAlignVertical: TextAlignVertical.center,
        style: GoogleFonts.quicksand(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textColor,
        ),
        cursorColor: AppColors.primaryBlue,
        decoration: _decoration(context),
        validator: validator,
      );

  Widget _passwordField(ShowPasswordController c, BuildContext context) {
    return Obx(() {
      final visible = isConfirmPassword
          ? c.isConfirmPasswordVisible.value
          : c.isPasswordVisible.value;
      return Stack(
        alignment: Alignment.centerRight,
        children: [
          TextFormField(
            controller: controller,
            obscureText: !visible,
            textAlignVertical: TextAlignVertical.center,
            style: GoogleFonts.quicksand(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textColor,
            ),
            cursorColor: AppColors.primaryBlue,
            decoration: _decoration(context).copyWith(
              contentPadding: const EdgeInsets.only(top: 15, right: 44),
            ),
            validator: validator,
          ),
          Positioned(
            right: 0,
            child: GestureDetector(
              onTap: isConfirmPassword
                  ? c.toggleConfirmPasswordVisibility
                  : c.togglePasswordVisibility,
              child: Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(8),
                child: Icon(
                  visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  InputDecoration _decoration(BuildContext context) => InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.quicksand(
          color: AppColors.getHintTextColor(context),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
        border: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        helperText: ' ',
        helperStyle: const TextStyle(height: 0.8, color: Colors.transparent),
        errorStyle: GoogleFonts.quicksand(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.errorRed,
          height: 1.0,
        ),
        contentPadding: const EdgeInsets.only(top: 15),
        isDense: true,
      );
}
