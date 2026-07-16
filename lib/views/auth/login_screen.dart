import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/firebase_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  bool _obscurePassword = true;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _seedDatabase() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(firebaseServiceProvider).seedDemoData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Database seeded ✓ Use rampur@mediflow.com / password123')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(firebaseServiceProvider).login(
            _emailController.text.trim(),
            _passwordController.text,
          );
      if (widget.role == 'facility') {
        final email = _emailController.text.trim();
        final facilityId =
            email.toLowerCase().replaceAll('@', '_').replaceAll('.', '_');
        final fac =
            await ref.read(firebaseServiceProvider).getFacility(facilityId);

        if (fac != null) {
          if (mounted) context.go('/facility/${fac.id}/overview');
        } else {
          throw Exception(
              "No facility found for this account ($email). Please ensure you have seeded the database.");
        }
      } else {
        if (mounted) context.go('/admin/overview');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Login failed: ${e.toString().split(']').last.trim()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFacility = widget.role == 'facility';
    final accentColor = isFacility ? MediColors.teal : MediColors.primary;
    final gradient =
        isFacility ? MediColors.cyanGradient : MediColors.primaryGradient;

    return Scaffold(
      backgroundColor: MediColors.bg,
      body: Row(
        children: [
          // Left: Brand illustration
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [MediColors.bg, MediColors.surface],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                              color: accentColor.withValues(alpha: 0.3),
                              blurRadius: 40,
                              spreadRadius: 5),
                        ],
                      ),
                      child: Icon(
                        isFacility
                            ? Icons.vaccines_rounded
                            : Icons.admin_panel_settings_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      isFacility ? 'Facility Portal' : 'Admin Portal',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: accentColor),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 360,
                      child: Text(
                        isFacility
                            ? 'Manage daily logs, track inventory, and forecast indents using AI.'
                            : 'Monitor global stock levels and optimize redistribution routes.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: MediColors.textSecondary,
                            fontSize: 14,
                            height: 1.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Right: Login form
          Expanded(
            child: Center(
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
                    const Text(
                      'Sign In',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: MediColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your credentials to continue',
                      style: TextStyle(
                          color: MediColors.textSecondary, fontSize: 14),
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
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: MediColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline_rounded,
                            color: MediColors.textMuted, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: MediColors.textMuted,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 52,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: gradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: accentColor.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6)),
                          ],
                        ),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Sign In',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: _isLoading ? null : _seedDatabase,
                          icon: const Icon(Icons.dataset_rounded, size: 16),
                          label: const Text('Seed DB'),
                          style: TextButton.styleFrom(
                              foregroundColor: MediColors.textMuted),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => context.go('/'),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Back'),
                          style: TextButton.styleFrom(
                              foregroundColor: MediColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
