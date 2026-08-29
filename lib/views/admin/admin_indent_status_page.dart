import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/firebase_service.dart';
import '../../services/csv_export_service.dart';
import '../../models/request.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';
import '../shared/skeleton_loaders.dart';
import '../../utils/date_formatter.dart';

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

  List<RequestStatus> _getValidTransitions(RequestStatus currentStatus) {
    switch (currentStatus) {
      case RequestStatus.pending:
        return [RequestStatus.approved, RequestStatus.rejected];
      case RequestStatus.approved:
        return [RequestStatus.dispatched, RequestStatus.rejected];
      case RequestStatus.dispatched:
        return [RequestStatus.inTransit];
      case RequestStatus.inTransit:
        return [RequestStatus.received];
      case RequestStatus.received:
        return [RequestStatus.verified];
      case RequestStatus.rejected:
        return [RequestStatus.pending];
      case RequestStatus.needsManualReview:
        return [RequestStatus.pending, RequestStatus.rejected];
      case RequestStatus.verified:
      case RequestStatus.fulfilled:
      case RequestStatus.draft:
        return [];
    }
  }

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    final colors = context.mediTheme;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(title, style: TextStyle(color: colors.textPrimary)),
        content: Text(message, style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(MedRequest request, RequestStatus status) async {
    final colors = context.mediTheme;
    final statusLabel = status.label.toUpperCase();
    final confirmed = await _showConfirmationDialog(
      title: 'Confirm Status Change',
      message:
          'Are you sure you want to change the status of ${request.medicineName} request to $statusLabel?',
      confirmLabel: statusLabel,
      confirmColor: _getStatusColor(status, colors),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(firebaseServiceProvider)
          .updateRequestStatus(request.id, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Request updated to $statusLabel successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Color _getStatusColor(RequestStatus status, MediFlowTheme colors) {
    switch (status) {
      case RequestStatus.approved:
        return colors.success;
      case RequestStatus.dispatched:
        return colors.primary;
      case RequestStatus.inTransit:
        return colors.primary;
      case RequestStatus.received:
        return colors.success;
      case RequestStatus.verified:
        return colors.success;
      case RequestStatus.rejected:
        return colors.error;
      case RequestStatus.pending:
        return colors.warning;
      case RequestStatus.fulfilled:
        return colors.info;
      case RequestStatus.needsManualReview:
        return colors.violet;
      case RequestStatus.draft:
        return colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mediTheme;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Supply Status')),
      body: StreamBuilder<List<MedRequest>>(
        stream: ref.read(firebaseServiceProvider).streamRequests(null),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AdminIndentStatusSkeleton();
          }

          final requests = _buildVisibleRequests(snapshot.data);

          if (requests.isEmpty) {
            return Center(
                child: Text('No supply requests found.',
                    style: TextStyle(color: colors.textMuted)));
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
                      foregroundColor: colors.textSecondary,
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      _buildTableHeader(colors),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: requests.length,
                        separatorBuilder: (context, index) =>
                            Divider(height: 1, color: colors.border),
                        itemBuilder: (context, index) {
                          final req = requests[index];
                          return _buildTableRow(req, colors);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(MediFlowTheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surfaceLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text('Date',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 3,
              child: Text('Facility',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 3,
              child: Text('Medicine',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Quantity',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Status',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 3,
              child: Text('Global Optimization',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.bold))),
          const Expanded(flex: 1, child: SizedBox()),
        ],
      ),
    );
  }

  Widget _buildTableRow(MedRequest req, MediFlowTheme colors) {
    final isApproved = req.status == RequestStatus.approved;
    final validTransitions = _getValidTransitions(req.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text(DateFormatter.formatDate(req.requestDate),
                  style: TextStyle(color: colors.textSecondary))),
          Expanded(
              flex: 3,
              child: Text(req.facilityId.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      fontSize: 13))),
          Expanded(
              flex: 3,
              child: Text(req.medicineName,
                  style: TextStyle(color: colors.textPrimary))),
          Expanded(
              flex: 2,
              child: Text(req.quantity.toString(),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: colors.textPrimary))),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:
                    _getStatusColor(req.status, colors).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(req.status.label.toUpperCase(),
                  style: TextStyle(
                      color: _getStatusColor(req.status, colors),
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
          Expanded(
            flex: 3,
            child: (req.status == RequestStatus.dispatched ||
                    req.status == RequestStatus.inTransit ||
                    req.status == RequestStatus.received ||
                    req.status == RequestStatus.verified)
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_shipping,
                          size: 16,
                          color:
                              req.status.index >= RequestStatus.dispatched.index
                                  ? colors.primary
                                  : colors.textMuted),
                      Text(' → ',
                          style: TextStyle(color: colors.textMuted)),
                      Icon(Icons.inventory_2,
                          size: 16,
                          color:
                              req.status.index >= RequestStatus.received.index
                                  ? colors.primary
                                  : colors.textMuted),
                      Text(' → ',
                          style: TextStyle(color: colors.textMuted)),
                      Icon(Icons.check_circle,
                          size: 16,
                          color:
                              req.status.index >= RequestStatus.verified.index
                                  ? colors.success
                                  : colors.textMuted),
                    ],
                  )
                : isApproved
                    ? Center(
                        child: TextButton.icon(
                          onPressed: () => context.go('/admin/routing'),
                          icon:
                              const Icon(Icons.auto_fix_high_rounded, size: 14),
                          label: const Text('Optimize Routes',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.primary,
                            backgroundColor:
                                colors.primary.withValues(alpha: 0.08),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      )
                    : Center(
                        child: Text('—',
                            style: TextStyle(color: colors.textMuted))),
          ),
          Expanded(
            flex: 1,
            child: PopupMenuButton<RequestStatus>(
              enabled: validTransitions.isNotEmpty,
              icon: Icon(
                Icons.more_vert_rounded,
                color: validTransitions.isNotEmpty
                    ? colors.textMuted
                    : colors.textMuted.withValues(alpha: 0.3),
                size: 20,
              ),
              onSelected: (status) => _updateStatus(req, status),
              itemBuilder: (context) => validTransitions.map((status) {
                return PopupMenuItem(
                  value: status,
                  child: Text(status.label.toUpperCase(),
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
