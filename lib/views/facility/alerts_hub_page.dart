import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:med_supply_prototype/constants/colors.dart';

import 'alerts_page.dart';
import '../shared/notification_feed_widget.dart';
import '../shared/ai_chat_page.dart';

class AlertsHubPage extends ConsumerWidget {
  final String facilityId;

  const AlertsHubPage({super.key, required this.facilityId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: MediColors.bg,
        appBar: AppBar(
          title: Row(
            children: [
              const Text('Alerts & Notifications',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: MediColors.textPrimary)),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: MediColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  facilityId.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12,
                      color: MediColors.info,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            indicatorColor: MediColors.primary,
            labelColor: MediColors.primary,
            unselectedLabelColor: MediColors.textSecondary,
            dividerColor: MediColors.border,
            tabs: [
              Tab(
                  text: 'Live Feed',
                  icon: Icon(Icons.notifications_active_rounded)),
              Tab(
                  text: 'Inventory Health',
                  icon: Icon(Icons.health_and_safety_rounded)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            NotificationFeedWidget(facilityId: facilityId),
            AlertsPage(facilityId: facilityId, isTabBody: true),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const AIChatPage(role: "Facility Manager")));
          },
          backgroundColor: const Color(0xFF1E3A8A),
          tooltip: 'Open MediFlow AI Assistant',
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
      ),
    );
  }
}
