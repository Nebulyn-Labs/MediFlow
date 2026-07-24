import 'package:flutter/material.dart';
import 'package:med_supply_prototype/constants/colors.dart';

/// Animated skeleton container that pulses opacity between 0.35 and 0.8
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8.0,
    this.margin,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(begin: 0.35, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            color: MediColors.surfaceLight.withValues(alpha: _opacityAnimation.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: MediColors.border.withValues(alpha: _opacityAnimation.value * 0.5),
            ),
          ),
        );
      },
    );
  }
}

/// Placeholder for page title and description header
class SkeletonHeader extends StatelessWidget {
  const SkeletonHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 220, height: 28, borderRadius: 6),
        SizedBox(height: 8),
        SkeletonBox(width: 320, height: 16, borderRadius: 4),
      ],
    );
  }
}

/// Placeholder matching standard KPI card layout (Title, count, icon)
class SkeletonKpiCard extends StatelessWidget {
  final double width;
  const SkeletonKpiCard({super.key, this.width = 240});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MediColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBox(width: 120, height: 14, borderRadius: 4),
              SkeletonBox(width: 28, height: 28, borderRadius: 8),
            ],
          ),
          SizedBox(height: 16),
          SkeletonBox(width: 80, height: 32, borderRadius: 6),
          SizedBox(height: 8),
          SkeletonBox(width: 100, height: 12, borderRadius: 4),
        ],
      ),
    );
  }
}

/// Placeholder for rows in tables and list views
class SkeletonTableRow extends StatelessWidget {
  const SkeletonTableRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MediColors.border),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: SkeletonBox(height: 16, borderRadius: 4)),
          SizedBox(width: 16),
          Expanded(child: SkeletonBox(height: 16, borderRadius: 4)),
          SizedBox(width: 16),
          Expanded(child: SkeletonBox(height: 16, borderRadius: 4)),
          SizedBox(width: 16),
          SkeletonBox(width: 60, height: 24, borderRadius: 12),
        ],
      ),
    );
  }
}

/// Generic card container skeleton
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 140});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MediColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 40, height: 40, borderRadius: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 180, height: 16, borderRadius: 4),
                    SizedBox(height: 6),
                    SkeletonBox(width: 120, height: 12, borderRadius: 4),
                  ],
                ),
              ),
              SkeletonBox(width: 70, height: 26, borderRadius: 12),
            ],
          ),
          Spacer(),
          SkeletonBox(width: double.infinity, height: 14, borderRadius: 4),
        ],
      ),
    );
  }
}

/// Skeleton for search bar and filter controls
class SkeletonSearchBar extends StatelessWidget {
  const SkeletonSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: SkeletonBox(height: 44, borderRadius: 8)),
        SizedBox(width: 12),
        SkeletonBox(width: 100, height: 44, borderRadius: 8),
      ],
    );
  }
}

/// Full dashboard skeleton for Facility Overview
class FacilityOverviewSkeleton extends StatelessWidget {
  const FacilityOverviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonHeader(),
              SkeletonBox(width: 160, height: 40, borderRadius: 8),
            ],
          ),
          const SizedBox(height: 24),
          const Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              SkeletonKpiCard(),
              SkeletonKpiCard(),
              SkeletonKpiCard(),
              SkeletonKpiCard(),
            ],
          ),
          const SizedBox(height: 28),
          const SkeletonSearchBar(),
          const SizedBox(height: 20),
          for (int i = 0; i < 5; i++) const SkeletonTableRow(),
        ],
      ),
    );
  }
}

/// Full dashboard skeleton for Admin Overview
class AdminOverviewSkeleton extends StatelessWidget {
  const AdminOverviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonHeader(),
          const SizedBox(height: 24),
          const Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              SkeletonKpiCard(),
              SkeletonKpiCard(),
              SkeletonKpiCard(),
              SkeletonKpiCard(),
            ],
          ),
          const SizedBox(height: 28),
          const SkeletonSearchBar(),
          const SizedBox(height: 20),
          for (int i = 0; i < 5; i++) const SkeletonTableRow(),
        ],
      ),
    );
  }
}

