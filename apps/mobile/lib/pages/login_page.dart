import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/providers/installation_provider.dart';
import 'package:mobile/core/controllers/openhab_controller.dart';
import 'package:mobile/pages/legal_pages.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/providers/role_provider.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
 
  bool _isLoading       = false;
  bool _obscurePassword = true;
 
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
 
  Future<void> _onContinue() async {
    final email    = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) return;
 
    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithEmail(email: email, password: password);
      if (mounted) {
        await _createUserDocIfNeeded(); // jaga-jaga akun lama belum ada doc
        await context.read<RoleProvider>().loadRole();
        final installationProvider = context.read<InstallationProvider>();
        await installationProvider.load();

        debugPrint('🏠 installationId = ${installationProvider.installationId}');
        debugPrint('🏠 config = ${installationProvider.config?.openhabUrl}');

        if (installationProvider.config != null) {
          await OpenHABController.instance
              .initializeWithConfig(installationProvider.config!);
        } else {
          OpenHABController.instance.resetConnection();
        }

        context.go('/home');
      }
    } on Exception catch (e) {
      if (mounted) _showError(_friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
 
  Future<void> _onGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final result = await AuthService.signInWithGoogle();
      if (result == null) return; // user cancel
      if (mounted) {
        await _createUserDocIfNeeded(); // jaga-jaga akun lama belum ada doc
        await context.read<RoleProvider>().loadRole();
        final installationProvider = context.read<InstallationProvider>();
        await installationProvider.load();

        debugPrint('🏠 installationId = ${installationProvider.installationId}');
        debugPrint('🏠 config = ${installationProvider.config?.openhabUrl}');

        if (installationProvider.config != null) {
          await OpenHABController.instance
              .initializeWithConfig(installationProvider.config!);
        } else {
          OpenHABController.instance.resetConnection();
        }

        context.go('/home');
      }
    } on Exception catch (e) {
      if (mounted) _showError(_friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
 
  /// Buat document users/{uid} kalau belum ada (jaga-jaga akun yang
  /// signup sebelum sistem role/instalasi ini dipasang). Default role
  /// selalu "user" — TIDAK PERNAH menimpa akun yang sudah ada.
  Future<void> _createUserDocIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await docRef.get();

    if (!doc.exists) {
      await docRef.set({
        'email': user.email ?? '',
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
    if (error.contains('user-not-found'))         return 'Email tidak terdaftar';
    if (error.contains('wrong-password'))         return 'Password salah';
    if (error.contains('invalid-email'))          return 'Format email tidak valid';
    if (error.contains('user-disabled'))          return 'Akun dinonaktifkan';
    if (error.contains('network-request-failed')) return 'Tidak ada koneksi internet';
    if (error.contains('too-many-requests'))      return 'Terlalu banyak percobaan, coba lagi nanti';
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
              Text('Welcome', style: AppTypography.displayLarge),
              const SizedBox(height: AppSpacing.sm),
              _buildSubtitle(),
              const SizedBox(height: AppSpacing.xl2),
              _buildEmailField(),
              const SizedBox(height: AppSpacing.md),
              _buildPasswordField(),
              const SizedBox(height: AppSpacing.sm),
              _buildForgotPassword(),
              const SizedBox(height: AppSpacing.lg),
              _buildContinueButton(),
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
          const TextSpan(text: 'Login to your account or '),
          TextSpan(
            text: 'Sign Up',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.go('/signup'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      style: AppTypography.inputText,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Enter your email',
        hintStyle: AppTypography.inputHint,
        suffixIcon: _emailController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.cancel, color: AppColors.textHint, size: 18),
                onPressed: () {
                  _emailController.clear();
                  setState(() {});
                },
              )
            : null,
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: AppTypography.inputText,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Password',
        hintStyle: AppTypography.inputHint,
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.textHint,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  Widget _buildForgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () => _showForgotPasswordDialog(),
        child: Text(
          'Forgot password?',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showForgotPasswordDialog() {
  final ctrl = TextEditingController();
  bool isSending = false;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Enter your email',
            labelText: 'Email',
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSending ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: isSending
                ? null
                : () async {
                    if (ctrl.text.trim().isEmpty) return;

                    setDialogState(() => isSending = true);
                    try {
                      await AuthService.sendPasswordResetEmail(ctrl.text.trim());
                      if (mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Link reset dikirim ke ${ctrl.text.trim()}',
                            ),
                            backgroundColor: Colors.green[600],
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } on Exception catch (e) {
                      setDialogState(() => isSending = false);
                      if (mounted) _showError(_friendlyError(e.toString()));
                    }
                  },
            child: isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send'),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildContinueButton() {
  final canContinue = _emailController.text.isNotEmpty &&
      _passwordController.text.isNotEmpty;
  return SizedBox(
    width: double.infinity,
    height: AppSpacing.buttonHeight,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
      disabledForegroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        inherit: true,
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
),
      onPressed: (_isLoading || !canContinue) ? null : _onContinue,
      child: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Text('Continue'),
    ),
  );
}

  Widget _buildTermsText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textPrimary.withValues(alpha: 0.6),
          ),
          children: [
            const TextSpan(text: 'By pressing on "Continue with..." you agree\nto our '),
            TextSpan(
              text: 'Terms of Service',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primary,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
              recognizer: TapGestureRecognizer()
              ..onTap = () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TermsOfServicePage()),
              ),
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primary,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
              recognizer: TapGestureRecognizer()
              ..onTap = () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
class _DividerWithText extends StatelessWidget {
  final String text;
  const _DividerWithText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(text,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textHint)),
        ),
        const Expanded(child: Divider(color: AppColors.divider)),
      ],
    );
  }
}
class _SocialButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final String label;

  const _SocialButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: AppTypography.buttonLabelDark),
          ],
        ),
      ),
    );
  }
}