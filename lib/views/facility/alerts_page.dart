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
  const AlertsPage({super.key, required this.facilityId});

  @override
  ConsumerState<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends ConsumerState<AlertsPage> {
  List<_InventoryAlert> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    try {
      final alertMaps = await ref
          .read(firebaseServiceProvider)
          .getAlertsOnce(widget.facilityId);

      final List<_InventoryAlert> alerts = alertMaps.map((data) {
        final item = InventoryItem(
          id: data['stockId'] ?? '',
          medicineName: data['medicineName'] ?? '',
          batchId: data['batchId'] ?? '',
          arrivalDate: DateTime.now(),
          expiryDate: data['expiryDate'] != null
              ? (data['expiryDate'] as Timestamp).toDate()
              : DateTime.now(),
          initialQuantity: data['initialQuantity']?.toInt() ?? 0,
          remainingQuantity: data['qtyRemaining']?.toInt() ?? 0,
          unit: data['unit'] ?? 'units',
          lastUpdated: DateTime.now(),
        );

        final typeStr = data['type'] ?? '';
        _AlertKind kind;
        String title;
        String reason;
        Color color;
        IconData icon;

        final pct = item.initialQuantity > 0
            ? item.remainingQuantity / item.initialQuantity
            : 0.0;
        final percentText = '${(pct * 100).round()}%';
        final daysLeft = item.expiryDate.difference(DateTime.now()).inDays;
        final expiryText = daysLeft < 0
            ? 'expired ${daysLeft.abs()} days ago'
            : 'expires in $daysLeft days';

        if (typeStr == 'expired') {
          kind = _AlertKind.expired;
          title = 'Expired';
          reason = '${item.medicineName} has passed its expiry date and should not be issued.';
          color = MediColors.error;
          icon = Icons.error_rounded;
        } else if (typeStr == 'low_stock') {
          kind = _AlertKind.lowStock;
          title = 'Low Stock';
          reason = '${item.medicineName} is below the low-stock threshold.';
          color = MediColors.error;
          icon = Icons.trending_down_rounded;
        } else if (typeStr == 'wastage_risk') {
          kind = _AlertKind.wastageRisk;
          title = 'Wastage Risk';
          reason = 'High remaining stock is close to expiry, so redistribution should be considered.';
          color = MediColors.warning;
          icon = Icons.warning_amber_rounded;
        } else {
          // expiring_soon
          kind = _AlertKind.expiringSoon;
          title = 'Expiring Soon';
          reason = '${item.medicineName} is within the 30-day expiry window.';
          color = MediColors.warning;
          icon = Icons.schedule_rounded;
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

      if (mounted) {
        setState(() {
          _alerts = alerts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading alerts: $e')));
      }
    }
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _openSmartAnalysis() {
    context.go('/facility/${widget.facilityId}/indent');
  }

  @override
  Widget build(BuildContext context) {
    final expiredAlerts =
        _alerts.where((a) => a.kind == _AlertKind.expired).toList();
    final stockAlerts = _alerts
        .where((a) =>
            a.kind == _AlertKind.lowStock || a.kind == _AlertKind.wastageRisk)
        .toList();
    final expiryAlerts =
        _alerts.where((a) => a.kind == _AlertKind.expiringSoon).toList();

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Alerts',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: MediColors.textPrimary)),
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
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: MediColors.textSecondary),
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
                  builder: (_) => const AIChatPage(role: "Facility Manager")));
        },
        backgroundColor: const Color(0xFF1E3A8A),
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
                            Icon(Icons.check_circle_rounded,
                                size: 64,
                                color:
                                    MediColors.success.withValues(alpha: 0.8)),
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
    return Text(title,
        style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: MediColors.textPrimary));
  }

  Widget _buildAlertCard(_InventoryAlert alert) {
    final isExpired = alert.kind == _AlertKind.expired;

    return Container(
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
          )
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
                    Text(alert.item.medicineName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: MediColors.textPrimary)),
                    Text(alert.item.batchId,
                        style: const TextStyle(
                            fontSize: 12,
                            color: MediColors.textMuted,
                            fontWeight: FontWeight.w600)),
                    _statusBadge(alert),
                  ],
                ),
                const SizedBox(height: 8),
                Text(alert.reason,
                    style: const TextStyle(
                        color: MediColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(alert.detail,
                    style: const TextStyle(
                        color: MediColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 16),
                isExpired
                    ? _buildActionButton('Mark for Disposal', alert.color,
                        () => _handleDisposal(alert))
                    : _buildActionButton('Run Smart AI Stock Analysis',
                        MediColors.primary, _openSmartAnalysis),
              ],
            ),
          ),
        ],
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
            color: alert.color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildActionButton(
      String text, Color accentColor, VoidCallback onTap) {
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
              color: accentColor, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