/// Skeleton for Admin Indent Status Page
class AdminIndentStatusSkeleton extends StatelessWidget {
  const AdminIndentStatusSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonHeader(),
          const SizedBox(height: 24),
          const Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              SkeletonKpiCard(),
              SkeletonKpiCard(),
              SkeletonKpiCard(),
            ],
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              SkeletonBox(width: 90, height: 36, borderRadius: 20),
              SizedBox(width: 8),
              SkeletonBox(width: 90, height: 36, borderRadius: 20),
              SizedBox(width: 8),
              SkeletonBox(width: 90, height: 36, borderRadius: 20),
            ],
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < 4; i++) const SkeletonTableRow(),
        ],
      ),
    );
  }
}

/// Skeleton for Admin Indent Approval Page
class AdminIndentApprovalSkeleton extends StatelessWidget {
  const AdminIndentApprovalSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonHeader(),
          const SizedBox(height: 24),
          const SkeletonCard(height: 120),
          const SizedBox(height: 20),
          for (int i = 0; i < 3; i++) ...[
            const SkeletonCard(height: 160),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for AI Forecast Page
class AIForecastSkeleton extends StatelessWidget {
  const AIForecastSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonHeader(),
          const SizedBox(height: 24),
          const Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              SkeletonKpiCard(),
              SkeletonKpiCard(),
              SkeletonKpiCard(),
            ],
          ),
          const SizedBox(height: 24),
          const SkeletonCard(height: 280),
          const SizedBox(height: 24),
          for (int i = 0; i < 3; i++) const SkeletonTableRow(),
        ],
      ),
    );
  }
}

/// Skeleton for Active Indents Page
class ActiveIndentsSkeleton extends StatelessWidget {
  const ActiveIndentsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonHeader(),
              SkeletonBox(width: 140, height: 40, borderRadius: 8),
            ],
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              SkeletonBox(width: 100, height: 36, borderRadius: 20),
              SizedBox(width: 8),
              SkeletonBox(width: 100, height: 36, borderRadius: 20),
            ],
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < 3; i++) ...[
            const SkeletonCard(height: 150),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for Alerts Page
class AlertsSkeleton extends StatelessWidget {
  const AlertsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonHeader(),
          const SizedBox(height: 24),
          const Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              SkeletonKpiCard(),
              SkeletonKpiCard(),
              SkeletonKpiCard(),
            ],
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              SkeletonBox(width: 80, height: 32, borderRadius: 16),
              SizedBox(width: 8),
              SkeletonBox(width: 80, height: 32, borderRadius: 16),
              SizedBox(width: 8),
              SkeletonBox(width: 80, height: 32, borderRadius: 16),
            ],
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < 4; i++) ...[
            const SkeletonCard(height: 100),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for Route Optimization Map Page
class RouteOptimizationMapSkeleton extends StatelessWidget {
  const RouteOptimizationMapSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonHeader(),
          SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 320, height: double.infinity, borderRadius: 12),
                SizedBox(width: 20),
                Expanded(
                  child: SkeletonBox(width: double.infinity, height: double.infinity, borderRadius: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for Daily Logging Page
class DailyLoggingSkeleton extends StatelessWidget {
  const DailyLoggingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonHeader(),
          const SizedBox(height: 24),
          const SkeletonBox(width: double.infinity, height: 60, borderRadius: 10),
          const SizedBox(height: 24),
          for (int i = 0; i < 4; i++) const SkeletonTableRow(),
        ],
      ),
    );
  }
}

/// Skeleton for Indent Creation Page
class IndentCreationSkeleton extends StatelessWidget {
  const IndentCreationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonHeader(),
          const SizedBox(height: 24),
          const SkeletonCard(height: 180),
          const SizedBox(height: 24),
          for (int i = 0; i < 3; i++) const SkeletonTableRow(),
        ],
      ),
    );
  }
}
