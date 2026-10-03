import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';


class OtpPage extends StatefulWidget {
  final String email;

  const OtpPage({super.key, required this.email});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {


  static const int _otpLength = 6;

  final TextEditingController _hiddenController = TextEditingController();
  final FocusNode _hiddenFocusNode = FocusNode();

  final bool _isLoading = false;
  bool _isKeyboardVisible = false;

  String get _otpValue => _hiddenController.text;
  bool get _isComplete => _otpValue.length == _otpLength;

  @override
  void initState() {
    super.initState();
    _hiddenFocusNode.addListener(
      () => setState(() => _isKeyboardVisible = _hiddenFocusNode.hasFocus),
    );
    _hiddenController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FocusScope.of(context).requestFocus(_hiddenFocusNode),
    );
  }

  @override
  void dispose() {
    _hiddenController.dispose();
    _hiddenFocusNode.dispose();
    super.dispose();
  }

  void _onContinue() {
    if (!_isComplete) return;
    context.go('/home');
  }

  void _onResend() {
  }

  void _requestFocus() {
    FocusScope.of(context).requestFocus(_hiddenFocusNode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _buildHeroImage(),
          _buildBlurOverlay(),
          _buildLogo(),
          _buildHiddenTextField(),
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

  Widget _buildBlurOverlay() {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _isKeyboardVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(color: Colors.black.withValues(alpha: 0.3)),
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

  Widget _buildHiddenTextField() {
    return Positioned(
      left: -500,
      top: 0,
      child: SizedBox(
        width: 1,
        height: 1,
        child: TextField(
          controller: _hiddenController,
          focusNode: _hiddenFocusNode,
          keyboardType: TextInputType.number,
          maxLength: _otpLength,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.transparent, fontSize: 1),
          cursorColor: Colors.transparent,
          cursorWidth: 0,
          decoration: const InputDecoration(
            border: InputBorder.none,
            counterText: '',
          ),
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
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(),
              const SizedBox(height: 8),
              _buildSubtitle(),
              const SizedBox(height: 28),
              _buildOtpRow(),
              const SizedBox(height: 16),
              _buildResendText(),
              const SizedBox(height: 28),
              _buildContinueButton(),
              const SizedBox(height: 16),
              _buildTermsText(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Text('Enter the Verification code', style: AppTypography.headingLarge);
  }

  Widget _buildSubtitle() {
    return Text(
      'A verification code has been sent to\n${widget.email}',
      style: AppTypography.bodyMedium.copyWith(
        color: AppColors.textPrimary.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildOtpRow() {
    return GestureDetector(
      onTap: _requestFocus,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildOtpBox(0),
          const SizedBox(width: 8),
          _buildOtpBox(1),
          const SizedBox(width: 8),
          _buildOtpBox(2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '—',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textHint),
            ),
          ),
          _buildOtpBox(3),
          const SizedBox(width: 8),
          _buildOtpBox(4),
          const SizedBox(width: 8),
          _buildOtpBox(5),
        ],
      ),
    );
  }

  Widget _buildResendText() {
    return RichText(
      text: TextSpan(
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.textPrimary.withValues(alpha: 0.6),
        ),
        children: [
          const TextSpan(text: "Didn't receive a code? "),
          TextSpan(
            text: 'Resend',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()..onTap = _onResend,
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: (_isComplete && !_isLoading) ? _onContinue : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Continue',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildTermsText() {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textPrimary.withValues(alpha: 0.6),
          ),
          children: [
            const TextSpan(
              text: 'By pressing on "Continue with..." you agree\nto our ',
            ),
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
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final char = index < _otpValue.length ? _otpValue[index] : '';
    final isActive = _hiddenFocusNode.hasFocus &&
        index == _otpValue.length.clamp(0, _otpLength - 1) &&
        (index == _otpValue.length || _otpValue.isEmpty);

    return Expanded(
      child: GestureDetector(
        onTap: _requestFocus,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.backgroundInput,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? AppColors.otpBoxActive : AppColors.otpBoxInactive,
              width: isActive ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: char.isNotEmpty
              ? Text(
                  char,
                  style: AppTypography.headingSmall.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                )
              : isActive
                  ? Container(width: 2, height: 20, color: AppColors.otpBoxActive)
                  : const SizedBox.shrink(),
        ),
      ),
    );
  }
}