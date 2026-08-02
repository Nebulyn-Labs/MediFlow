import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/firebase_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(firebaseServiceProvider).sendPasswordReset(email);
    } catch (e) {
      // Ignore exceptions to prevent email enumeration
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "If an account exists for that email, we've sent a reset link.")),
        );
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: MediColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: MediColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_reset_rounded,
                  size: 56,
                  color: MediColors.primary,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Reset Password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: MediColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your email address and we\'ll send you a link to reset your password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MediColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: MediColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined,
                        color: MediColors.textMuted, size: 20),
                  ),
                  onSubmitted: (_) => _resetPassword(),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: MediColors.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: MediColors.primary.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _resetPassword,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Send Reset Link',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
