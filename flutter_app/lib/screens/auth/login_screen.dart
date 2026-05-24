import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/loader_controller.dart';
import '../../controllers/show_password_controller.dart';
import '../../services/auth_service.dart';
import '../../services/toast_service.dart';
import '../../themes/colors.dart';
import '../main/main_screen.dart';
import 'signup_screen.dart';
import 'utils/auth_utils.dart';
import 'utils/validators.dart';
import 'widgets/auth_buttons.dart';
import 'widgets/auth_header.dart';
import 'widgets/input_container.dart';
import 'widgets/input_fields.dart';

class LoginScreen extends StatelessWidget {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final AuthService authService = Get.find<AuthService>();
  final LoaderController loaderController = Get.find<LoaderController>();
  // Ensure password visibility singleton exists.
  final _ = Get.find<ShowPasswordController>();
  final AuthController authController = Get.find<AuthController>();
  final ToastService toastService = Get.find<ToastService>();

  LoginScreen({super.key});

  Future<void> _handleLogin() async {
    if (!formKey.currentState!.validate()) return;
    loaderController.startLoading();
    final user = await authService.signInWithEmailAndPassword(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
    );
    loaderController.stopLoading();
    if (user != null) {
      await authController.initializeUserSession();
      toastService.showSuccessMessage('Login Successful!');
      Get.offAll(() => const MainScreen());
    }
  }

  Future<void> _handleForgotPassword() async {
    if (emailController.text.isEmpty) {
      toastService.showErrorMessage('Enter Email To Reset Password');
      return;
    }
    final emailError =
        AuthValidators.validateEmail(emailController.text.trim());
    if (emailError != null) {
      toastService.showErrorMessage('Enter Valid Email To Reset Password');
      return;
    }
    loaderController.startLoading();
    final ok = await authService
        .sendPasswordResetEmail(emailController.text.trim());
    loaderController.stopLoading();
    if (ok) toastService.showSuccessMessage('Forgot Password Email Sent');
  }

  @override
  Widget build(BuildContext context) {
    final h = AuthUtils.getResponsiveHeight(context, 1);
    final w = AuthUtils.getResponsiveWidth(context, 1);
    final bottomInset = AuthUtils.getBottomInset(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      resizeToAvoidBottomInset: false,
      body: Form(
        key: formKey,
        child: Stack(
          children: [
            ...AuthUtils.buildBackgroundGradients(context),
            Column(
              children: [
                AuthHeader(
                  height: h * 0.38,
                  icon: Icons.shield_moon_rounded,
                  title: 'Tactical Disaster Sim',
                  subtitle: 'Kavrepalanchok Emergency Response',
                ),
                Expanded(child: _formSection(context, h, w, bottomInset)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _formSection(BuildContext c, double h, double w, double bottomInset) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.backgroundColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -35),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.backgroundColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32),
                topRight: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 25,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.only(top: 20),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    w * 0.04, h * 0.02, w * 0.04, bottomInset),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  children: [
                    _title(),
                    InputContainer(children: [
                      CustomInputField(
                        controller: emailController,
                        icon: Icons.email_rounded,
                        iconColor: AppColors.emailIconColor,
                        hintText: 'Email Address',
                        validator: AuthValidators.validateEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const InputDivider(),
                      CustomInputField(
                        controller: passwordController,
                        icon: Icons.lock_rounded,
                        iconColor: AppColors.passwordIconColor,
                        hintText: 'Password',
                        validator: AuthValidators.validatePassword,
                        isPassword: true,
                      ),
                    ]),
                    _forgot(),
                    _actions(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _title() => Column(
        children: [
          Text(
            'Welcome Back',
            style: GoogleFonts.quicksand(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              foreground: Paint()
                ..shader = const LinearGradient(colors: AppColors.textGradient)
                    .createShader(const Rect.fromLTWH(0, 0, 200, 70)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      );

  Widget _forgot() => Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(top: 16, right: 4),
        child: GestureDetector(
          onTap: _handleForgotPassword,
          child: Text(
            'Forgot Password?',
            style: GoogleFonts.quicksand(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );

  Widget _actions() => Column(
        children: [
          const SizedBox(height: 24),
          Obx(() => PrimaryAuthButton(
                text: 'Login To Your Account',
                icon: Icons.login_rounded,
                onPressed: _handleLogin,
                isLoading: loaderController.isLoading.value,
              )),
          const SizedBox(height: 20),
          const OrDivider(),
          const SizedBox(height: 20),
          SecondaryAuthButton(
            text: 'Create New Account',
            icon: Icons.person_add_rounded,
            onPressed: () => Get.off(() => SignUpScreen()),
          ),
        ],
      );
}
