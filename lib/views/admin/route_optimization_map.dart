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
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';
import '../shared/skeleton_loaders.dart';

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
  String? _errorMessage;
  bool _showRoutes = false;
  bool _isGenerating = false;
  String _aiSummary = '';
  List<MultiStopRoute> _multiStopRoutes = [];
  // Stores the full RouteResult (polyline + road distance/duration) for each
  // multi-stop route, keyed by the donor facility id.
  Map<String, RouteResult> _roadRoutes = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_isLoading && _errorMessage == null && _facilities.isNotEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final firebaseService = ref.read(firebaseServiceProvider);
      final facs = await firebaseService.getFacilities();

      if (mounted) {
        setState(() {
          _facilities = facs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('RouteOptimizationMap: Failed to load facilities: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Unable to load facilities. Please check your connection and try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generateOptimalRoutes(
      List<MedRequest> requests, List<InventoryItem> allMeds) async {
    setState(() => _isGenerating = true);
    try {
      final firebaseService = ref.read(firebaseServiceProvider);
      if (_facilities.isEmpty) {
        final freshFacs = await firebaseService
            .getFacilities()
            .catchError((_) => <Facility>[]);
        if (freshFacs.isNotEmpty) {
          _facilities = freshFacs;
        }
      }
      final freshRequests = await firebaseService
          .getRequestsOnce()
          .catchError((_) => <MedRequest>[]);
      final freshMeds = await firebaseService
          .getAllMedicinesOnce()
          .catchError((_) => <InventoryItem>[]);
      final activeRequests =
          freshRequests.isNotEmpty ? freshRequests : requests;
      final activeMeds = freshMeds.isNotEmpty ? freshMeds : allMeds;

      final optimizer = ref.read(optimizationServiceProvider);
      final router = ref.read(routingServiceProvider);
      final ai = ref.read(aiServiceProvider);

      Map<String, List<InventoryItem>> inventories = {};
      for (var med in activeMeds) {
        if (med.facilityId != null) {
          inventories.putIfAbsent(med.facilityId!, () => []).add(med);
        }
      }

      // 1. Calculate optimal transfers grouped into multi-stop routes
      final multiRoutes = optimizer.calculateMultiStopRoutes(
        facilities: _facilities,
        inventories: inventories,
        requests: activeRequests,
      );

      // 2. Fetch road-accurate routes for each multi-stop route and leg
      Map<String, RouteResult> routes = {};
      for (var mr in multiRoutes) {
        if (mr.stops.isEmpty) continue;
        final stopsCoords =
            mr.stops.map((f) => LatLng(f.latitude, f.longitude)).toList();
        final result = await router.getMultiStopRoute(stopsCoords);
        routes[mr.transfers.first.donor.id] = result;

        for (var rec in mr.transfers) {
          final legResult = await router.getRoute(
            LatLng(rec.donor.latitude, rec.donor.longitude),
            LatLng(rec.recipient.latitude, rec.recipient.longitude),
          );
          routes['${rec.donor.id}_${rec.recipient.id}'] = legResult;
        }
      }

      // 3. Generate AI Summary
      final summary =
          await ai.generateRedistributionPlan(activeRequests, _facilities);

      debugPrint(
          'RouteOptimizationMap: Generated ${multiRoutes.length} multi-stop routes.');
      debugPrint('RouteOptimizationMap: Fetched ${routes.length} road routes.');
      // The route generation kicks off several network requests and the user
      // can navigate away while they are in flight. Guard the post-await
      // setState so we do not touch a disposed State.
      if (!mounted) return;
      setState(() {
        _multiStopRoutes = multiRoutes;
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
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mediTheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: const RouteOptimizationMapSkeleton(),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('Advanced Route Optimization')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 64, color: colors.textMuted),
                const SizedBox(height: 20),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16, color: colors.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                        gradient: colors.primaryGradient,
                        borderRadius: BorderRadius.circular(12)),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                      onPressed: _loadData,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final mapCenter = _facilities.isNotEmpty
        ? LatLng(_facilities.first.latitude, _facilities.first.longitude)
        : const LatLng(28.6139, 77.2090);

    return Scaffold(
      backgroundColor: colors.background,
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
                    color: colors.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Transfer Manifest',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary)),
                              const SizedBox(height: 8),
                              Text(
                                  'Smart-scored redistribution paths factoring in rural priority and expiry risks.',
                                  style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 13)),
                              const SizedBox(height: 16),
                              if (_aiSummary.isNotEmpty && _showRoutes)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: colors.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: colors.primary
                                              .withValues(alpha: 0.2))),
                                  child: Text(_aiSummary,
                                      style: TextStyle(
                                          color: colors.primaryLight,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 13)),
                                ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: Container(
                                  decoration: BoxDecoration(
                                      gradient: colors.primaryGradient,
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
                                        : () => _generateOptimalRoutes(
                                            requests, allMeds),
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
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text(
                                            'Confirm Demo Simulation'),
                                        content: const Text(
                                          'Warning: Simulating demo scenario will wipe existing data and reseed demo data. Are you sure you want to proceed?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            child: const Text('Wipe & Reseed'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirmed != true) return;

                                    setState(() => _isGenerating = true);
                                    try {
                                      final error = await ref
                                          .read(firebaseServiceProvider)
                                          .seedDemoData();
                                      if (error != null) {
                                        messenger.showSnackBar(
                                            SnackBar(content: Text(error)));
                                        return;
                                      }
                                      // RE-LOAD FACILITIES & AUTO GENERATE ROUTES AFTER SEEDING
                                      await _loadData();
                                      await _generateOptimalRoutes([], []);
                                    } catch (e) {
                                      debugPrint(
                                          'RouteOptimizationMap: Demo seed failed: $e');
                                    } finally {
                                      if (mounted) {
                                        setState(() => _isGenerating = false);
                                      }
                                    }
                                    messenger.showSnackBar(const SnackBar(
                                        content: Text(
                                            'Demo scenario seeded! Click Generate to see routes.')));
                                  },
                                ),
                              ),
                              if (_showRoutes)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextButton(
                                    onPressed: () =>
                                        setState(() => _showRoutes = false),
                                    child: Center(
                                        child: Text('Clear Map',
                                            style: TextStyle(
                                                color: colors.textMuted))),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: colors.border),
                        Expanded(
                          child: !_showRoutes
                              ? Center(
                                  child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.map_outlined,
                                        size: 48, color: colors.textMuted),
                                    const SizedBox(height: 12),
                                    Text('Click Generate to start analysis',
                                        style: TextStyle(
                                            color: colors.textMuted)),
                                  ],
                                ))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(24),
                                  itemCount: _multiStopRoutes.length,
                                  itemBuilder: (context, index) {
                                    final mr = _multiStopRoutes[index];
                                    return _buildMultiStopRouteCard(mr, colors);
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
                                polylines: _multiStopRoutes.map<Polyline>((mr) {
                                  final donorId = mr.transfers.first.donor.id;
                                  final routeResult = _roadRoutes[donorId];
                                  final points = routeResult?.points ??
                                      mr.stops
                                          .map((s) =>
                                              LatLng(s.latitude, s.longitude))
                                          .toList();
                                  bool hasRural = mr.stops.any((s) =>
                                      s.type == FacilityType.rural &&
                                      s.id != donorId);
                                  return Polyline(
                                    points: points,
                                    color: (hasRural
                                            ? Colors.blueAccent
                                            : colors.primary)
                                        .withValues(alpha: 0.8),
                                    strokeWidth: 6.0,
                                  );
                                }).toList(),
                              ),
                            MarkerLayer(
                              markers: _facilities.map((f) {
                                bool isDonor = _multiStopRoutes.any((mr) =>
                                    mr.transfers.first.donor.id == f.id);
                                bool isRecipient = _multiStopRoutes.any((mr) =>
                                    mr.stops.skip(1).any((s) => s.id == f.id));

                                Color markerColor = colors.textMuted;
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
                                            color: colors.surface
                                                .withValues(alpha: 0.9),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: colors.border,
                                                width: 0.5),
                                          ),
                                          child: Text(
                                            f.name,
                                            style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: colors.textPrimary),
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
                              }, colors),
                              const SizedBox(height: 8),
                              _buildMapControl(Icons.remove, () {
                                _mapController.move(
                                    _mapController.camera.center,
                                    _mapController.camera.zoom - 1);
                              }, colors),
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
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.border)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Optimization Legend',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colors.textPrimary)),
                                const SizedBox(height: 12),
                                _buildLegendItem(
                                    Colors.green, 'Donor Site (Surplus)', colors),
                                _buildLegendItem(
                                    Colors.orange, 'Recipient Site (Deficit)', colors),
                                _buildLegendItem(
                                    Colors.blueAccent, 'Rural Priority Route', colors),
                                _buildLegendItem(
                                    colors.primary, 'Standard Route', colors),
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

  Widget _buildMapControl(IconData icon, VoidCallback onPressed, MediFlowTheme colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: colors.textPrimary),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, MediFlowTheme colors) {
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
              style: TextStyle(
                  color: colors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMultiStopRouteCard(MultiStopRoute mr, MediFlowTheme colors) {
    if (mr.transfers.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border, width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Multi-Stop Route: ${mr.transfers.first.donor.name}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                        fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...mr.transfers.map((rec) => _buildSingleTransferInfo(rec, colors)),
        ],
      ),
    );
  }

  Widget _buildSingleTransferInfo(TransferRecommendation rec, MediFlowTheme colors) {
    /// Fallback assumed average speed when no road-routing data is available.
    /// Named here as a constant so it is easy to find and change (#252).
    const double kFallbackSpeedKmh = 40.0;

    // Prefer road distance/duration for this specific transfer leg if present,
    // falling back to whole-tour donor route metadata.
    final legKey = '${rec.donor.id}_${rec.recipient.id}';
    final routeResult = _roadRoutes[legKey] ?? _roadRoutes[rec.donor.id];

    // Road distance and duration from the API (null when straight-line
    // fallback was used or the route has not been fetched yet).
    final double? roadDistKm = routeResult?.distanceKm;
    final double? roadDurationSeconds = routeResult?.durationSeconds;

    // Straight-line haversine distance — used only as a fallback.
    const Distance distanceCalc = Distance();
    final double straightLineDistKm = distanceCalc(
          LatLng(rec.donor.latitude, rec.donor.longitude),
          LatLng(rec.recipient.latitude, rec.recipient.longitude),
        ) /
        1000;

    // Resolved display values: prefer road data, fall back to straight-line.
    final bool usingRoadData =
        roadDistKm != null && roadDurationSeconds != null;
    final double displayDistKm =
        usingRoadData ? roadDistKm : straightLineDistKm;
    final int displayTimeMinutes = usingRoadData
        ? (roadDurationSeconds / 60).round()
        : (straightLineDistKm / kFallbackSpeedKmh * 60).round();

    // Label shown next to the ETA so users know what it's based on.
    final String etaLabel = usingRoadData
        ? 'est.'
        : 'est. (straight-line @ ${kFallbackSpeedKmh.toInt()} km/h)';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: colors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: colors.primaryOverlay,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('Score: ${rec.score.toInt()}',
                    style: TextStyle(
                        color: colors.primaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
              if (rec.recipient.type == FacilityType.rural)
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
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary))),
          ]),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Icon(Icons.arrow_downward_rounded,
                  color: colors.textMuted, size: 16)),
          Row(children: [
            const Icon(Icons.input_rounded, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(rec.recipient.name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary))),
          ]),
          Divider(height: 32, color: colors.border),
          Text(rec.medicine,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                  fontSize: 15)),
          Text('${rec.quantity} Units requested',
              style:
                  TextStyle(color: colors.textMuted, fontSize: 13)),
          const SizedBox(height: 12),
          Text(rec.reasoning,
              style: TextStyle(
                  color: colors.primaryLight,
                  fontSize: 11,
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route_rounded,
                      size: 14, color: colors.textMuted),
                  const SizedBox(width: 4),
                  Text('${displayDistKm.toStringAsFixed(1)} km',
                      style: TextStyle(
                          color: colors.textMuted, fontSize: 12)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 14, color: colors.textMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('${displayTimeMinutes}m $etaLabel',
                        style: TextStyle(
                            color: colors.textMuted, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
