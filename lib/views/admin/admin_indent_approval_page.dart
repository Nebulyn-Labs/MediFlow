import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../services/csv_export_service.dart';
import '../../models/request.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import '../shared/skeleton_loaders.dart';

class AdminIndentApprovalPage extends ConsumerStatefulWidget {
  const AdminIndentApprovalPage({super.key});

  @override
  ConsumerState<AdminIndentApprovalPage> createState() =>
      _AdminIndentApprovalPageState();
}

class _AdminIndentApprovalPageState
    extends ConsumerState<AdminIndentApprovalPage> {
  final Map<String, String?> _aiSuggestions = {};
  final Map<String, bool> _aiLoading = {};
  bool _isActionInProgress = false;
  bool _isExportingCsv = false;
  final Set<String> _selectedRequestIds = {};
  late final Stream<List<MedRequest>> _requestsStream;

  @override
  void initState() {
    super.initState();
    _requestsStream = ref.read(firebaseServiceProvider).streamRequests(
      null,
      statuses: const [RequestStatus.pending],
    );
  }

  /// Facility-scoped cache for the expensive reads that back AI analysis
  /// (full inventory + 90 days of usage logs). Several pending requests
  /// usually belong to the same facility, so without this every "Analyze
  /// with AI" click re-issued identical Firestore queries.
  ///
  /// Keyed by `<kind>:<facilityId>`. Futures are cached rather than values,
  /// so two analyses started back-to-back share a single in-flight read.
  final Map<String, Future<Object?>> _facilityDataCache = {};

  Future<T> _cachedFacilityRead<T>(String key, Future<T> Function() read) {
    final cached = _facilityDataCache[key];
    if (cached != null) return cached as Future<T>;

    final future = read();
    _facilityDataCache[key] = future;

    // A failed read must not poison the cache — drop it so the next attempt
    // refetches. This side-listener also marks the future's error as observed,
    // so it is never reported as an unhandled async error.
    future.then<void>((_) {}, onError: (Object _) {
      _facilityDataCache.remove(key);
    });

    return future;
  }

  /// Approving/declining changes what the facility holds, so the cached
  /// snapshot is stale afterwards. Drop it and let the next analysis refetch.
  void _invalidateFacilityCache(String facilityId) {
    _facilityDataCache.remove('inventory:$facilityId');
    _facilityDataCache.remove('logs:$facilityId');
  }

  Future<void> _analyzeRequest(MedRequest request) async {
    debugPrint('🟢 [ANALYZE] ${request.medicineName} '
        'cache=${_facilityDataCache.keys.toList()} '
        'state=${identityHashCode(this)}');
    setState(() => _aiLoading[request.id] = true);
    try {
      final firebaseService = ref.read(firebaseServiceProvider);
      final aiService = ref.read(aiServiceProvider);

      // Fetch facility inventory + usage logs for context. Both go through the
      // per-facility cache, and both are started before the first await so the
      // initial (uncached) analysis issues them in parallel instead of serially.
      final inventoryFuture = _cachedFacilityRead(
        'inventory:${request.facilityId}',
        () => firebaseService.getInventoryOnce(request.facilityId),
      );
      final logsFuture = _cachedFacilityRead(
        'logs:${request.facilityId}',
        () => firebaseService.getRecentLogs(request.facilityId, days: 90),
      );

      final inventory = await inventoryFuture;
      final logs = await logsFuture;

      final currentItem = inventory.firstWhere(
        (i) => i.medicineName == request.medicineName,
        orElse: () => throw 'Medicine not found in facility inventory',
      );

      final forecast =
          await aiService.forecastDemand(request.medicineName, logs, 30);
      final predRaw = forecast['prediction'];
      int predictedDemand = 0;
      if (predRaw is num) {
        predictedDemand = predRaw.toInt();
      } else if (predRaw is String) {
        predictedDemand = double.tryParse(predRaw)?.toInt() ?? 0;
      }

      String suggestion;
      if (request.quantity > (predictedDemand * 1.5)) {
        suggestion =
            '⚠️ REDUCE: Request is 50%+ higher than predicted 30-day demand ($predictedDemand).';
      } else if (currentItem.remainingQuantity > predictedDemand) {
        suggestion =
            '⚠️ DECLINE: Facility already has enough stock (${currentItem.remainingQuantity}) for predicted demand ($predictedDemand).';
      } else {
        suggestion =
            '✅ APPROVE: Request is aligned with historical usage and current low stock.';
      }

      // The AI call is slow enough that the user can navigate away mid-analysis.
      // Guard the post-await setState to avoid writing to a disposed State.
      if (!mounted) return;
      setState(() => _aiSuggestions[request.id] = suggestion);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiSuggestions[request.id] = 'Error: $e');
    } finally {
      if (mounted) setState(() => _aiLoading[request.id] = false);
    }
  }

  Future<void> _updateStatus(MedRequest request, RequestStatus status) async {
    final actionVerb = status == RequestStatus.approved ? 'approve' : 'decline';
    final actionNoun =
        status == RequestStatus.approved ? 'Approval' : 'Decline';
    final confirmed = await _showConfirmationDialog(
      title: 'Confirm $actionNoun',
      message:
          'Are you sure you want to $actionVerb the request for ${request.medicineName}?',
      confirmLabel: status == RequestStatus.approved ? 'Approve' : 'Decline',
      confirmColor: status == RequestStatus.approved
          ? MediColors.success
          : MediColors.error,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionInProgress = true);
    try {
      await ref
          .read(firebaseServiceProvider)
          .updateRequestStatus(request.id, status);
      _invalidateFacilityCache(request.facilityId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Request ${status.label} successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _bulkUpdateStatus(
      List<MedRequest> selectedRequests, RequestStatus status) async {
    if (selectedRequests.isEmpty) return;
    final actionVerb = status == RequestStatus.approved ? 'approve' : 'decline';
    final actionPast =
        status == RequestStatus.approved ? 'approved' : 'declined';
    final count = selectedRequests.length;

    final confirmed = await _showConfirmationDialog(
      title:
          'Confirm Bulk ${status == RequestStatus.approved ? 'Approval' : 'Decline'}',
      message:
          'Are you sure you want to $actionVerb $count selected request(s)?',
      confirmLabel: status == RequestStatus.approved ? 'Approve' : 'Decline',
      confirmColor: status == RequestStatus.approved
          ? MediColors.success
          : MediColors.error,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionInProgress = true);
    try {
      final firebaseService = ref.read(firebaseServiceProvider);
      for (final req in selectedRequests) {
        await firebaseService.updateRequestStatus(req.id, status);
        _invalidateFacilityCache(req.facilityId);
      }
      if (mounted) {
        setState(() {
          _selectedRequestIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully $actionPast $count request(s)!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed bulk operation: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _bulkAnalyze(List<MedRequest> selectedRequests) async {
    if (selectedRequests.isEmpty) return;
    final count = selectedRequests.length;

    final confirmed = await _showConfirmationDialog(
      title: 'Confirm Bulk AI Analysis',
      message:
          'Are you sure you want to run AI analysis on $count selected request(s)?',
      confirmLabel: 'Analyze',
      confirmColor: MediColors.primaryLight,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionInProgress = true);
    try {
      for (final req in selectedRequests) {
        await _analyzeRequest(req);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bulk AI analysis completed for $count request(s)!'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _exportIndentRequestsCsv(List<MedRequest> requests) async {
    if (requests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No indent requests to export yet')));
      return;
    }

    setState(() => _isExportingCsv = true);
    try {
      await CsvExportService.exportIndentRequests(requests);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Indent requests CSV exported ✓')));
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

  Future<bool?> _showConfirmationDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MediColors.surface,
        title:
            Text(title, style: const TextStyle(color: MediColors.textPrimary)),
        content: Text(message,
            style: const TextStyle(color: MediColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: MediColors.textMuted)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('Pending Requests Approval')),
      body: StreamBuilder<List<MedRequest>>(
        stream: _requestsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AdminIndentApprovalSkeleton();
          }

          final pending = MedRequest.filterPending(snapshot.data ?? const []);

          if (pending.isEmpty) {
            return const Center(
                child: Text('No pending requests.',
                    style: TextStyle(color: MediColors.textMuted)));
          }

          final pendingIds = pending.map((e) => e.id).toSet();
          final validSelected = _selectedRequestIds.intersection(pendingIds);

          final allSelected =
              pending.isNotEmpty && validSelected.length == pending.length;
          final selectedRequests =
              pending.where((req) => validSelected.contains(req.id)).toList();

          return Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                color: MediColors.surface,
                child: Row(
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          key: const Key('bulk_select_all_checkbox'),
                          value: allSelected,
                          onChanged: _isActionInProgress
                              ? null
                              : (bool? checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedRequestIds.addAll(pendingIds);
                                    } else {
                                      _selectedRequestIds.clear();
                                    }
                                  });
                                },
                        ),
                        Text(
                          'Select All (${validSelected.length}/${pending.length})',
                          style: const TextStyle(
                            color: MediColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      key: const Key('export_indent_csv_button'),
                      onPressed: _isExportingCsv
                          ? null
                          : () => _exportIndentRequestsCsv(pending),
                      icon: _isExportingCsv
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('Export CSV'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MediColors.textSecondary,
                        side: const BorderSide(color: MediColors.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const Key('bulk_analyze_button'),
                      onPressed: (_isActionInProgress || validSelected.isEmpty)
                          ? null
                          : () => _bulkAnalyze(selectedRequests),
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('Bulk Analyze'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MediColors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      key: const Key('bulk_decline_button'),
                      onPressed: (_isActionInProgress || validSelected.isEmpty)
                          ? null
                          : () => _bulkUpdateStatus(
                              selectedRequests, RequestStatus.rejected),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Bulk Decline'),
                      style: TextButton.styleFrom(
                        foregroundColor: MediColors.error,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('bulk_approve_button'),
                      onPressed: (_isActionInProgress || validSelected.isEmpty)
                          ? null
                          : () => _bulkUpdateStatus(
                              selectedRequests, RequestStatus.approved),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Bulk Approve'),
                      style: FilledButton.styleFrom(
                        backgroundColor: MediColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: MediColors.border),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: pending.length,
                  itemBuilder: (context, index) {
                    final req = pending[index];
                    final isAiLoading = _aiLoading[req.id] ?? false;
                    final suggestion = _aiSuggestions[req.id];
                    final isSelected = validSelected.contains(req.id);
                    final isRedistribution = req.type == RequestType.surplus;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected
                              ? MediColors.primary
                              : MediColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Checkbox(
                                          key: Key('checkbox_${req.id}'),
                                          value: isSelected,
                                          onChanged: _isActionInProgress
                                              ? null
                                              : (bool? checked) {
                                                  setState(() {
                                                    if (checked == true) {
                                                      _selectedRequestIds
                                                          .add(req.id);
                                                    } else {
                                                      _selectedRequestIds
                                                          .remove(req.id);
                                                    }
                                                  });
                                                },
                                        ),
                                        const SizedBox(width: 8),
                                        Text(req.medicineName,
                                            style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: MediColors.textPrimary)),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isRedistribution
                                                ? MediColors.successOverlay
                                                : MediColors.errorOverlay,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isRedistribution
                                                ? 'REDISTRIBUTION REQUEST'
                                                : 'RESTOCK REQUEST',
                                            style: TextStyle(
                                              color: isRedistribution
                                                  ? MediColors.success
                                                  : MediColors.error,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Facility: ${req.facilityId.replaceAll('_', ' ').toUpperCase()}',
                                        style: const TextStyle(
                                            color: MediColors.primaryLight,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                      color: MediColors.surfaceLight,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text('${req.quantity} Units',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: MediColors.textPrimary)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (req.notes != null)
                              Text('Facility Notes: ${req.notes}',
                                  style: const TextStyle(
                                      color: MediColors.textSecondary,
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic)),

                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            // AI Suggestion Box
                            if (suggestion != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: suggestion.contains('✅')
                                      ? MediColors.successOverlay
                                      : MediColors.warningOverlay,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: suggestion.contains('✅')
                                          ? MediColors.success
                                              .withValues(alpha: 0.3)
                                          : MediColors.warning
                                              .withValues(alpha: 0.3)),
                                ),
                                child: Text(suggestion,
                                    style: const TextStyle(
                                        color: MediColors.textPrimary,
                                        fontWeight: FontWeight.w500)),
                              ),

                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed:
                                      (isAiLoading || _isActionInProgress)
                                          ? null
                                          : () => _analyzeRequest(req),
                                  icon: isAiLoading
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.auto_awesome,
                                          size: 16),
                                  label: const Text('Analyze with AI'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: MediColors.primaryLight),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _isActionInProgress
                                      ? null
                                      : () => _updateStatus(
                                          req, RequestStatus.rejected),
                                  style: TextButton.styleFrom(
                                      foregroundColor: MediColors.error),
                                  child: const Text('Decline'),
                                ),
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: _isActionInProgress
                                      ? null
                                      : () => _updateStatus(
                                          req, RequestStatus.approved),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: MediColors.success),
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
