import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/facility.dart';
import '../../models/request.dart';
import '../../models/inventory_item.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../services/routing_service.dart';
import '../../services/optimization_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class RouteOptimizationMap extends ConsumerStatefulWidget {
  const RouteOptimizationMap({super.key});

  @override
  ConsumerState<RouteOptimizationMap> createState() =>
      _RouteOptimizationMapState();
}

class _RouteOptimizationMapState extends ConsumerState<RouteOptimizationMap> {
  final MapController _mapController = MapController();
  List<Facility> _facilities = [];
  bool _isLoading = true;
  bool _showRoutes = false;
  bool _isGenerating = false;
  String _aiSummary = '';
  List<TransferRecommendation> _recommendations = [];
  Map<String, List<LatLng>> _roadRoutes = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final firebaseService = ref.read(firebaseServiceProvider);
    final facs = await firebaseService.getFacilities();

    if (mounted) {
      setState(() {
        _facilities = facs;
        _isLoading = false;
      });
    }
  }



  Future<void> _generateOptimalRoutes(
      List<MedRequest> requests, List<InventoryItem> allMeds) async {
    setState(() => _isGenerating = true);
    try {
      final optimizer = ref.read(optimizationServiceProvider);
      final router = ref.read(routingServiceProvider);
      final ai = ref.read(aiServiceProvider);

      Map<String, List<InventoryItem>> inventories = {};
      for (var med in allMeds) {
        if (med.facilityId != null) {
          inventories.putIfAbsent(med.facilityId!, () => []).add(med);
        }
      }

      // 1. Calculate optimal transfers
      final recs = optimizer.calculateOptimalTransfers(
        facilities: _facilities,
        inventories: inventories,
        requests: requests,
      );

      // 2. Fetch road-accurate routes for each recommendation
      Map<String, List<LatLng>> routes = {};
      for (var rec in recs) {
        final start = LatLng(rec.donor.latitude, rec.donor.longitude);
        final end = LatLng(rec.recipient.latitude, rec.recipient.longitude);
        final path = await router.getRoute(start, end);
        routes['${rec.donor.id}_${rec.recipient.id}'] = path;
      }

      // 3. Generate AI Summary
      final summary =
          await ai.generateRedistributionPlan(requests, _facilities);

      debugPrint(
          'RouteOptimizationMap: Generated ${recs.length} recommendations.');
      debugPrint('RouteOptimizationMap: Fetched ${routes.length} road routes.');

      setState(() {
        _recommendations = recs;
        _roadRoutes = routes;
        _aiSummary = summary;
        _showRoutes = true;
      });
    } catch (e) {
      debugPrint('RouteOptimizationMap Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error generating routes: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final mapCenter = _facilities.isNotEmpty
        ? LatLng(_facilities.first.latitude, _facilities.first.longitude)
        : const LatLng(28.6139, 77.2090);

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('Advanced Route Optimization')),
      body: StreamBuilder<List<InventoryItem>>(
        stream: ref.watch(firebaseServiceProvider).streamAllMedicines(),
        builder: (context, invSnapshot) {
          final allMeds = invSnapshot.data ?? [];

          return StreamBuilder<List<MedRequest>>(
            stream: ref.watch(firebaseServiceProvider).streamRequests(null),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];

              return Row(
                children: [
                  // Left Panel: Logistics Details
                  Container(
                    width: 400,
                    color: MediColors.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Transfer Manifest',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: MediColors.textPrimary)),
                              const SizedBox(height: 8),
                              const Text(
                                  'Smart-scored redistribution paths factoring in rural priority and expiry risks.',
                                  style: TextStyle(
                                      color: MediColors.textSecondary,
                                      fontSize: 13)),
                              const SizedBox(height: 16),
                              if (_aiSummary.isNotEmpty && _showRoutes)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: MediColors.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: MediColors.primary
                                              .withValues(alpha: 0.2))),
                                  child: Text(_aiSummary,
                                      style: const TextStyle(
                                          color: MediColors.primaryLight,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 13)),
                                ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: Container(
                                  decoration: BoxDecoration(
                                      gradient: MediColors.primaryGradient,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent),
                                    icon: _isGenerating
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2))
                                        : Icon(_showRoutes
                                            ? Icons.refresh_rounded
                                            : Icons.auto_awesome),
                                    label: Text(_showRoutes
                                        ? 'Re-optimize Routes'
                                        : 'Generate Optimal Routes'),
                                    onPressed: _isGenerating
                                        ? null
                                        : () =>
                                            _generateOptimalRoutes(requests, allMeds),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: TextButton.icon(
                                  icon: const Icon(Icons.science_outlined,
                                      size: 16),
                                  label: const Text('Simulate Demo Scenario',
                                      style: TextStyle(fontSize: 12)),
                                  onPressed: () async {
                                    setState(() => _isGenerating = true);
                                    await ref
                                        .read(firebaseServiceProvider)
                                        .seedDemoData();
                                    // RE-LOAD FACILITIES AFTER SEEDING
                                    await _loadData();
                                    setState(() => _isGenerating = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Demo scenario seeded! Click Generate to see routes.')));
                                    }
                                  },
                                ),
                              ),
                              if (_showRoutes)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextButton(
                                    onPressed: () =>
                                        setState(() => _showRoutes = false),
                                    child: const Center(
                                        child: Text('Clear Map',
                                            style: TextStyle(
                                                color: MediColors.textMuted))),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: !_showRoutes
                              ? const Center(
                                  child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.map_outlined,
                                        size: 48, color: MediColors.textMuted),
                                    SizedBox(height: 12),
                                    Text('Click Generate to start analysis',
                                        style: TextStyle(
                                            color: MediColors.textMuted)),
                                  ],
                                ))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(24),
                                  itemCount: _recommendations.length,
                                  itemBuilder: (context, index) {
                                    final rec = _recommendations[index];
                                    return _buildTransferCard(rec);
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),

                  // Right Panel: Map
                  Expanded(
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: mapCenter,
                            initialZoom: 10.0,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.mediflow.app',
                            ),
                            if (_showRoutes)
                              PolylineLayer(
                                polylines:
                                    _recommendations.map<Polyline>((rec) {
                                  final key =
                                      '${rec.donor.id}_${rec.recipient.id}';
                                  final points = _roadRoutes[key] ??
                                      [
                                        LatLng(rec.donor.latitude,
                                            rec.donor.longitude),
                                        LatLng(rec.recipient.latitude,
                                            rec.recipient.longitude)
                                      ];
                                  return Polyline(
                                    points: points,
                                    color: (rec.recipient.type == 'rural'
                                            ? Colors.blueAccent
                                            : MediColors.primary)
                                        .withValues(alpha: 0.8),
                                    strokeWidth: 6.0,
                                  );
                                }).toList(),
                              ),
                            MarkerLayer(
                              markers: _facilities.map((f) {
                                bool isDonor = _recommendations
                                    .any((r) => r.donor.id == f.id);
                                bool isRecipient = _recommendations
                                    .any((r) => r.recipient.id == f.id);

                                Color markerColor = MediColors.textMuted;
                                if (_showRoutes) {
                                  if (isDonor) {
                                    markerColor = Colors.green;
                                  } else if (isRecipient) {
                                    markerColor = Colors.orange;
                                  }
                                }

                                return Marker(
                                  point: LatLng(f.latitude, f.longitude),
                                  width: 100,
                                  height: 70,
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                              alpha: 0.2),
                                                      blurRadius: 4)
                                                ],
                                              ),
                                            ),
                                            Icon(Icons.local_hospital_rounded,
                                                color: markerColor, size: 28),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: MediColors.surface
                                                .withValues(alpha: 0.9),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: MediColors.border,
                                                width: 0.5),
                                          ),
                                          child: Text(
                                            f.name,
                                            style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: MediColors.textPrimary),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                        // Zoom Controls
                        Positioned(
                          top: 24,
                          right: 24,
                          child: Column(
                            children: [
                              _buildMapControl(Icons.add, () {
                                _mapController.move(
                                    _mapController.camera.center,
                                    _mapController.camera.zoom + 1);
                              }),
                              const SizedBox(height: 8),
                              _buildMapControl(Icons.remove, () {
                                _mapController.move(
                                    _mapController.camera.center,
                                    _mapController.camera.zoom - 1);
                              }),
                            ],
                          ),
                        ),
                        // Legend
                        Positioned(
                          bottom: 24,
                          right: 24,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: MediColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: MediColors.border)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Optimization Legend',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: MediColors.textPrimary)),
                                const SizedBox(height: 12),
                                _buildLegendItem(
                                    Colors.green, 'Donor Site (Surplus)'),
                                _buildLegendItem(
                                    Colors.orange, 'Recipient Site (Deficit)'),
                                _buildLegendItem(
                                    Colors.blueAccent, 'Rural Priority Route'),
                                _buildLegendItem(
                                    MediColors.primary, 'Standard Route'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMapControl(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MediColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: MediColors.textPrimary),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: MediColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTransferCard(TransferRecommendation rec) {
    final Distance distanceCalc = const Distance();
    final distKm = distanceCalc(LatLng(rec.donor.latitude, rec.donor.longitude),
            LatLng(rec.recipient.latitude, rec.recipient.longitude)) /
        1000;
    final timeHours = (distKm / 40);
    final timeMinutes = (timeHours * 60).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: MediColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MediColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: MediColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('Score: ${rec.score.toInt()}',
                    style: const TextStyle(
                        color: MediColors.primaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
              if (rec.recipient.type == 'rural')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('RURAL PRIORITY',
                      style: TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 10)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.outbound_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(rec.donor.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: MediColors.textPrimary))),
          ]),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Icon(Icons.arrow_downward_rounded,
                  color: MediColors.textMuted, size: 16)),
          Row(children: [
            const Icon(Icons.input_rounded, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(rec.recipient.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: MediColors.textPrimary))),
          ]),
          const Divider(height: 32),
          Text(rec.medicine,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: MediColors.textPrimary,
                  fontSize: 15)),
          Text('${rec.quantity} Units requested',
              style:
                  const TextStyle(color: MediColors.textMuted, fontSize: 13)),
          const SizedBox(height: 12),
          Text(rec.reasoning,
              style: const TextStyle(
                  color: MediColors.primaryLight,
                  fontSize: 11,
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                const Icon(Icons.route_rounded,
                    size: 14, color: MediColors.textMuted),
                const SizedBox(width: 4),
                Text('${distKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        color: MediColors.textMuted, fontSize: 12))
              ]),
              Row(children: [
                const Icon(Icons.schedule_rounded,
                    size: 14, color: MediColors.textMuted),
                const SizedBox(width: 4),
                Text('${timeMinutes}m est.',
                    style: const TextStyle(
                        color: MediColors.textMuted, fontSize: 12))
              ]),
            ],
          ),
        ],
      ),
    );
  }
}
