import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/firebase_service.dart';
import '../../models/inventory_item.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import '../shared/ai_chat_page.dart';
import '../shared/skeleton_loaders.dart';

enum _AlertKind { expired, wastageRisk, expiringSoon, lowStock }

class _InventoryAlert {
  final InventoryItem item;
  final _AlertKind kind;
  final String title;
  final String reason;
  final String detail;
  final Color color;
  final IconData icon;

  const _InventoryAlert({
    required this.item,
    required this.kind,
    required this.title,
    required this.reason,
    required this.detail,
    required this.color,
    required this.icon,
  });
}

class AlertsPage extends ConsumerStatefulWidget {
  final String facilityId;
  final bool isTabBody;

  const AlertsPage(
      {super.key, required this.facilityId, this.isTabBody = false});

  @override
  ConsumerState<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends ConsumerState<AlertsPage> {
  int _refreshKey = 0;
  late Stream<List<Map<String, dynamic>>> _alertsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(AlertsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.facilityId != widget.facilityId) {
      _initStream();
    }
  }

  void _initStream() {
    _alertsStream =
        ref.read(firebaseServiceProvider).streamAlerts(widget.facilityId);
  }

        final detail = typeStr == 'expired'
            ? '${item.remainingQuantity} ${item.unit} remaining; $expiryText.'
            : '${item.remainingQuantity} / ${item.initialQuantity} ${item.unit} left ($percentText); $expiryText.';

