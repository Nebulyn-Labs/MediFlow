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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('Pending Requests Approval')),
      body: StreamBuilder<List<MedRequest>>(
        stream: ref.read(firebaseServiceProvider).streamRequests(null),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final pending = snapshot.data
                  ?.where((r) => r.status == RequestStatus.pending)
                  .toList() ??
              [];

          if (pending.isEmpty) {
            return const Center(
                child: Text('No pending requests.',
                    style: TextStyle(color: MediColors.textMuted)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final req = pending[index];
              final isAiLoading = _aiLoading[req.id] ?? false;
              final suggestion = _aiSuggestions[req.id];

              final isRedistribution = req.type == RequestType.surplus;

              return Card(
                margin: const EdgeInsets.only(bottom: 20),
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
                                          ? MediColors.success
                                              .withValues(alpha: 0.1)
                                          : MediColors.error
                                              .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
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
                                ? MediColors.success.withValues(alpha: 0.1)
                                : MediColors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: suggestion.contains('✅')
                                    ? MediColors.success.withValues(alpha: 0.3)
                                    : MediColors.warning
                                        .withValues(alpha: 0.3)),
                          ),
                          child: Text(suggestion,
                              style: TextStyle(
                                  color: suggestion.contains('✅')
                                      ? MediColors.success
                                      : MediColors.warning,
                                  fontWeight: FontWeight.w500)),
                        ),

                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                isAiLoading ? null : () => _analyzeRequest(req),
                            icon: isAiLoading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.auto_awesome, size: 16),
                            label: const Text('Analyze with AI'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: MediColors.primaryLight),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _isActionInProgress
                                ? null
                                : () => _updateStatus(
                                    req.id, RequestStatus.rejected),
                            style: TextButton.styleFrom(
                                foregroundColor: MediColors.error),
                            child: const Text('Decline'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: _isActionInProgress
                                ? null
                                : () => _updateStatus(
                                    req.id, RequestStatus.approved),
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
          );
        },
      ),
    );
  }
}
