import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../models/facility.dart';
import '../../models/request.dart';
import '../../models/inventory_item.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class AdminOverview extends ConsumerStatefulWidget {
  const AdminOverview({super.key});

  @override
  ConsumerState<AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends ConsumerState<AdminOverview> {
  List<Facility> _facilities = [];
  Map<String, double> _stockHealth = {};
  Map<String, int> _alertCounts = {};
  Map<String, int> _topMedicines = {};

  int _openShortageRequests = 0;
  int _surplusOffers = 0;
  int _pendingIndents = 0;

  bool _isLoading = true;
  StreamSubscription? _requestsSub;

  // ---- search state (Sprint 3) ----
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // ---- filter state (Sprint 4) ----
  static const List<String> _filterOptions = [
    'All',
    'Low Stock',
    'Surplus',
    'Expiring Soon',
  ];
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _requestsSub?.cancel();
    final facs = await ref.read(firebaseServiceProvider).getFacilities();

    Map<String, double> health = {};
    Map<String, int> alerts = {};
    Map<String, int> topMeds = {};

    // Parallelize facility inventory and AI alert requests using Future.wait
    await Future.wait(facs.map((f) async {
      final inv =
          await ref.read(firebaseServiceProvider).getInventoryOnce(f.id);

      double totalInitial = 0;
      double totalRemaining = 0;
      for (var item in inv) {
        totalInitial += item.initialQuantity;
        totalRemaining += item.remainingQuantity;

        topMeds[item.medicineName] =
            (topMeds[item.medicineName] ?? 0) + item.remainingQuantity.toInt();
      }

      health[f.id] =
          totalInitial == 0 ? 100.0 : (totalRemaining / totalInitial) * 100;

      final fAlerts =
          await ref.read(aiServiceProvider).generateSmartAlerts(inv);
      alerts[f.id] = fAlerts.length;
    }));

    _requestsSub =
        ref.read(firebaseServiceProvider).streamRequests(null).listen((reqs) {
      if (!mounted) return;
      int shortage = 0;
      int surplus = 0;
      int pending = 0;
      for (var r in reqs) {
        if (r.status == RequestStatus.pending) {
          if (r.type == RequestType.shortage) shortage++;
          if (r.type == RequestType.surplus) surplus++;
          if (r.type == RequestType.regularIndent) pending++;
        }
      }
      setState(() {
        _openShortageRequests = shortage;
        _surplusOffers = surplus;
        _pendingIndents = pending;
      });
    });

    if (mounted) {
      setState(() {
        _facilities = facs;
        _stockHealth = health;
        _alertCounts = alerts;
        _topMedicines = topMeds;
        _isLoading = false;
      });
    }
  }

  // ---- status + filtering logic (Sprint 5) ----
  String _getStockStatus(InventoryItem item) {
    final daysToExpiry = item.expiryDate.difference(DateTime.now()).inDays;
    if (daysToExpiry <= 90) return 'Expiring Soon';

    if (item.initialQuantity == 0) return 'Healthy';
    final ratio = item.remainingQuantity / item.initialQuantity;
    if (ratio < 0.2) return 'Low Stock';
    if (ratio > 0.8) return 'Surplus';
    return 'Healthy';
  }

  List<InventoryItem> _applyFilters(List<InventoryItem> items) {
    return items.where((item) {
      final matchesSearch =
          item.medicineName.toLowerCase().contains(_searchQuery);
      final matchesFilter =
          _selectedFilter == 'All' || _getStockStatus(item) == _selectedFilter;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  // ---- medicine list widget (Sprint 6, overflow-fixed in 9c) ----
  Widget _buildMedicineList() {
    return StreamBuilder<List<InventoryItem>>(
      stream: ref.read(firebaseServiceProvider).streamAllMedicines(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Error loading inventory: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final filtered = _applyFilters(snapshot.data!);

        if (filtered.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No medicines match your search or filter.',
                style: TextStyle(color: MediColors.textSecondary)),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final item = filtered[index];
            final status = _getStockStatus(item);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MediColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MediColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(item.medicineName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: MediColors.textPrimary)),
                  ),
                  Expanded(
                    child: Text(
                        '${item.remainingQuantity}/${item.initialQuantity} ${item.unit}',
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: MediColors.textSecondary)),
                  ),
                  Flexible(
                    child: Text(status,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: MediColors.info)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---- filter chips as horizontally-scrollable row (Sprint 9d) ----
  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filterOptions.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _selectedFilter = filter;
                });
              },
              backgroundColor: MediColors.surface,
              selectedColor: MediColors.info.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected ? MediColors.info : MediColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: isSelected ? MediColors.info : MediColors.border,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              color: MediColors.info,
              backgroundColor: MediColors.surface,
              strokeWidth: 2.5,
              displacement: 48,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KPI Header
                    Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      children: [
                        _buildKpiCard('TOTAL FACILITIES',
                            '${_facilities.length}', Icons.business_rounded,
                            onTap: () {}),
                        _buildKpiCard(
                            'OPEN SHORTAGE REQUESTS',
                            '$_openShortageRequests',
                            Icons.warning_amber_rounded,
                            isAlert: true,
                            onTap: () {}),
                        _buildKpiCard('SURPLUS / EXPIRY OFFERS',
                            '$_surplusOffers', Icons.swap_horiz_rounded,
                            isAlert: false,
                            iconColor: MediColors.warning,
                            onTap: () {}),
                        _buildKpiCard(
                            'PENDING INDENT APPROVALS',
                            '$_pendingIndents',
                            Icons.assignment_turned_in_rounded,
                            iconColor: MediColors.info,
                            onTap: () => context.go('/admin/approvals')),
                      ],
                    ),
                    const SizedBox(height: 36),

                    // ---- search field (Sprint 3) ----
                    TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search medicines by name...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: MediColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: MediColors.border),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ---- filter chips (Sprint 4, horizontal-scroll in 9d) ----
                    _buildFilterChips(),
                    const SizedBox(height: 20),

                    // ---- medicine list (Sprint 6) ----
                    _buildMedicineList(),
                    const SizedBox(height: 36),

                    // Facility Health Grid
                    _buildFacilityHealthGrid(),
                    const SizedBox(height: 36),

                    // Top Medicines Chart
                    _buildTopMedicinesChart(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon,
      {bool isAlert = false, Color? iconColor, VoidCallback? onTap}) {
    final finalIconColor =
        isAlert ? MediColors.error : (iconColor ?? MediColors.info);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: MediColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MediColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: MediColors.textSecondary,
                            letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Icon(icon, color: finalIconColor, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Text(value,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: MediColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildFacilityHealthGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Facility Health Overview',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MediColors.textPrimary)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: _facilities.map((f) => _buildHealthCard(f)).toList(),
        ),
      ],
    );
  }

  Widget _buildHealthCard(Facility facility) {
    final health = _stockHealth[facility.id] ?? 0;
    final alerts = _alertCounts[facility.id] ?? 0;

    Color healthColor;
    String healthStatus;
    if (health > 70) {
      healthColor = MediColors.success;
      healthStatus = 'Healthy';
    } else if (health > 40) {
      healthColor = MediColors.warning;
      healthStatus = 'Low';
    } else {
      healthColor = MediColors.error;
      healthStatus = 'Critical';
    }

    return Container(
      width: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MediColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Text(facility.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: MediColors.textPrimary),
                      overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: MediColors.surfaceLight,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(facility.type,
                    style: const TextStyle(
                        fontSize: 10,
                        color: MediColors.textSecondary,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Stock Health',
                  style:
                      TextStyle(fontSize: 12, color: MediColors.textSecondary)),
              Text('${health.round()}%',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: healthColor)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: health / 100,
              backgroundColor: MediColors.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(healthColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: healthColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(healthStatus,
                    style: TextStyle(
                        color: healthColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              if (alerts > 0)
                Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded,
                        color: MediColors.error, size: 14),
                    const SizedBox(width: 4),
                    Text('$alerts',
                        style: const TextStyle(
                            color: MediColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopMedicinesChart() {
    if (_topMedicines.isEmpty) return const SizedBox.shrink();

    var sortedEntries = _topMedicines.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    var topEntries = sortedEntries.take(8).toList();
    if (topEntries.isEmpty) return const SizedBox.shrink();

    final maxQty = topEntries.first.value;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MediColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top Medicines by Total Units Across All Facilities',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MediColors.textPrimary)),
          const SizedBox(height: 32),
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: topEntries.map((e) {
                final heightFactor = maxQty == 0 ? 0.0 : e.value / maxQty;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 24,
                        height: 150 * heightFactor,
                        decoration: const BoxDecoration(
                          color: MediColors.info,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        e.key,
                        style: const TextStyle(
                            fontSize: 10, color: MediColors.textSecondary),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
