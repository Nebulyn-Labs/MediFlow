import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/inventory_item.dart';
import '../../services/firebase_service.dart';
import '../../services/simulation_service.dart';
import '../../services/csv_export_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class FacilityOverview extends ConsumerWidget {
  final String facilityId;
  const FacilityOverview({super.key, required this.facilityId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryStream =
        ref.watch(firebaseServiceProvider).streamInventory(facilityId);

    return StreamBuilder<List<InventoryItem>>(
      stream: inventoryStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final inventory = snapshot.data ?? [];
        final expiringSoon = inventory
            .where((i) => i.expiryDate.difference(DateTime.now()).inDays <= 30)
            .length;
        final lowStock = inventory.where((i) {
          final pct = i.initialQuantity > 0
              ? i.remainingQuantity / i.initialQuantity
              : 0.0;
          return pct <= 0.20 || i.remainingQuantity <= 500;
        }).length;

        return Scaffold(
          backgroundColor: MediColors.bg,
          appBar: AppBar(
            title: const Text('Dashboard'),
            actions: [
              // Live Alert Bell
              PopupMenuButton<String>(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_outlined,
                        color: MediColors.textSecondary),
                    if (lowStock + expiringSoon > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                              color: MediColors.error, shape: BoxShape.circle),
                          child: Center(
                              child: Text('${lowStock + expiringSoon}',
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
                    const PopupMenuItem<String>(
                        value: 'h',
                        enabled: false,
                        child: Text('Live Alerts',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: MediColors.textPrimary))),
                    const PopupMenuDivider(),
                  ];
                  final lowItems = inventory.where((i) {
                    final pct = i.initialQuantity > 0
                        ? i.remainingQuantity / i.initialQuantity
                        : 0.0;
                    return pct <= 0.20 || i.remainingQuantity <= 500;
                  }).toList();
                  final expiringItems = inventory
                      .where((i) =>
                          i.expiryDate.difference(DateTime.now()).inDays <= 30)
                      .toList();
                  for (var item in lowItems) {
                    alerts.add(PopupMenuItem<String>(
                        value: 'l_${item.medicineName}',
                        child: ListTile(
                          leading: const Icon(Icons.warning_rounded,
                              color: MediColors.error, size: 20),
                          title: Text('${item.medicineName} critically low',
                              style: const TextStyle(
                                  fontSize: 13, color: MediColors.textPrimary)),
                          subtitle: Text('${item.remainingQuantity} units left',
                              style: const TextStyle(
                                  fontSize: 11, color: MediColors.textMuted)),
                          trailing: TextButton(
                            onPressed: () async {
                              try {
                                await ref
                                    .read(firebaseServiceProvider)
                                    .restock(facilityId, item.medicineName, 500);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text(
                                          'Restocked 500 units of ${item.medicineName}')));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
                              color: isExpired
                                  ? MediColors.error
                                  : MediColors.warning,
                              size: 20),
                          title: Text(
                              isExpired
                                  ? '${item.medicineName} has EXPIRED'
                                  : '${item.medicineName} expires in $d d',
                              style: const TextStyle(
                                  fontSize: 13, color: MediColors.textPrimary)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        )));
                  }
                  if (lowItems.isEmpty && expiringItems.isEmpty) {
                    alerts.add(const PopupMenuItem<String>(
                        value: 'ok',
                        enabled: false,
                        child: ListTile(
                          leading: Icon(Icons.check_circle_rounded,
                              color: MediColors.success, size: 20),
                          title: Text('All systems healthy',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: MediColors.textSecondary)),
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
                    try {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) context.go('/');
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Sign out failed: ${e.toString()}'),
                            backgroundColor: MediColors.error,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => ref
                .read(firebaseServiceProvider)
                .getInventoryOnce(facilityId),
            color: MediColors.primary,
            backgroundColor: MediColors.surface,
            strokeWidth: 2.5,
            displacement: 48,
            child: SingleChildScrollView(
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
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: MediColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Real-time inventory monitoring and insights',
                            style: const TextStyle(
                                color: MediColors.textSecondary, fontSize: 14)),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final firebase = ref.read(firebaseServiceProvider);
                        final fac = await firebase.getFacility(facilityId);
                        if (fac != null) {
                          // Show loading
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Simulating 30 days of usage data...')));
                          }
                          await ref
                              .read(simulationServiceProvider)
                              .runFullSimulation(facilityId, fac.type);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Simulation complete! Analytics ready.')));
                          }
                        }
                      },
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Simulate Analytics'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MediColors.primary,
                        side: const BorderSide(color: MediColors.primary),
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
                    final expired = inventory
                        .where((i) =>
                            i.expiryDate.difference(DateTime.now()).inDays < 0)
                        .length;
                    final wastageRisk = inventory.where((i) {
                      final pct = i.initialQuantity > 0
                          ? (i.remainingQuantity / i.initialQuantity)
                          : 1.0;
                      return pct >= 0.70 &&
                          i.expiryDate.difference(DateTime.now()).inDays <= 30;
                    }).length;
                    final unhealthy = inventory.where((i) {
                      final pct = i.initialQuantity > 0
                          ? i.remainingQuantity / i.initialQuantity
                          : 0.0;
                      final daysLeft =
                          i.expiryDate.difference(DateTime.now()).inDays;
                      return daysLeft < 0 ||
                          daysLeft <= 30 ||
                          pct >= 0.70 && daysLeft <= 30 ||
                          pct <= 0.20 ||
                          i.remainingQuantity <= 500;
                    }).length;
                    final healthy = (inventory.length - unhealthy)
                        .clamp(0, inventory.length);
                    final stockHealthText = inventory.isEmpty
                        ? 'No stock'
                        : '$healthy / ${inventory.length} healthy';
                    final stockHealthColor = unhealthy == 0
                        ? MediColors.success
                        : MediColors.warning;
                    final stockHealthGradient = unhealthy == 0
                        ? const LinearGradient(
                            colors: [Color(0xFF0A3D2E), Color(0xFF1E293B)])
                        : const LinearGradient(
                            colors: [Color(0xFF3D2E0A), Color(0xFF1E293B)]);

                    return Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      children: [
                        _buildKpiCard(
                            'Total Meds in Inv',
                            '${inventory.length}',
                            Icons.medication_rounded,
                            MediColors.info,
                            const LinearGradient(
                                colors: [Color(0xFF1E3A5F), Color(0xFF1E293B)]),
                            () {}),
                        _buildKpiCard(
                            'Stock Health',
                            stockHealthText,
                            Icons.health_and_safety_rounded,
                            stockHealthColor,
                            stockHealthGradient, () {
                          context.go('/facility/$facilityId/alerts');
                        }),
                        _buildKpiCard(
                            'Expired',
                            '$expired',
                            Icons.error_outline_rounded,
                            MediColors.error,
                            const LinearGradient(
                                colors: [Color(0xFF3D1519), Color(0xFF1E293B)]),
                            () {
                          context.go('/facility/$facilityId/alerts');
                        }),
                        _buildKpiCard(
                            'Wastage Risk',
                            '$wastageRisk',
                            Icons.warning_amber_rounded,
                            const Color(0xFFF59E0B),
                            const LinearGradient(
                                colors: [Color(0xFF3D2E0A), Color(0xFF1E293B)]),
                            () {
                          context.go('/facility/$facilityId/alerts');
                        }),
                        _buildKpiCard(
                            'Low Stock',
                            '$lowStock',
                            Icons.trending_down_rounded,
                            MediColors.error,
                            const LinearGradient(
                                colors: [Color(0xFF3D1519), Color(0xFF1E293B)]),
                            () {
                          context.go('/facility/$facilityId/alerts');
                        }),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 36),
                _buildInventoryTable(context, ref, inventory),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportInventoryCsv(BuildContext context, WidgetRef ref,
      List<InventoryItem> inventory) async {
    try {
      final fac =
          await ref.read(firebaseServiceProvider).getFacility(facilityId);
      await CsvExportService.exportInventory(inventory,
          facilityName: fac?.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Inventory CSV exported ✓')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color accent,
      LinearGradient bg, VoidCallback onTap) {
    return GestureDetector(
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
                    fontSize: 28, fontWeight: FontWeight.w800, color: accent)),
            const SizedBox(height: 4),
            Text(title,
                style: const TextStyle(
                    fontSize: 13, color: MediColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryTable(
      BuildContext context, WidgetRef ref, List<InventoryItem> inventory) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Inventory Status',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: MediColors.textPrimary)),
            OutlinedButton.icon(
              onPressed: inventory.isEmpty
                  ? null
                  : () => _exportInventoryCsv(context, ref, inventory),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MediColors.textSecondary,
                side: const BorderSide(color: MediColors.border),
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
            color: MediColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MediColors.border),
          ),
          child: inventory.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 48, color: MediColors.textMuted),
                      const SizedBox(height: 12),
                      Text('No inventory items yet',
                          style: TextStyle(color: MediColors.textMuted)),
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
                      final pct = item.initialQuantity > 0
                          ? (item.remainingQuantity / item.initialQuantity)
                          : 1.0;
                      final daysToExpiry =
                          item.expiryDate.difference(DateTime.now()).inDays;
                      Color statusColor;
                      String statusText;
                      if (daysToExpiry < 0) {
                        statusColor = MediColors.error;
                        statusText = 'Expired';
                      } else if (pct >= 0.70 && daysToExpiry <= 30) {
                        statusColor = const Color(0xFFF59E0B); // Amber
                        statusText = 'Wastage Risk';
                      } else if (pct <= 0.20 || item.remainingQuantity <= 500) {
                        statusColor = MediColors.error;
                        statusText = 'Low Stock';
                      } else {
                        statusColor = MediColors.success;
                        statusText = 'Healthy';
                      }

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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: MediColors.textPrimary)),
                                Text(item.batchId,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: MediColors.textMuted)),
                              ]),
                        ])),
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${item.remainingQuantity} / ${item.initialQuantity}',
                                style: const TextStyle(
                                    color: MediColors.textPrimary,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 100,
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: MediColors.surfaceLight,
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
                          "${item.expiryDate.year}-${item.expiryDate.month.toString().padLeft(2, '0')}-${item.expiryDate.day.toString().padLeft(2, '0')}",
                          style:
                              const TextStyle(color: MediColors.textSecondary),
                        )),
                        DataCell(Text(
                          daysToExpiry < 0
                              ? 'Expired'
                              : daysToExpiry > 365
                                  ? '${(daysToExpiry / 365).toStringAsFixed(1)} yr'
                                  : '$daysToExpiry days',
                          style: TextStyle(
                            color: daysToExpiry < 0
                                ? MediColors.error
                                : daysToExpiry < 90
                                    ? MediColors.warning
                                    : MediColors.textSecondary,
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