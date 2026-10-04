import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/providers/role_provider.dart';
import '../../../../core/providers/installation_provider.dart';
import '../../../../core/controllers/openhab_controller.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _nameController            = TextEditingController();
  final _emailController           = TextEditingController();
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading       = false;
  bool _obscurePassword = true;
  bool _obscureConfirm  = true;

  bool get _isComplete =>
      _nameController.text.isNotEmpty &&
      _emailController.text.isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onSignUp() async {
    if (!_isComplete) return;

    final password        = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password != confirmPassword) {
      _showError('Password tidak cocok');
      return;
    }
    if (password.length < 6) {
      _showError('Password minimal 6 karakter');
      return;
    }

    // Ambil dependensi SEBELUM await pertama (hindari BuildContext async gap).
    final roleProvider         = context.read<RoleProvider>();
    final installationProvider = context.read<InstallationProvider>();
    final router               = GoRouter.of(context);

    setState(() => _isLoading = true);
    try {
      await AuthService.signUpWithEmail(
        name:     _nameController.text.trim(),
        email:    _emailController.text.trim(),
        password: password,
      );
      if (!mounted) return;

      await _createUserDocIfNeeded();
      await roleProvider.loadRole();
      await installationProvider.load();
      if (!mounted) return;

      // User baru pasti belum ada installationId (admin belum assign),
      // jadi controller-nya di-reset, bukan initializeWithConfig.
      OpenHABController.instance.resetConnection();

      router.go('/home');
    } on Exception catch (e) {
      if (mounted) _showError(_friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Bikin document users/{uid} otomatis pas pertama kali signup.
  /// Default role selalu "user" — admin yang assign role/instalasi
  /// belakangan lewat User Management page.
  Future<void> _createUserDocIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await docRef.get();

    if (!doc.exists) {
      await docRef.set({
        'email': user.email ?? _emailController.text.trim(),
        'role': 'user',
        'installationId': null,
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _friendlyError(String error) {
    if (error.contains('email-already-in-use')) return 'Email sudah terdaftar';
    if (error.contains('invalid-email'))        return 'Format email tidak valid';
    if (error.contains('weak-password'))        return 'Password terlalu lemah';
    if (error.contains('network-request-failed')) return 'Tidak ada koneksi internet';
    return 'Terjadi kesalahan, coba lagi';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildHeroImage(),
          _buildGradientOverlay(),
          _buildLogo(),
          _buildBottomCard(),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    return Positioned.fill(
      child: Image.asset(
        'assets/images/bg_house.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.2),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x55000000), Color(0x00000000)],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Image.asset(
          'assets/icons/logo_philoin.png',
          height: 53,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
          boxShadow: [
            BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, -4)),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl2, AppSpacing.xl3, AppSpacing.xl2, AppSpacing.xl3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Create Account', style: AppTypography.displayLarge),
              const SizedBox(height: AppSpacing.sm),
              _buildSubtitle(),
              const SizedBox(height: AppSpacing.xl2),
              _buildNameField(),
              const SizedBox(height: AppSpacing.md),
              _buildEmailField(),
              const SizedBox(height: AppSpacing.md),
              _buildPasswordField(),
              const SizedBox(height: AppSpacing.md),
              _buildConfirmPasswordField(),
              const SizedBox(height: AppSpacing.xl2),
              _buildSignUpButton(),
              const SizedBox(height: AppSpacing.lg),
              _buildTermsText(),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    return RichText(
      text: TextSpan(
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textPrimary.withValues(alpha: 0.8),
        ),
        children: [
          const TextSpan(text: 'Already have an account? '),
          TextSpan(
            text: 'Login',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.go('/login'),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() => _FormTextField(
        controller: _nameController,
        hintText: 'Full name',
        keyboardType: TextInputType.name,
        onChanged: (_) => setState(() {}),
      );

  Widget _buildEmailField() => _FormTextField(
        controller: _emailController,
        hintText: 'Email address',
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => setState(() {}),
      );

  Widget _buildPasswordField() => _FormTextField(
        controller: _passwordController,
        hintText: 'Password',
        obscureText: _obscurePassword,
        onChanged: (_) => setState(() {}),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.textHint,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      );

  Widget _buildConfirmPasswordField() => _FormTextField(
        controller: _confirmPasswordController,
        hintText: 'Confirm password',
        obscureText: _obscureConfirm,
        onChanged: (_) => setState(() {}),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.textHint,
            size: 20,
          ),
          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      );

  Widget _buildSignUpButton() {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.buttonHeight,
      child: ElevatedButton(
        onPressed: (_isComplete && !_isLoading) ? _onSignUp : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Text('Sign Up'),
      ),
    );
  }

  Widget _buildTermsText() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.textPrimary.withValues(alpha: 0.6),
        ),
        children: [
          const TextSpan(text: 'By signing up you agree to our '),
          TextSpan(
            text: 'Terms of Service',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
            recognizer: TapGestureRecognizer()..onTap = () {},
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
            recognizer: TapGestureRecognizer()..onTap = () {},
          ),
        ],
      ),
    );
  }
}

class _FormTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  const _FormTextField({
    required this.controller,
    required this.hintText,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.onChanged,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: AppTypography.inputText,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTypography.inputHint,
        suffixIcon: suffixIcon,
      ),
    );
  }
}