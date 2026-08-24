import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/inventory_item.dart';
import '../../services/firebase_service.dart';
import '../../services/simulation_service.dart';
import '../../services/csv_export_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';
import '../shared/confirm_logout_dialog.dart';
import '../shared/skeleton_loaders.dart';
import '../../utils/date_formatter.dart';

class FacilityOverview extends ConsumerStatefulWidget {
  final String facilityId;
  const FacilityOverview({super.key, required this.facilityId});

  @override
  ConsumerState<FacilityOverview> createState() => _FacilityOverviewState();
}

class _FacilityOverviewState extends ConsumerState<FacilityOverview> {
  bool _isSimulating = false;
  final GlobalKey _inventoryTableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final colors = context.mediTheme;
    final inventoryStream =
        ref.watch(firebaseServiceProvider).streamInventory(widget.facilityId);

    return StreamBuilder<List<InventoryItem>>(
      stream: inventoryStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: colors.background,
            body: const FacilityOverviewSkeleton(),
          );
        }
        final inventory = snapshot.data ?? [];
        final alertCount = inventory.where((i) => i.hasAlert).length;

        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: const Text('Dashboard'),
            actions: [
              // Live Alert Bell
              PopupMenuButton<String>(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.notifications_outlined,
                        color: colors.textSecondary),
                    if (alertCount > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                              color: colors.error, shape: BoxShape.circle),
                          child: Center(
                              child: Text('$alertCount',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700))),
                        ),
                      ),
                  ],
                ),
                tooltip: 'Alerts',
                itemBuilder: (context) {
                  final alerts = <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                        value: 'h',
                        enabled: false,
                        child: Text('Live Alerts',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary))),
                    const PopupMenuDivider(),
                  ];
                  final lowItems = inventory
                      .where((i) => i.status == ItemStatus.lowStock)
                      .toList();
                  // Expiring-soon popup: only items that are truly expiring
                  // soon, NOT already expired (those are listed separately).
                  final expiringItems = inventory
                      .where((i) =>
                          i.status == ItemStatus.expiringSoon ||
                          i.status == ItemStatus.wastageRisk ||
                          i.status == ItemStatus.expired)
                      .toList();
                  for (var item in lowItems) {
                    alerts.add(PopupMenuItem<String>(
                        value: 'l_${item.medicineName}',
                        child: ListTile(
                          leading: Icon(Icons.warning_rounded,
                              color: colors.error, size: 20),
                          title: Text('${item.medicineName} critically low',
                              style: TextStyle(
                                  fontSize: 13, color: colors.textPrimary)),
                          subtitle: Text('${item.remainingQuantity} units left',
                              style: TextStyle(
                                  fontSize: 11, color: colors.textMuted)),
                          trailing: TextButton(
                            onPressed: () async {
                              try {
                                await ref.read(firebaseServiceProvider).restock(
                                    widget.facilityId, item.medicineName, 500);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Restocked 500 units of ${item.medicineName}')));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Failed to restock: Inventory record not found for ${item.medicineName}'),
                                          backgroundColor: MediColors.error));
                                }
                              }
                            },
                            child: const Text('Restock',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: MediColors.primary)),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        )));
                  }
                  for (var item in expiringItems) {
                    final d = item.expiryDate.difference(DateTime.now()).inDays;
                    final isExpired = d < 0;
                    alerts.add(PopupMenuItem<String>(
                        value: 'e_${item.medicineName}',
                        child: ListTile(
                          leading: Icon(
                              isExpired
                                  ? Icons.error_outline_rounded
                                  : Icons.schedule_rounded,
                              color: isExpired ? colors.error : colors.warning,
                              size: 20),
                          title: Text(
                              isExpired
                                  ? '${item.medicineName} has EXPIRED'
                                  : '${item.medicineName} expires in $d d',
                              style: TextStyle(
                                  fontSize: 13, color: colors.textPrimary)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        )));
                  }
                  return alerts;
                },
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                child: const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: CircleAvatar(
                      radius: 18,
                      backgroundColor: MediColors.surfaceLight,
                      child: Icon(Icons.person_rounded,
                          color: MediColors.textSecondary, size: 20)),
                ),
                itemBuilder: (c) => [
                  const PopupMenuItem(
                      value: 'out',
                      child: ListTile(
                          leading: Icon(Icons.logout_rounded,
                              color: MediColors.error),
                          title: Text('Sign Out'),
                          dense: true,
                          contentPadding: EdgeInsets.zero)),
                ],
                onSelected: (v) async {
                  if (v == 'out') {
                    await signOutWithConfirmation(context);
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Greeting
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Facility Dashboard',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Real-time inventory monitoring and insights',
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 14)),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _isSimulating
                          ? null
                          : () async {
                              final confirmed =
                                  await confirmSimulateAnalytics(context);
                              if (!confirmed || !mounted) return;

                              setState(() => _isSimulating = true);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Simulating 30 days of usage data...')));
                              }
                              try {
                                final firebase =
                                    ref.read(firebaseServiceProvider);
                                final fac = await firebase
                                    .getFacility(widget.facilityId);
                                if (fac == null) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: const Text(
                                          'Simulation failed. Please try again.'),
                                      backgroundColor: colors.error,
                                    ));
                                  }
                                  if (mounted) {
                                    setState(() => _isSimulating = false);
                                  }
                                  return;
                                }

                                await ref
                                    .read(simulationServiceProvider)
                                    .runFullSimulation(
                                        widget.facilityId, fac.type);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Simulation complete! Analytics ready.')));
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: const Text(
                                        'Simulation failed. Please try again.'),
                                    backgroundColor: colors.error,
                                  ));
                                }
                              }
                              if (mounted) {
                                setState(() => _isSimulating = false);
                              }
                            },
                      icon: _isSimulating
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: colors.primary))
                          : const Icon(Icons.analytics_outlined),
                      label: Text(
                          _isSimulating ? 'Running...' : 'Simulate Analytics'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // KPI Cards
                Builder(
                  builder: (context) {
                    // All counts now derived from the centralized
                    // ItemStatus getter — no inline threshold duplication.
                    final expired = inventory
                        .where((i) => i.status == ItemStatus.expired)
                        .length;
                    final wastageRisk = inventory
                        .where((i) => i.status == ItemStatus.wastageRisk)
                        .length;
                    final lowStock = inventory
                        .where((i) => i.status == ItemStatus.lowStock)
                        .length;
                    final unhealthy = inventory.where((i) => i.hasAlert).length;
                    final healthy = (inventory.length - unhealthy)
                        .clamp(0, inventory.length);
                    final stockHealthText = inventory.isEmpty
                        ? 'No stock'
                        : '$healthy / ${inventory.length} healthy';
                    final stockHealthColor = unhealthy == 0
                        ? colors.success
                        : colors.warning;
                    final stockHealthGradient = unhealthy == 0
                        ? colors.healthyKpiGradient
                        : colors.warningKpiGradient;

                    return Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      children: [
                        _buildKpiCard(
                            'Total Meds in Inv',
                            '${inventory.length}',
                            Icons.medication_rounded,
                            colors.info,
                            colors.infoKpiGradient,
                            null,
                            colors),
                        _buildKpiCard(
                            'Stock Health',
                            stockHealthText,
                            Icons.health_and_safety_rounded,
                            stockHealthColor,
                            stockHealthGradient, () {
                          context.go('/facility/${widget.facilityId}/alerts');
                        }, colors),
                        _buildKpiCard(
                            'Expired',
                            '$expired',
                            Icons.error_outline_rounded,
                            colors.error,
                            colors.errorKpiGradient,
                            () {
                          context.go('/facility/${widget.facilityId}/alerts');
                        }, colors),
                        _buildKpiCard(
                            'Wastage Risk',
                            '$wastageRisk',
                            Icons.warning_amber_rounded,
                            const Color(0xFFF59E0B),
                            colors.warningKpiGradient,
                            () {
                          context.go('/facility/${widget.facilityId}/alerts');
                        }, colors),
                        _buildKpiCard(
                            'Low Stock',
                            '$lowStock',
                            Icons.trending_down_rounded,
                            colors.error,
                            colors.errorKpiGradient,
                            () {
                          context.go('/facility/${widget.facilityId}/alerts');
                        }, colors),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 36),
                _buildInventoryTable(context, ref, inventory, colors),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportInventoryCsv(BuildContext context, WidgetRef ref,
      List<InventoryItem> inventory) async {
    try {
      final fac = await ref
          .read(firebaseServiceProvider)
          .getFacility(widget.facilityId);
      await CsvExportService.exportInventory(inventory,
          facilityName: fac?.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Inventory CSV exported \u2713')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color accent,
      LinearGradient bg, VoidCallback? onTap, MediFlowTheme colors) {
    return MouseRegion(
      cursor:
          onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(height: 18),
              Text(value,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: accent)),
              const SizedBox(height: 4),
              Text(title,
                  style: TextStyle(
                      fontSize: 13, color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryTable(
      BuildContext context, WidgetRef ref, List<InventoryItem> inventory, MediFlowTheme colors) {
    return Column(
      key: _inventoryTableKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Inventory Status',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary)),
            OutlinedButton.icon(
              onPressed: inventory.isEmpty
                  ? null
                  : () => _exportInventoryCsv(context, ref, inventory),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textSecondary,
                side: BorderSide(color: colors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: inventory.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 48, color: colors.textMuted),
                      const SizedBox(height: 12),
                      Text('No inventory items yet',
                          style: TextStyle(color: colors.textMuted)),
                    ]),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DataTable(
                    columnSpacing: 28,
                    columns: const [
                      DataColumn(label: Text('Medicine')),
                      DataColumn(label: Text('Quantity')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Expiry Date')),
                      DataColumn(label: Text('Time Left')),
                    ],
                    rows: inventory.map((item) {
                      final pct = item.remainingPercentage;
                      final daysToExpiry = item.daysToExpiry;
                      // Use centralized status — single source of truth.
                      final statusColor = switch (item.status) {
                        ItemStatus.expired => colors.error,
                        ItemStatus.wastageRisk => const Color(0xFFF59E0B),
                        ItemStatus.lowStock => colors.error,
                        ItemStatus.expiringSoon => colors.warning,
                        ItemStatus.healthy => colors.success,
                      };
                      final statusText = item.statusText;

                      return DataRow(cells: [
                        DataCell(Row(children: [
                          Container(
                              width: 4,
                              height: 32,
                              decoration: BoxDecoration(
                                  color: statusColor,
                                  borderRadius: BorderRadius.circular(4))),
                          const SizedBox(width: 12),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(item.medicineName,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colors.textPrimary)),
                                Text(item.batchId,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colors.textMuted)),
                              ]),
                        ])),
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${item.remainingQuantity} / ${item.initialQuantity}',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 100,
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: colors.surfaceLight,
                                color: statusColor,
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        )),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(statusText,
                              style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        )),
                        DataCell(Text(
                          DateFormatter.formatDate(item.expiryDate),
                          style:
                              TextStyle(color: colors.textSecondary),
                        )),
                        DataCell(Text(
                          daysToExpiry < 0
                              ? 'Expired'
                              : daysToExpiry > 365
                                  ? '${(daysToExpiry / 365).toStringAsFixed(1)} yr'
                                  : '$daysToExpiry days',
                          style: TextStyle(
                            color: daysToExpiry < 0
                                ? colors.error
                                : daysToExpiry < 90
                                    ? colors.warning
                                    : colors.textSecondary,
                            fontWeight: daysToExpiry < 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }
}
