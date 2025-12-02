import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../core/extensions/context_extensions.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/otp_service.dart';
import '../services/email_service.dart';
import '../services/window_service.dart';
import '../screens/dashboard_screen.dart';
import '../widgets/gradient_button.dart';
import '../widgets/window_controls.dart';

class OTPVerificationScreen extends ConsumerStatefulWidget {
  final String email;

  const OTPVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  ConsumerState<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends ConsumerState<OTPVerificationScreen> {
  final _otpController = TextEditingController();
  final _otpService = OTPService();
  final _windowService = WindowService();
  bool _isVerifying = false;
  bool _isResending = false;
  int _resendCooldown = 0;
  int _expirationTime = 0;
  Timer? _cooldownTimer;
  Timer? _expirationTimer;
  String _currentOTP = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _windowService.setOtpWindowSize();
    _startCooldownTimer();
    _startExpirationTimer();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _expirationTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startCooldownTimer() {
    _resendCooldown = _otpService.getRemainingCooldown(widget.email);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _resendCooldown = _otpService.getRemainingCooldown(widget.email);
      });
      if (_resendCooldown == 0) {
        timer.cancel();
      }
    });
  }

  void _startExpirationTimer() {
    _expirationTime = _otpService.getRemainingExpirationTime(widget.email);
    _expirationTimer?.cancel();
    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _expirationTime = _otpService.getRemainingExpirationTime(widget.email);
      });
      if (_expirationTime == 0) {
        timer.cancel();
      }
    });
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;

    final username = parts[0];
    final domain = parts[1];

    if (username.length <= 2) {
      return '${username[0]}***@$domain';
    }

    final maskedUsername = '${username[0]}${'*' * (username.length - 2)}${username[username.length - 1]}';
    return '$maskedUsername@$domain';
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _handleVerifyOTP() async {
    if (_currentOTP.length != 6) {
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorText = null;
    });

    try {
      // Verify OTP via auth provider
      final success = await ref.read(currentUserProvider.notifier).verifyOTP(
            widget.email,
            _currentOTP,
          );

      if (!mounted) return;

      if (success) {
        // Cancel timers before navigation
        _cooldownTimer?.cancel();
        _expirationTimer?.cancel();
        // Navigate to dashboard
        context.pushReplacement(const DashboardScreen());
      } else {
        setState(() {
          _errorText = 'Invalid code. Please try again.';
          _otpController.clear();
          _currentOTP = '';
        });
      }
    } on OTPException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.message;
        _otpController.clear();
        _currentOTP = '';
      });

      // Restart expiration timer if OTP was cleared
      if (e.message.contains('expired') || e.message.contains('Too many')) {
        _startExpirationTimer();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Verification failed. Please try again.';
        _otpController.clear();
        _currentOTP = '';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _handleResendOTP() async {
    if (!_otpService.canResendOTP(widget.email)) {
      return;
    }

    setState(() {
      _isResending = true;
      _errorText = null;
    });

    try {
      // Resend OTP via auth provider
      final success = await ref.read(currentUserProvider.notifier).sendOTP(widget.email);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New code sent to your email'),
            backgroundColor: AppTheme.successColor,
            duration: Duration(seconds: 2),
          ),
        );

        // Restart timers
        _startCooldownTimer();
        _startExpirationTimer();

        // Clear current input
        _otpController.clear();
        setState(() {
          _currentOTP = '';
        });
      }
    } on OTPException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppTheme.warningColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resend code: ${e.toString()}'),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  void _handleEditEmail() {
    Navigator.of(context).pop();
  }

  Future<void> _handlePaste() async {
    if (_isVerifying) return;

    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      final text = clipboardData!.text!;
      final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isNotEmpty) {
        final otp = digitsOnly.length > 6 ? digitsOnly.substring(0, 6) : digitsOnly;
        _otpController.text = otp;
        setState(() {
          _currentOTP = otp;
          _errorText = null;
        });
        // Don't auto-verify on paste - let user click verify button
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final isMetaOrControl = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      if (isMetaOrControl && event.logicalKey == LogicalKeyboardKey.keyV) {
        _handlePaste();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _resendCooldown == 0 && !_isResending;

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: Stack(
        children: [
          Focus(
            onKeyEvent: _handleKeyEvent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20.0, 40.0, 20.0, 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon
                  Icon(
                Icons.mark_email_read_outlined,
                size: 48,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                'Enter Code',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),

              // Masked Email
              Text(
                'Sent to ${_maskEmail(widget.email)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),

              // Edit Email Button
              TextButton(
                onPressed: _handleEditEmail,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                child: const Text('Edit Email', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 12),

              // Expiration Timer
              if (_expirationTime > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppTheme.warningColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 14, color: AppTheme.warningColor),
                      const SizedBox(width: 6),
                      Text(
                        'Expires in ${_formatTime(_expirationTime)}',
                        style: TextStyle(
                          color: AppTheme.warningColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // PIN Code Fields
              PinCodeTextField(
                appContext: context,
                length: 6,
                controller: _otpController,
                keyboardType: TextInputType.number,
                animationType: AnimationType.fade,
                enabled: !_isVerifying,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(8),
                  fieldHeight: 45,
                  fieldWidth: 40,
                  activeFillColor: AppTheme.backgroundColor,
                  inactiveFillColor: AppTheme.backgroundColor,
                  selectedFillColor: AppTheme.backgroundColor,
                  activeColor: AppTheme.primaryColor,
                  inactiveColor: AppTheme.borderColor,
                  selectedColor: AppTheme.primaryColor,
                  errorBorderColor: AppTheme.errorColor,
                ),
                cursorColor: AppTheme.primaryColor,
                animationDuration: const Duration(milliseconds: 200),
                enableActiveFill: true,
                autoFocus: true,
                enablePinAutofill: true,
                beforeTextPaste: (text) {
                  if (text == null) return false;
                  final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
                  return digitsOnly.isNotEmpty;
                },
                onCompleted: (code) {
                  _currentOTP = code;
                  _handleVerifyOTP();
                },
                onChanged: (value) {
                  setState(() {
                    _currentOTP = value;
                    if (value.isNotEmpty) {
                      _errorText = null;
                    }
                  });
                },
              ),

              // Paste button for desktop
              TextButton.icon(
                onPressed: _isVerifying ? null : _handlePaste,
                icon: const Icon(Icons.content_paste, size: 14),
                label: const Text('Paste code', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
              ),

              // Error Text
              if (_errorText != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorText!,
                  style:
                      const TextStyle(color: AppTheme.errorColor, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),

              // Verify Button
              GradientButton(
                onPressed: (_isVerifying || _currentOTP.length != 6)
                    ? null
                    : _handleVerifyOTP,
                child: _isVerifying
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Verify Code',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 12),

              // Resend Button
              TextButton.icon(
                onPressed: canResend ? _handleResendOTP : null,
                icon: _isResending
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(
                  canResend ? 'Resend Code' : 'Resend in ${_resendCooldown}s',
                  style: const TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
              ),

              const SizedBox(height: 8),

              // Info Text
              Text(
                'Didn\'t receive the code? Check your spam folder',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                textAlign: TextAlign.center,
              ),
              ],
            ),
          ),
        ),
          // Window control buttons (minimize, close)
          const Positioned(
            top: 8,
            right: 8,
            child: WindowControls(),
          ),
        ],
      ),
    );
  }
}
