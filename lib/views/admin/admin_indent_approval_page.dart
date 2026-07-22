import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../models/request.dart';
import 'package:med_supply_prototype/constants/colors.dart';

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
  final Set<String> _selectedRequestIds = {};
  bool _isActionInProgress = false;

  Future<void> _analyzeRequest(MedRequest request) async {
    setState(() => _aiLoading[request.id] = true);
    try {
      final firebaseService = ref.read(firebaseServiceProvider);
      final aiService = ref.read(aiServiceProvider);

      // Fetch facility inventory for context
      final inventory =
          await firebaseService.getInventoryOnce(request.facilityId);
      final logs =
          await firebaseService.getRecentLogs(request.facilityId, days: 90);

      final currentItem = inventory.firstWhere(
        (i) => i.medicineName == request.medicineName,
        orElse: () => throw 'Medicine not found in facility inventory',
      );

      final forecast =
          await aiService.forecastDemand(request.medicineName, logs, 30);
      final predictedDemand = forecast['prediction'] as int;

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

      setState(() => _aiSuggestions[request.id] = suggestion);
    } catch (e) {
      setState(() => _aiSuggestions[request.id] = 'Error: $e');
    } finally {
      setState(() => _aiLoading[request.id] = false);
    }
  }

  Future<void> _updateStatus(String requestId, RequestStatus status) async {
    setState(() => _isActionInProgress = true);
    try {
      await ref
          .read(firebaseServiceProvider)
          .updateRequestStatus(requestId, status);
      setState(() => _selectedRequestIds.remove(requestId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Request ${status.name} successfully!')));
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

  // ---- Bulk Action Processing ----
  Future<void> _processBulkAction(RequestStatus status) async {
    if (_selectedRequestIds.isEmpty) return;

    setState(() => _isActionInProgress = true);
    final count = _selectedRequestIds.length;
    final idsToProcess = List<String>.from(_selectedRequestIds);

    try {
      final firebaseService = ref.read(firebaseServiceProvider);
      for (final id in idsToProcess) {
        await firebaseService.updateRequestStatus(id, status);
      }

      setState(() => _selectedRequestIds.clear());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Successfully updated $count requests to ${status.name}!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bulk action failed partially/fully: $e')));
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  // ---- Bulk Action Confirmation Dialog ----
  void _confirmBulkAction(RequestStatus status) {
    final count = _selectedRequestIds.length;
    final actionText = status == RequestStatus.approved ? 'approve' : 'decline';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm Bulk ${actionText.toUpperCase()}'),
        content: Text(
            'Are you sure you want to $actionText $count selected request(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: status == RequestStatus.approved
                  ? MediColors.success
                  : MediColors.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _processBulkAction(status);
            },
            child: Text('Confirm $actionText'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MedRequest>>(
      stream: ref.read(firebaseServiceProvider).streamRequests(null),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: MediColors.bg,
            appBar: AppBar(title: const Text('Pending Requests Approval')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final pending = snapshot.data
                ?.where((r) => r.status == RequestStatus.pending)
                .toList() ??
            [];

        final allSelected = pending.isNotEmpty &&
            _selectedRequestIds.length == pending.length;

        return Scaffold(
          backgroundColor: MediColors.bg,
          appBar: AppBar(
            title: Text(_selectedRequestIds.isEmpty
                ? 'Pending Requests Approval'
                : '${_selectedRequestIds.length} Selected'),
            actions: _selectedRequestIds.isNotEmpty
                ? [
                    TextButton.icon(
                      onPressed: _isActionInProgress
                          ? null
                          : () => _confirmBulkAction(RequestStatus.rejected),
                      icon: const Icon(Icons.close_rounded,
                          color: MediColors.error, size: 18),
                      label: const Text('Decline Selected',
                          style: TextStyle(color: MediColors.error)),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: MediColors.success),
                        onPressed: _isActionInProgress
                            ? null
                            : () => _confirmBulkAction(RequestStatus.approved),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve Selected'),
                      ),
                    ),
                  ]
                : null,
          ),
          body: pending.isEmpty
              ? const Center(
                  child: Text('No pending requests.',
                      style: TextStyle(color: MediColors.textMuted)))
              : Column(
                  children: [
                    // Header Toolbar with Select All option
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      color: MediColors.surface,
                      child: Row(
                        children: [
                          Checkbox(
                            value: allSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedRequestIds.addAll(
                                      pending.map((r) => r.id));
                                } else {
                                  _selectedRequestIds.clear();
                                }
                              });
                            },
                          ),
                          Text(
                            allSelected ? 'Deselect All' : 'Select All',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: MediColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Total Pending: ${pending.length}',
                            style: const TextStyle(
                              color: MediColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: pending.length,
                        itemBuilder: (context, index) {
                          final req = pending[index];
                          final isAiLoading = _aiLoading[req.id] ?? false;
                          final suggestion = _aiSuggestions[req.id];
                          final isSelected =
                              _selectedRequestIds.contains(req.id);
                          final isRedistribution =
                              req.type == RequestType.surplus;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected
                                    ? MediColors.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (checked) {
                                          setState(() {
                                            if (checked == true) {
                                              _selectedRequestIds.add(req.id);
                                            } else {
                                              _selectedRequestIds
                                                  .remove(req.id);
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  req.medicineName,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: MediColors.textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: isRedistribution
                                                        ? MediColors.success
                                                            .withValues(
                                                                alpha: 0.1)
                                                        : MediColors.error
                                                            .withValues(
                                                                alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
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
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: MediColors.surfaceLight,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${req.quantity} Units',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: MediColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (req.notes != null)
                                    Text(
                                      'Facility Notes: ${req.notes}',
                                      style: const TextStyle(
                                        color: MediColors.textSecondary,
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),

                                  const SizedBox(height: 24),
                                  const Divider(),
                                  const SizedBox(height: 16),

                                  // AI Suggestion Box
                                  if (suggestion != null)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      margin:
                                          const EdgeInsets.only(bottom: 20),
                                      decoration: BoxDecoration(
                                        color: suggestion.contains('✅')
                                            ? MediColors.success
                                                .withValues(alpha: 0.1)
                                            : MediColors.warning
                                                .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: suggestion.contains('✅')
                                              ? MediColors.success
                                                  .withValues(alpha: 0.3)
                                              : MediColors.warning
                                                  .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        suggestion,
                                        style: TextStyle(
                                          color: suggestion.contains('✅')
                                              ? MediColors.success
                                              : MediColors.warning,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),

                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: isAiLoading
                                            ? null
                                            : () => _analyzeRequest(req),
                                        icon: isAiLoading
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2),
                                              )
                                            : const Icon(Icons.auto_awesome,
                                                size: 16),
                                        label: const Text('Analyze with AI'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              MediColors.primaryLight,
                                        ),
                                      ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: _isActionInProgress
                                            ? null
                                            : () => _updateStatus(
                                                  req.id,
                                                  RequestStatus.rejected,
                                                ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: MediColors.error,
                                        ),
                                        child: const Text('Decline'),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton(
                                        onPressed: _isActionInProgress
                                            ? null
                                            : () => _updateStatus(
                                                  req.id,
                                                  RequestStatus.approved,
                                                ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: MediColors.success,
                                        ),
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
                ),
        );
      },
    );
  }
}
