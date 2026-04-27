import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/facility.dart';
import '../../models/request.dart';
import '../../models/inventory_item.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../services/routing_service.dart';
import '../../main.dart';

class RouteOptimizationMap extends ConsumerStatefulWidget {
  const RouteOptimizationMap({super.key});

  @override
  ConsumerState<RouteOptimizationMap> createState() => _RouteOptimizationMapState();
}

class _RouteOptimizationMapState extends ConsumerState<RouteOptimizationMap> {
  final MapController _mapController = MapController();
  List<Facility> _facilities = [];
  Map<String, List<InventoryItem>> _allInventory = {};
  List<MedRequest> _pendingRequests = [];
  bool _isLoading = true;
  bool _isComputing = false;
  bool _showRoutes = false;
  String _aiSummary = '';
  List<Map<String, dynamic>> _transferPlan = [];
  Map<int, List<LatLng>> _routeGeometries = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _fitMapToFacilities() {
    if (_facilities.isEmpty) return;
    try {
      final points = _facilities.map((f) => LatLng(f.latitude, f.longitude)).toList();
      _mapController.fitCamera(
        CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(60)),
      );
    } catch (_) {}
  }

  Future<void> _loadData() async {
    final firebase = ref.read(firebaseServiceProvider);
    try {
      final facs = await firebase.getFacilities();
      
      // Load inventory for ALL facilities
      Map<String, List<InventoryItem>> allInv = {};
      for (var fac in facs) {
        final inv = await firebase.getInventoryOnce(fac.id);
        allInv[fac.id] = inv;
      }

      if (mounted) {
        setState(() {
          _facilities = facs;
          _allInventory = allInv;
          _isLoading = false;
        });
        Future.delayed(const Duration(milliseconds: 500), _fitMapToFacilities);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// Smart redistribution algorithm:
  /// 1. Scan ALL inventory across ALL facilities for each medicine.
  /// 2. Identify facilities with surplus (>50% remaining) and deficit (<25% remaining).
  /// 3. Also include any pending indent requests as explicit needs.
  /// 4. Match donors to recipients on priority: rural first, nearest, near-expiry stock first.
  /// 5. One donor can supply multiple recipients.
  Future<void> _computeRedistribution() async {
    setState(() => _isComputing = true);
    try {
      final firebase = ref.read(firebaseServiceProvider);
      final allRequests = await firebase.streamRequests(null).first;
      final pending = allRequests.where((r) =>
          r.status == RequestStatus.pending && r.type == RequestType.regularIndent).toList();
      setState(() => _pendingRequests = pending);

      final Distance distCalc = const Distance();
      List<Map<String, dynamic>> transfers = [];

      // Collect all unique medicine names across all facilities
      final Set<String> allMeds = {};
      for (var inv in _allInventory.values) {
        for (var item in inv) {
          allMeds.add(item.medicineName.toLowerCase());
        }
      }

      // For each medicine, find surplus and deficit facilities
      for (var medName in allMeds) {
        List<Map<String, dynamic>> surplusFacs = [];
        List<Map<String, dynamic>> deficitFacs = [];

        for (var fac in _facilities) {
          final inv = _allInventory[fac.id] ?? [];
          final item = inv.where((i) => i.medicineName.toLowerCase() == medName).firstOrNull;
          if (item == null) {
            // Facility doesn't have this medicine at all — it's in deficit
            deficitFacs.add({'facility': fac, 'deficit': 50, 'remaining': 0, 'initial': 100});
            continue;
          }
          final ratio = item.remainingQuantity / item.initialQuantity;
          if (ratio > 0.50) {
            final spare = ((item.remainingQuantity - item.initialQuantity * 0.35) * 0.5).round();
            if (spare > 0) {
              surplusFacs.add({'facility': fac, 'item': item, 'spare': spare, 'ratio': ratio});
            }
          } else if (ratio < 0.25) {
            final need = (item.initialQuantity * 0.4 - item.remainingQuantity).round();
            if (need > 0) {
              deficitFacs.add({'facility': fac, 'deficit': need, 'remaining': item.remainingQuantity, 'initial': item.initialQuantity});
            }
          }
        }

        // Also add pending indent requests for this medicine as deficit
        for (var req in pending) {
          if (req.medicineName.toLowerCase() != medName) continue;
          final fac = _facilities.where((f) => f.id == req.facilityId).firstOrNull;
          if (fac == null) continue;
          if (!deficitFacs.any((d) => (d['facility'] as Facility).id == fac.id)) {
            deficitFacs.add({'facility': fac, 'deficit': req.quantity, 'remaining': 0, 'initial': req.quantity});
          }
        }

        // Sort deficit: rural first, then by severity
        deficitFacs.sort((a, b) {
          final aFac = a['facility'] as Facility;
          final bFac = b['facility'] as Facility;
          if (aFac.type == 'rural' && bFac.type != 'rural') return -1;
          if (bFac.type == 'rural' && aFac.type != 'rural') return 1;
          return (b['deficit'] as int).compareTo(a['deficit'] as int);
        });

        // Match surplus donors to deficit recipients
        for (var deficit in deficitFacs) {
          if (surplusFacs.isEmpty) break;
          final recFac = deficit['facility'] as Facility;
          int needed = deficit['deficit'] as int;

          // Score each surplus donor for this recipient
          List<Map<String, dynamic>> scored = [];
          for (var surplus in surplusFacs) {
            final donFac = surplus['facility'] as Facility;
            if (donFac.id == recFac.id) continue;
            final distM = distCalc(LatLng(donFac.latitude, donFac.longitude), LatLng(recFac.latitude, recFac.longitude));
            final distKm = distM / 1000;
            double score = (500 - distKm.clamp(0, 500));
            if (recFac.type == 'rural') score += 150;
            final item = surplus['item'] as InventoryItem;
            if (item.expiryDate.difference(DateTime.now()).inDays < 90) score += 100;
            score += ((surplus['spare'] as int) / needed * 100).clamp(0, 200);
            scored.add({...surplus, 'distKm': distKm, 'score': score});
          }
          scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

          for (var donor in scored) {
            if (needed <= 0) break;
            final donFac = donor['facility'] as Facility;
            int available = donor['spare'] as int;
            final qty = min(available, needed);
            if (qty <= 0) continue;
            final distKm = donor['distKm'] as double;
            transfers.add({
              'from': donFac, 'to': recFac,
              'medicine': (donor['item'] as InventoryItem).medicineName,
              'qty': qty, 'requested': deficit['deficit'],
              'distance': '${distKm.toStringAsFixed(1)} km',
              'time': '${(distKm / 40).ceil()}h ${((distKm % 40) / 40 * 60).round()}m',
              'score': donor['score'] as double,
              'donorStock': (donor['item'] as InventoryItem).remainingQuantity,
              'recipientType': recFac.type,
            });
            needed -= qty;
            // Reduce donor spare for next iteration
            donor['spare'] = available - qty;
          }
        }
      }

      // Sort transfers by score
      transfers.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      // AI summary
      String summary;
      try {
        summary = await ref.read(aiServiceProvider).generateRedistributionPlan(pending, _facilities);
      } catch (_) {
        summary = _localSummary(transfers, pending);
      }

      // Fetch real road routes from OSRM
      Map<int, List<LatLng>> geometries = {};
      for (int i = 0; i < transfers.length; i++) {
        final from = transfers[i]['from'] as Facility;
        final to = transfers[i]['to'] as Facility;
        geometries[i] = await RoutingService.getRoute(
          LatLng(from.latitude, from.longitude), LatLng(to.latitude, to.longitude),
        );
      }

      if (mounted) {
        setState(() {
          _transferPlan = transfers;
          _routeGeometries = geometries;
          _aiSummary = summary;
          _showRoutes = true;
          _isComputing = false;
        });
        Future.delayed(const Duration(milliseconds: 300), _fitMapToFacilities);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isComputing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _localSummary(List<Map<String, dynamic>> transfers, List<MedRequest> pending) {
    if (transfers.isEmpty) return 'All facilities have balanced stock levels. No redistribution needed.';
    final totalUnits = transfers.fold<int>(0, (sum, t) => sum + (t['qty'] as int));
    final ruralCount = transfers.where((t) => t['recipientType'] == 'rural').length;
    final uniqueMeds = transfers.map((t) => t['medicine']).toSet().length;
    return 'AI detected imbalances in $uniqueMeds medicine(s). '
        'Optimized ${transfers.length} transfers moving $totalUnits units across ${_facilities.length} facilities. '
        '$ruralCount transfer(s) prioritized for rural clinics.';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: MediColors.bg, body: Center(child: CircularProgressIndicator()));

    final mapCenter = _facilities.isNotEmpty
        ? LatLng(_facilities.first.latitude, _facilities.first.longitude)
        : const LatLng(28.6139, 77.2090);

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('Route Optimization')),
      body: Row(
        children: [
          // ── Left Panel ──
          Container(
            width: 420,
            color: MediColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Transfer Manifest', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: MediColors.textPrimary)),
                      const SizedBox(height: 8),
                      const Text('AI-optimized redistribution paths based on stock levels, distance, and facility priority.', style: TextStyle(color: MediColors.textSecondary, fontSize: 13)),
                      const SizedBox(height: 16),

                      // Stats row
                      Row(
                        children: [
                          _buildStatChip(Icons.business_rounded, '${_facilities.length}', 'Facilities'),
                          const SizedBox(width: 12),
                          _buildStatChip(Icons.inventory_2_rounded, '${_allInventory.values.fold<int>(0, (s, l) => s + l.length)}', 'Total Items'),
                          const SizedBox(width: 12),
                          if (_showRoutes)
                            _buildStatChip(Icons.route_rounded, '${_transferPlan.length}', 'Routes'),
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (_aiSummary.isNotEmpty && _showRoutes) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [MediColors.primary.withOpacity(0.08), MediColors.violet.withOpacity(0.05)]),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: MediColors.primary.withOpacity(0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.auto_awesome, color: MediColors.primaryLight, size: 18),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_aiSummary, style: const TextStyle(color: MediColors.primaryLight, fontStyle: FontStyle.italic, fontSize: 13))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: _showRoutes ? null : MediColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                            border: _showRoutes ? Border.all(color: MediColors.border) : null,
                          ),
                          child: _isComputing
                              ? const Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                                  SizedBox(width: 12),
                                  Text('Analyzing all facilities...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ]))
                              : FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
                                  icon: Icon(_showRoutes ? Icons.refresh_rounded : Icons.route_rounded),
                                  label: Text(_showRoutes ? 'Recompute Routes' : 'Generate Routes'),
                                  onPressed: _computeRedistribution,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: MediColors.border),
                Expanded(
                  child: !_showRoutes
                      ? const Center(child: Text('Generate routes to see manifest', style: TextStyle(color: MediColors.textMuted)))
                      : _transferPlan.isEmpty
                          ? _buildNoTransfersState()
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _transferPlan.length,
                              itemBuilder: (context, index) {
                                final t = _transferPlan[index];
                                return _buildTransferCard(
                                  from: (t['from'] as Facility).name,
                                  to: (t['to'] as Facility).name,
                                  medicine: t['medicine'],
                                  quantity: '${t['qty']} / ${t['requested']} units',
                                  distance: t['distance'],
                                  time: t['time'],
                                  score: t['score'],
                                  isRural: t['recipientType'] == 'rural',
                                  donorStock: t['donorStock'],
                                );
                              },
                            ),
                ),
              ],
            ),
          ),

          // ── Right Panel: Map ──
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: mapCenter, initialZoom: 6.0),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.mediflow.app',
                    ),
                    if (_showRoutes && _transferPlan.isNotEmpty)
                      PolylineLayer<Object>(
                        polylines: List.generate(_transferPlan.length, (i) {
                          final t = _transferPlan[i];
                          final from = t['from'] as Facility;
                          final to = t['to'] as Facility;
                          final points = _routeGeometries[i] ?? [
                            LatLng(from.latitude, from.longitude),
                            LatLng(to.latitude, to.longitude),
                          ];
                          return Polyline<Object>(
                            points: points,
                            color: t['recipientType'] == 'rural' ? MediColors.warning : MediColors.primary,
                            strokeWidth: 4.0,
                          );
                        }),
                      ),
                    MarkerLayer(
                      markers: _facilities.map((f) {
                        // Check if this facility is a donor or recipient in the transfer plan
                        final isDonor = _transferPlan.any((t) => (t['from'] as Facility).id == f.id);
                        final isRecipient = _transferPlan.any((t) => (t['to'] as Facility).id == f.id);
                        Color markerColor = Colors.red;
                        if (isDonor) markerColor = MediColors.success;
                        if (isRecipient) markerColor = MediColors.warning;

                        return Marker(
                          point: LatLng(f.latitude, f.longitude),
                          width: 130,
                          height: 90,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: markerColor.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: markerColor, width: 2),
                                ),
                                child: Icon(Icons.local_hospital, color: markerColor, size: 22),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: MediColors.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: MediColors.border),
                                ),
                                child: Text(
                                  f.name.length > 16 ? '${f.name.substring(0, 14)}…' : f.name,
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: MediColors.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                // Legend
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: MediColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: MediColors.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Legend', style: TextStyle(fontWeight: FontWeight.bold, color: MediColors.textPrimary)),
                        const SizedBox(height: 10),
                        _legendRow(MediColors.success, 'Donor Facility'),
                        const SizedBox(height: 6),
                        _legendRow(MediColors.warning, 'Recipient (Rural Priority)'),
                        const SizedBox(height: 6),
                        _legendRow(Colors.red, 'Neutral Facility'),
                        const SizedBox(height: 6),
                        Row(children: [Container(width: 16, height: 3, color: MediColors.primary), const SizedBox(width: 8), const Text('Transfer Route', style: TextStyle(color: MediColors.textSecondary, fontSize: 12))]),
                        const SizedBox(height: 6),
                        Row(children: [Container(width: 16, height: 3, color: MediColors.warning), const SizedBox(width: 8), const Text('Rural Priority Route', style: TextStyle(color: MediColors.textSecondary, fontSize: 12))]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable Widgets ──

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: MediColors.surfaceLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: MediColors.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: MediColors.textMuted),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: MediColors.textPrimary, fontSize: 14)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: MediColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(children: [
      Container(width: 14, height: 14, decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: color, width: 2))),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: MediColors.textSecondary, fontSize: 12)),
    ]);
  }

  Widget _buildNoTransfersState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 48, color: MediColors.success),
            const SizedBox(height: 16),
            Text('All Clear', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: MediColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('No redistribution needed. All facilities have balanced stock or no pending indents.',
                style: TextStyle(color: MediColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferCard({
    required String from,
    required String to,
    required String medicine,
    required String quantity,
    required String distance,
    required String time,
    required double score,
    required bool isRural,
    required int donorStock,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MediColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isRural ? MediColors.warning.withOpacity(0.4) : MediColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Priority Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isRural ? MediColors.warning.withOpacity(0.12) : MediColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isRural ? '⚡ RURAL PRIORITY' : '● STANDARD',
                  style: TextStyle(color: isRural ? MediColors.warning : MediColors.primaryLight, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              Text('Score: ${score.toStringAsFixed(0)}', style: const TextStyle(color: MediColors.textMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),

          // From → To
          Row(children: [
            const Icon(Icons.outbound_rounded, color: MediColors.success, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(from, style: const TextStyle(fontWeight: FontWeight.w600, color: MediColors.textPrimary, fontSize: 13))),
            Text('Stock: $donorStock', style: const TextStyle(color: MediColors.textMuted, fontSize: 11)),
          ]),
          const Padding(padding: EdgeInsets.only(left: 8, top: 4, bottom: 4), child: Icon(Icons.arrow_downward_rounded, color: MediColors.textMuted, size: 14)),
          Row(children: [
            Icon(Icons.input_rounded, color: isRural ? MediColors.warning : MediColors.info, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(to, style: const TextStyle(fontWeight: FontWeight.w600, color: MediColors.textPrimary, fontSize: 13))),
          ]),
          const Divider(height: 20, color: MediColors.border),

          // Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(medicine, style: const TextStyle(fontWeight: FontWeight.w600, color: MediColors.textPrimary, fontSize: 13)),
                Text(quantity, style: const TextStyle(color: MediColors.textMuted, fontSize: 12)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(children: [const Icon(Icons.route_rounded, size: 14, color: MediColors.primary), const SizedBox(width: 4), Text(distance, style: const TextStyle(color: MediColors.primary, fontWeight: FontWeight.w600, fontSize: 13))]),
                Row(children: [const Icon(Icons.schedule_rounded, size: 14, color: MediColors.textMuted), const SizedBox(width: 4), Text(time, style: const TextStyle(color: MediColors.textMuted, fontSize: 12))]),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}
