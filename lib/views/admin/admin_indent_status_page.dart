import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/firebase_service.dart';
import '../../services/csv_export_service.dart';
import '../../models/request.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class AdminIndentStatusPage extends ConsumerStatefulWidget {
  const AdminIndentStatusPage({super.key});

  @override
  ConsumerState<AdminIndentStatusPage> createState() =>
      _AdminIndentStatusPageState();
}

class _AdminIndentStatusPageState extends ConsumerState<AdminIndentStatusPage> {
  bool _isExportingCsv = false;

  List<MedRequest> _buildVisibleRequests(List<MedRequest>? source) {
    final requests =
        source?.where((r) => r.status != RequestStatus.draft).toList() ?? [];
    requests.sort((a, b) => b.requestDate.compareTo(a.requestDate));
    return requests;
  }

  Future<void> _exportTransferRequestsCsv(List<MedRequest> requests) async {
    if (requests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transfer requests to export yet')));
      return;
    }

    setState(() => _isExportingCsv = true);
    try {
      await CsvExportService.exportTransferRequests(requests);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer requests CSV exported ✓')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExportingCsv = false);
    }
  }

  Future<void> _updateStatus(String requestId, RequestStatus status) async {
    try {
      await ref
          .read(firebaseServiceProvider)
          .updateRequestStatus(requestId, status);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Color _getStatusColor(RequestStatus status) {
    switch (status) {
      case RequestStatus.approved:
        return MediColors.success;
      case RequestStatus.rejected:
        return MediColors.error;
      case RequestStatus.pending:
        return MediColors.warning;
      case RequestStatus.fulfilled:
        return MediColors.info;
      case RequestStatus.draft:
        return MediColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('Supply Status')),
      body: StreamBuilder<List<MedRequest>>(
        stream: ref.read(firebaseServiceProvider).streamRequests(null),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = _buildVisibleRequests(snapshot.data);

          if (requests.isEmpty) {
            return const Center(
                child: Text('No supply requests found.',
                    style: TextStyle(color: MediColors.textMuted)));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _isExportingCsv
                        ? null
                        : () => _exportTransferRequestsCsv(requests),
                    icon: _isExportingCsv
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Export CSV'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MediColors.textSecondary,
                      side: const BorderSide(color: MediColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      _buildTableHeader(),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: requests.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final req = requests[index];
                          return _buildTableRow(req);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: MediColors.surfaceLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: const Row(
        children: [
          Expanded(
              flex: 2,
              child: Text('Date',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 3,
              child: Text('Facility',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 3,
              child: Text('Medicine',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Quantity',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Status',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 3,
              child: Text('Global Optimization',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 1,
              child: Text('',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildTableRow(MedRequest req) {
    final isApproved = req.status == RequestStatus.approved;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text('${req.requestDate.day}/${req.requestDate.month}',
                  style: const TextStyle(color: MediColors.textSecondary))),
          Expanded(
              flex: 3,
              child: Text(req.facilityId.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: MediColors.textPrimary,
                      fontSize: 13))),
          Expanded(
              flex: 3,
              child: Text(req.medicineName,
                  style: const TextStyle(color: MediColors.textPrimary))),
          Expanded(
              flex: 2,
              child: Text(req.quantity.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(req.status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(req.status.name.toUpperCase(),
                  style: TextStyle(
                      color: _getStatusColor(req.status),
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
          Expanded(
            flex: 3,
            child: isApproved
                ? Center(
                    child: TextButton.icon(
                      onPressed: () => context.go('/admin/routing'),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                      label: const Text('Optimize Routes',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        foregroundColor: MediColors.primary,
                        backgroundColor:
                            MediColors.primary.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  )
                : const Center(
                    child: Text('—',
                        style: TextStyle(color: MediColors.textMuted))),
          ),
          Expanded(
            flex: 1,
            child: PopupMenuButton<RequestStatus>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: MediColors.textMuted, size: 20),
              onSelected: (status) => _updateStatus(req.id, status),
              itemBuilder: (context) => RequestStatus.values
                  .where((s) => s != RequestStatus.draft)
                  .map((status) {
                return PopupMenuItem(
                  value: status,
                  child: Text(status.name.toUpperCase(),
                      style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