        return _InventoryAlert(
          item: item,
          kind: kind,
          title: title,
          reason: reason,
          detail: detail,
          color: color,
          icon: icon,
        );
      }).toList()..sort((a, b) => _priority(a).compareTo(_priority(b)));

  List<_InventoryAlert> _parseAlerts(List<Map<String, dynamic>> alertMaps) {
    return alertMaps.map((data) {
      final expiryRaw = data['expiryDate'];
      DateTime expiryDate;
      if (expiryRaw is Timestamp) {
        expiryDate = expiryRaw.toDate();
      } else if (expiryRaw is String) {
        expiryDate = DateTime.tryParse(expiryRaw) ?? DateTime.now();
      } else {
        expiryDate = DateTime.now();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading alerts: $e')));
      }

      final detail = typeStr == 'expired'
          ? '${item.remainingQuantity} ${item.unit} remaining; $expiryText.'
          : '${item.remainingQuantity} / ${item.initialQuantity} ${item.unit} left ($percentText); $expiryText.';

      return _InventoryAlert(
        item: item,
        kind: kind,
        title: title,
        reason: reason,
        detail: detail,
        color: color,
        icon: icon,
      );
    }).toList()
      ..sort((a, b) => _priority(a).compareTo(_priority(b)));
  }

  int _priority(_InventoryAlert alert) {
    switch (alert.kind) {
      case _AlertKind.expired:
        return 0;
      case _AlertKind.lowStock:
        return 1;
      case _AlertKind.wastageRisk:
        return 2;
      case _AlertKind.expiringSoon:
        return 3;
    }
  }

  Future<void> _handleDisposal(_InventoryAlert alert) async {
    try {
      await ref
          .read(firebaseServiceProvider)
          .disposeInventory(widget.facilityId, alert.item.medicineName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Marked ${alert.item.medicineName} for safe disposal.')));
        _loadAlerts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _openSmartAnalysis() {
    context.go('/facility/${widget.facilityId}/indent');
  }

  @override
  Widget build(BuildContext context) {
    final expiredAlerts = _alerts
        .where((a) => a.kind == _AlertKind.expired)
        .toList();
    final stockAlerts = _alerts
        .where(
          (a) =>
              a.kind == _AlertKind.lowStock || a.kind == _AlertKind.wastageRisk,
        )
        .toList();
    final expiryAlerts = _alerts
        .where((a) => a.kind == _AlertKind.expiringSoon)
        .toList();

    // App bar and scaffold moved below
    final body = _isLoading
        ? const AlertsSkeleton()
        : SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (expiredAlerts.isNotEmpty) ...[
                  _sectionHeader('Expired Medicines'),
                  const SizedBox(height: 16),
                  ...expiredAlerts.map(_buildAlertCard),
                  const SizedBox(height: 32),
                ],
                if (stockAlerts.isNotEmpty) ...[
                  _sectionHeader('Stock Action Alerts'),
                  const SizedBox(height: 16),
                  ...stockAlerts.map(_buildAlertCard),
                  const SizedBox(height: 32),
                ],
                if (expiryAlerts.isNotEmpty) ...[
                  _sectionHeader('Expiry Watch'),
                  const SizedBox(height: 16),
                  ...expiryAlerts.map(_buildAlertCard),
                ],
                if (_alerts.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 96),
                      child: Column(
                        children: [
                          ExcludeSemantics(
                            child: Icon(Icons.check_circle_rounded,
                                size: 64,
                                color:
                                    MediColors.success.withValues(alpha: 0.8)),
                          ),
                          const SizedBox(height: 16),
                          const Text('No active alerts detected.',
                              style: TextStyle(
                                  color: MediColors.textSecondary,
                                  fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        if (widget.isTabBody) {
          return RefreshIndicator(
            onRefresh: () async => _manualRefresh(),
            child: body,
          );
        }

        return Scaffold(
          backgroundColor: MediColors.bg,
          appBar: _buildAppBar(),
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
          body: body,
        );
      },
    );
  }

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Alerts',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: MediColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: MediColors.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.facilityId.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  color: MediColors.info,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: MediColors.textSecondary,
            ),
            onPressed: _loadAlerts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AIChatPage(role: "Facility Manager"),
            ),
          );
        },
        backgroundColor: const Color(0xFF1E3A8A),
        tooltip: 'Open MediFlow AI Assistant',
        child: const Icon(Icons.auto_awesome, color: Colors.white),
      ),
      body: _isLoading
          ? const AlertsSkeleton()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (expiredAlerts.isNotEmpty) ...[
                    _sectionHeader('Expired Medicines'),
                    const SizedBox(height: 16),
                    ...expiredAlerts.map(_buildAlertCard),
                    const SizedBox(height: 32),
                  ],
                  if (stockAlerts.isNotEmpty) ...[
                    _sectionHeader('Stock Action Alerts'),
                    const SizedBox(height: 16),
                    ...stockAlerts.map(_buildAlertCard),
                    const SizedBox(height: 32),
                  ],
                  if (expiryAlerts.isNotEmpty) ...[
                    _sectionHeader('Expiry Watch'),
                    const SizedBox(height: 16),
                    ...expiryAlerts.map(_buildAlertCard),
                  ],
                  if (_alerts.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 96),
                        child: Column(
                          children: [
                            ExcludeSemantics(
                              child: Icon(Icons.check_circle_rounded,
                                  size: 64,
                                  color: MediColors.success
                                      .withValues(alpha: 0.8)),
                            ),
                            const SizedBox(height: 16),
                            const Text('No active alerts detected.',
                                style: TextStyle(
                                    color: MediColors.textSecondary,
                                    fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: MediColors.textPrimary,
      ),
    );
  }

  Widget _buildAlertCard(_InventoryAlert alert) {
    final isExpired = alert.kind == _AlertKind.expired;

    return Semantics(
      label:
          '${alert.title} alert for ${alert.item.medicineName}, batch ${alert.item.batchId}. ${alert.reason} ${alert.detail}',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MediColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: alert.color.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: alert.color.withValues(alpha: 0.05),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: alert.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(alert.icon, color: alert.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          alert.item.medicineName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: MediColors.textPrimary,
                          ),
                        ),
                        Text(
                          alert.item.batchId,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MediColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _statusBadge(alert),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      alert.reason,
                      style: const TextStyle(
                        color: MediColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.detail,
                      style: const TextStyle(
                        color: MediColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    isExpired
                        ? _buildActionButton(
                            'Mark for Disposal',
                            alert.color,
                            () => _handleDisposal(alert),
                          )
                        : _buildActionButton(
                            'Run Smart AI Stock Analysis',
                            MediColors.primary,
                            _openSmartAnalysis,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(_InventoryAlert alert) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: alert.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        alert.title,
        style: TextStyle(
          color: alert.color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String text,
    Color accentColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accentColor.withValues(alpha: 0.5)),
          color: accentColor.withValues(alpha: 0.08),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: accentColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
