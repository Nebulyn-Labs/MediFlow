import 'package:flutter/foundation.dart';
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
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Database Reseed'),
        content: const Text(
          'Warning: This deletes all live data (facilities, inventory, usage logs, and requests) and repopulates demo data. This action cannot be undone.\n\nAre you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Wipe & Reseed'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final error = await ref.read(firebaseServiceProvider).seedDemoData();
      if (error != null) {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      } else {
        messenger.showSnackBar(
          const SnackBar(
              content: Text(
                  'Database seeded ✓ Use rampur@mediflow.com / password123')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
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
        final fac =
            await ref.read(firebaseServiceProvider).getFacilityByEmail(email);

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;

          if (isNarrow) {
            return SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBrandHeader(isFacility, accentColor, gradient,
                        compact: true),
                    const SizedBox(height: 32),
                    _buildLoginForm(gradient, accentColor, compact: true),
                  ],
                ),
              ),
            );
          }

          return Row(
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
                    child: _buildBrandHeader(isFacility, accentColor, gradient,
                        compact: false),
                  ),
                ),
              ),

              // Right: Login form
              Expanded(
                child: Center(
                  child: _buildLoginForm(gradient, accentColor, compact: false),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBrandHeader(
      bool isFacility, Color accentColor, Gradient gradient,
      {required bool compact}) {
    final iconBoxSize = compact ? 88.0 : 120.0;
    final iconSize = compact ? 40.0 : 56.0;
    final titleSize = compact ? 22.0 : 28.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(compact ? 24 : 32),
            boxShadow: [
              BoxShadow(
                  color: accentColor.withValues(alpha: 0.3),
                  blurRadius: compact ? 24 : 40,
                  spreadRadius: compact ? 3 : 5),
            ],
          ),
          child: Icon(
            isFacility
                ? Icons.vaccines_rounded
                : Icons.admin_panel_settings_rounded,
            size: iconSize,
            color: Colors.white,
          ),
        ),
        SizedBox(height: compact ? 20 : 32),
        Text(
          isFacility ? 'Facility Portal' : 'Admin Portal',
          style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              color: accentColor),
        ),
        if (!compact) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              isFacility
                  ? 'Manage daily logs, track inventory, and forecast indents using AI.'
                  : 'Monitor global stock levels and optimize redistribution routes.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: MediColors.textSecondary, fontSize: 14, height: 1.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoginForm(Gradient gradient, Color accentColor,
      {required bool compact}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 24 : 40),
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
              style: TextStyle(color: MediColors.textSecondary, fontSize: 14),
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
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push('/forgot-password'),
                style: TextButton.styleFrom(
                  foregroundColor: MediColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
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
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (kDebugMode) ...[
                  TextButton.icon(
                    onPressed: _isLoading ? null : _seedDatabase,
                    icon: const Icon(Icons.dataset_rounded, size: 16),
                    label: const Text('Seed DB'),
                    style: TextButton.styleFrom(
                        foregroundColor: MediColors.textMuted),
                  ),
                  const SizedBox(width: 8),
                ],
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
    );
  }
}
