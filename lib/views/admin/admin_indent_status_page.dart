import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/firebase_service.dart';
import '../../models/request.dart';
import '../../models/facility.dart';
import '../../main.dart';

class AdminIndentStatusPage extends ConsumerStatefulWidget {
  const AdminIndentStatusPage({super.key});

  @override
  ConsumerState<AdminIndentStatusPage> createState() => _AdminIndentStatusPageState();
}

class _AdminIndentStatusPageState extends ConsumerState<AdminIndentStatusPage> {
  List<Facility> _facilities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFacilities();
  }

  Future<void> _loadFacilities() async {
    final facs = await ref.read(firebaseServiceProvider).getFacilities();
    if (mounted) setState(() { _facilities = facs; _isLoading = false; });
  }

  String _facilityName(String facilityId) {
    return _facilities
        .where((f) => f.id == facilityId)
        .map((f) => f.name)
        .firstOrNull ?? 'Unknown';
  }

  Future<void> _changeStatus(String requestId, RequestStatus newStatus) async {
    try {
      await ref.read(firebaseServiceProvider).updateRequestStatus(requestId, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status changed to ${newStatus.name} ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: MediColors.bg, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: Text('Indent Status', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24, color: MediColors.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MediColors.border, height: 1),
        ),
      ),
      body: StreamBuilder<List<MedRequest>>(
        stream: ref.read(firebaseServiceProvider).streamRequests(null),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final all = snapshot.data ?? [];
          final approved = all.where((r) => r.status == RequestStatus.approved).toList();
          final rejected = all.where((r) => r.status == RequestStatus.rejected).toList();
          final fulfilled = all.where((r) => r.status == RequestStatus.fulfilled).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats
                Row(
                  children: [
                    _buildStatChip(Icons.check_circle_rounded, '${approved.length}', 'Approved', MediColors.success),
                    const SizedBox(width: 16),
                    _buildStatChip(Icons.cancel_rounded, '${rejected.length}', 'Rejected', MediColors.error),
                    const SizedBox(width: 16),
                    _buildStatChip(Icons.verified_rounded, '${fulfilled.length}', 'Fulfilled', MediColors.teal),
                  ],
                ),
                const SizedBox(height: 32),

                // Approved Section
                _buildSection(
                  title: 'Approved Indents',
                  icon: Icons.check_circle_rounded,
                  iconColor: MediColors.success,
                  items: approved,
                  emptyMessage: 'No approved indents yet.',
                  actions: (req) => [
                    _actionButton('Mark Fulfilled', Icons.verified_rounded, MediColors.teal, () => _changeStatus(req.id, RequestStatus.fulfilled)),
                    const SizedBox(width: 8),
                    _actionButton('Revoke → Reject', Icons.undo_rounded, MediColors.error, () => _changeStatus(req.id, RequestStatus.rejected)),
                    const SizedBox(width: 8),
                    _actionButton('Back to Pending', Icons.replay_rounded, MediColors.warning, () => _changeStatus(req.id, RequestStatus.pending)),
                  ],
                ),
                const SizedBox(height: 24),

                // Rejected Section
                _buildSection(
                  title: 'Rejected Indents',
                  icon: Icons.cancel_rounded,
                  iconColor: MediColors.error,
                  items: rejected,
                  emptyMessage: 'No rejected indents.',
                  actions: (req) => [
                    _actionButton('Approve', Icons.check_circle_rounded, MediColors.success, () => _changeStatus(req.id, RequestStatus.approved)),
                    const SizedBox(width: 8),
                    _actionButton('Back to Pending', Icons.replay_rounded, MediColors.warning, () => _changeStatus(req.id, RequestStatus.pending)),
                  ],
                ),
                const SizedBox(height: 24),

                // Fulfilled Section
                _buildSection(
                  title: 'Fulfilled Indents',
                  icon: Icons.verified_rounded,
                  iconColor: MediColors.teal,
                  items: fulfilled,
                  emptyMessage: 'No fulfilled indents.',
                  actions: (req) => [
                    _actionButton('Reopen → Approved', Icons.undo_rounded, MediColors.warning, () => _changeStatus(req.id, RequestStatus.approved)),
                  ],
                ),
                const SizedBox(height: 64),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Widgets ──

  Widget _buildStatChip(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<MedRequest> items,
    required String emptyMessage,
    required List<Widget> Function(MedRequest) actions,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MediColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: MediColors.textPrimary)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('${items.length}', style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: MediColors.border, height: 1),
          const SizedBox(height: 12),

          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(emptyMessage, style: const TextStyle(color: MediColors.textMuted, fontSize: 13)),
              ),
            )
          else
            ...items.map((req) {
              final facName = _facilityName(req.facilityId);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MediColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MediColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(req.medicineName, style: const TextStyle(fontWeight: FontWeight.bold, color: MediColors.textPrimary, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text('$facName  •  ${req.quantity} units  •  ${req.notes ?? ''}',
                                  style: const TextStyle(color: MediColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                        ...actions(req),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return Tooltip(
      message: label,
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
