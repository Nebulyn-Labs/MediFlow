import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                      onHover: (val) =>
                          setState(() => _isHoveringFacility = val),
                      onTap: () => context.go('/login/facility'),
                    ),
                    const SizedBox(height: 20),
                    _buildRoleCard(
                      title: 'CMS Admin',
                      subtitle: 'Global logistics & redistribution planning',
                      icon: Icons.admin_panel_settings_rounded,
                      gradient: MediColors.primaryGradient,
                      isHovering: _isHoveringAdmin,
                      onHover: (val) => setState(() => _isHoveringAdmin = val),
                      onTap: () => context.go('/login/admin'),
                    ),
                    const SizedBox(height: 48),
                    Consumer(
                      builder: (context, ref, child) {
                        return TextButton.icon(
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Seeding demo data...')));
                            final error = await ref
                                .read(firebaseServiceProvider)
                                .seedDemoData();
                            if (context.mounted) {
                              if (error != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error)));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Demo data seeded ✓')));
                              }
                            }
                          },
                          icon:
                              const Icon(Icons.data_saver_on_rounded, size: 16),
                          label: const Text('Seed Demo Data'),
                          style: TextButton.styleFrom(
                              foregroundColor: MediColors.textMuted),
                        );
                      },
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
    required ValueChanged<bool> onHover,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 420,
          padding: const EdgeInsets.all(24),
          transform:
              Matrix4.translationValues(0.0, isHovering ? -4.0 : 0.0, 0.0),
          decoration: BoxDecoration(
            color: MediColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isHovering
                  ? gradient.colors.first.withValues(alpha: 0.5)
                  : MediColors.border,
              width: 1.5,
            ),
            boxShadow: isHovering
                ? [
                    BoxShadow(
                        color: gradient.colors.first.withValues(alpha: 0.15),
                        blurRadius: 30,
                        offset: const Offset(0, 12))
                  ]
                : [],
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
                    isHovering ? gradient.colors.first : MediColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
