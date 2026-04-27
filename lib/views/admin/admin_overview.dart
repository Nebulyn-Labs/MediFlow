import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/firebase_service.dart';
import '../../models/facility.dart';
import '../../models/request.dart';
import '../../main.dart';

class AdminOverview extends ConsumerStatefulWidget {
  const AdminOverview({super.key});

  @override
  ConsumerState<AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends ConsumerState<AdminOverview> {
  List<Facility> _facilities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final facs = await ref.read(firebaseServiceProvider).getFacilities();
    if (mounted) setState(() { _facilities = facs; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Central Management System', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: MediColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('Global supply chain intelligence', style: TextStyle(color: MediColors.textSecondary, fontSize: 14)),
                  const SizedBox(height: 28),

                  // KPI Row
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      _buildKpi('Facilities', '${_facilities.length}', Icons.business_rounded, MediColors.info),
                      _buildKpi('Active Regions', '${_facilities.map((f) => f.region).toSet().length}', Icons.public_rounded, MediColors.teal),
                    ],
                  ),
                  const SizedBox(height: 36),

                  // Two column layout
                  LayoutBuilder(builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 900;
                    final facilities = _buildFacilitiesSection();
                    final requests = _buildRequestsSection();
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: facilities),
                          const SizedBox(width: 24),
                          Expanded(child: requests),
                        ],
                      );
                    }
                    return Column(children: [facilities, const SizedBox(height: 24), requests]);
                  }),
                ],
              ),
            ),
    );
  }

  Widget _buildKpi(String title, String value, IconData icon, Color accent) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: accent)),
            Text(title, style: const TextStyle(fontSize: 12, color: MediColors.textSecondary)),
          ]),
        ],
      ),
    );
  }

  Widget _buildFacilitiesSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MediColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: MediColors.info.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.business_rounded, color: MediColors.info, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Registered Facilities', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: MediColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          ..._facilities.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MediColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MediColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(gradient: MediColors.cyanGradient, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600, color: MediColors.textPrimary)),
                      Text('${f.type} • ${f.region}', style: const TextStyle(fontSize: 12, color: MediColors.textMuted)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: MediColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Online', style: TextStyle(color: MediColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildRequestsSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MediColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: MediColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.receipt_long_rounded, color: MediColors.warning, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Incoming Requests', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: MediColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          StreamBuilder<List<MedRequest>>(
            stream: ref.read(firebaseServiceProvider).streamRequests(null),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final allRequests = snap.data ?? [];
              final requests = allRequests.where((r) => r.status == RequestStatus.pending).toList();
              if (requests.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('No pending requests', style: TextStyle(color: MediColors.textMuted))),
                );
              }
              return Column(
                children: requests.take(6).map((req) {
                  final facName = _facilities.firstWhere(
                    (f) => f.id == req.facilityId,
                    orElse: () => Facility(id: '', name: 'Unknown', email: '', type: '', region: '', latitude: 0, longitude: 0, createdAt: DateTime.now()),
                  ).name;
                  final isCrit = req.type == RequestType.shortage;
                  return _buildRequestItem(facName, req.medicineName, req.quantity, isCrit, req.id);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(String facility, String medicine, int qty, bool isCritical, String requestId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MediColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isCritical ? MediColors.error.withValues(alpha: 0.3) : MediColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 4, height: 40,
              decoration: BoxDecoration(
                color: isCritical ? MediColors.error : MediColors.info,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(facility, style: const TextStyle(fontWeight: FontWeight.w600, color: MediColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 2),
                Text('$medicine • $qty units', style: const TextStyle(fontSize: 12, color: MediColors.textMuted)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (isCritical ? MediColors.error : MediColors.info).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isCritical ? 'Critical' : 'Routine',
                style: TextStyle(color: isCritical ? MediColors.error : MediColors.info, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.check_circle_rounded, color: MediColors.success, size: 22),
              tooltip: 'Approve',
              onPressed: () async {
                await ref.read(firebaseServiceProvider).updateRequestStatus(requestId, RequestStatus.approved);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Approved ✓')));
              },
            ),
            IconButton(
              icon: const Icon(Icons.cancel_rounded, color: MediColors.error, size: 22),
              tooltip: 'Reject',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reject Request?'),
                    content: Text('Reject $medicine from $facility?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(backgroundColor: MediColors.error),
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(firebaseServiceProvider).updateRequestStatus(requestId, RequestStatus.rejected);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rejected ✗')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
