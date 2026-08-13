import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../../services/firebase_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import 'dart:math' as math;

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  bool _isHoveringFacility = false;
  bool _isHoveringAdmin = false;
  bool _isFocusedFacility = false;
  bool _isFocusedAdmin = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      body: Row(
        children: [
          // Left: Animated brand side
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  // Animated floating orbs
                  ...List.generate(3, (i) {
                    return AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final offset = math.sin(
                                _pulseController.value * math.pi * 2 +
                                    i * 1.2) *
                            20;
                        return Positioned(
                          top: 100.0 + i * 180.0 + offset,
                          left: 50.0 + i * 80.0,
                          child: Container(
                            width: 200 + i * 60.0,
                            height: 200 + i * 60.0,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  MediColors.primarySubtle,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }),
                  // Content
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: MediColors.primaryGradient,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    MediColors.primary.withValues(alpha: 0.4),
                                blurRadius: 40,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.health_and_safety_rounded,
                              size: 52, color: Colors.white),
                        ),
                        const SizedBox(height: 32),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Colors.white, Color(0xFFA5B4FC)],
                          ).createShader(bounds),
                          child: const Text(
                            'MediFlow',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Intelligent Medical Supply Chain',
                          style: TextStyle(
                            fontSize: 16,
                            color: MediColors.textMuted,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 48),
                        // Stats row
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStat('AI-Powered', 'Forecasting'),
                            Container(
                                width: 1,
                                height: 40,
                                color: MediColors.border,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 32)),
                            _buildStat('Real-time', 'Analytics'),
                            Container(
                                width: 1,
                                height: 40,
                                color: MediColors.border,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 32)),
                            _buildStat('Smart', 'Redistribution'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right: Role selection
          Expanded(
            child: Container(
              color: MediColors.bg,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Welcome Back',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: MediColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose your portal to continue',
                      style: TextStyle(
                          fontSize: 15, color: MediColors.textSecondary),
                    ),
                    const SizedBox(height: 48),
                    _buildRoleCard(
                      title: 'Facility Head',
                      subtitle: 'Manage inventory, daily logs & AI indents',
                      icon: Icons.local_hospital_rounded,
                      gradient: const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF14B8A6)]),
                      isHovering: _isHoveringFacility,
                      isFocused: _isFocusedFacility,
                      onHover: (val) =>
                          setState(() => _isHoveringFacility = val),
                      onFocusChange: (val) =>
                          setState(() => _isFocusedFacility = val),
                      onTap: () => context.go('/login/facility'),
                    ),
                    const SizedBox(height: 20),
                    _buildRoleCard(
                      title: 'CMS Admin',
                      subtitle: 'Global logistics & redistribution planning',
                      icon: Icons.admin_panel_settings_rounded,
                      gradient: MediColors.primaryGradient,
                      isHovering: _isHoveringAdmin,
                      isFocused: _isFocusedAdmin,
                      onHover: (val) => setState(() => _isHoveringAdmin = val),
                      onFocusChange: (val) =>
                          setState(() => _isFocusedAdmin = val),
                      onTap: () => context.go('/login/admin'),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 48),
                      Consumer(
                        builder: (context, ref, child) {
                          return TextButton.icon(
                            onPressed: () async {
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
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('Wipe & Reseed'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed != true) return;

                              messenger.showSnackBar(const SnackBar(
                                  content: Text('Seeding demo data...')));
                              final error = await ref
                                  .read(firebaseServiceProvider)
                                  .seedDemoData();
                              if (error != null) {
                                messenger.showSnackBar(
                                    SnackBar(content: Text(error)));
                              } else {
                                messenger.showSnackBar(const SnackBar(
                                    content: Text('Demo data seeded ✓')));
                              }
                            },
                            icon: const Icon(Icons.data_saver_on_rounded,
                                size: 16),
                            label: const Text('Seed Demo Data'),
                            style: TextButton.styleFrom(
                                foregroundColor: MediColors.textMuted),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String top, String bottom) {
    return Column(
      children: [
        Text(top,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: MediColors.primary)),
        const SizedBox(height: 4),
        Text(bottom,
            style: const TextStyle(fontSize: 12, color: MediColors.textMuted)),
      ],
    );
  }

  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required LinearGradient gradient,
    required bool isHovering,
    required bool isFocused,
    required ValueChanged<bool> onHover,
    required ValueChanged<bool> onFocusChange,
    required VoidCallback onTap,
  }) {
    // The card is a real button: a focusable, activatable widget (InkWell
    // inside FocusableActionDetector) so keyboard users can Tab to it, press
    // Enter or Space, and screen readers announce it as a button. A visible
    // focus ring reuses the existing hover styling so the affordance is
    // obvious without depending on the mouse. The outer Semantics widget
    // gives a clean single label that reads "Facility Head, Manage
    // inventory, daily logs & AI indents, button" instead of the bare text
    // labels the previous GestureDetector surfaced.
    final isActive = isHovering || isFocused;
    final borderColor = isActive
        ? gradient.colors.first.withValues(alpha: 0.5)
        : MediColors.border;
    final shadow = isActive
        ? [
            BoxShadow(
                color: gradient.colors.first.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 12)),
          ]
        : const <BoxShadow>[];

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: MouseRegion(
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        cursor: SystemMouseCursors.click,
        child: FocusableActionDetector(
          onFocusChange: onFocusChange,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: 420,
              padding: const EdgeInsets.all(24),
              transform:
                  Matrix4.translation(Vector3(0.0, isActive ? -4.0 : 0.0, 0.0)),
              decoration: BoxDecoration(
                color: MediColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 1.5),
                boxShadow: shadow,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 28, color: Colors.white),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: MediColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 13, color: MediColors.textSecondary)),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color:
                        isActive ? gradient.colors.first : MediColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
