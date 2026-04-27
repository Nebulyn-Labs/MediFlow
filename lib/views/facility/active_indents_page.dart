import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/firebase_service.dart';
import '../../models/request.dart';
import '../../main.dart';

class ActiveIndentsPage extends ConsumerStatefulWidget {
  final String facilityId;
  const ActiveIndentsPage({super.key, required this.facilityId});

  @override
  ConsumerState<ActiveIndentsPage> createState() => _ActiveIndentsPageState();
}

class _ActiveIndentsPageState extends ConsumerState<ActiveIndentsPage> {
  bool _isSubmitting = false;
  final Set<String> _selectedIds = {};

  Future<void> _requestFromCMS(List<MedRequest> drafts) async {
    final toSubmit = drafts.where((d) => _selectedIds.contains(d.id)).toList();
    if (toSubmit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one indent to send.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm CMS Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send ${toSubmit.length} indent(s) to the CMS for processing?'),
            const SizedBox(height: 12),
            ...toSubmit.take(5).map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• ${r.medicineName} — ${r.quantity} units',
                  style: const TextStyle(fontWeight: FontWeight.w500, color: MediColors.textPrimary)),
            )),
            if (toSubmit.length > 5)
              Text('...and ${toSubmit.length - 5} more',
                  style: const TextStyle(fontStyle: FontStyle.italic, color: MediColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send to CMS')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final firebase = ref.read(firebaseServiceProvider);
      for (var req in toSubmit) {
        await firebase.updateRequestStatus(req.id, RequestStatus.pending);
      }
      if (mounted) {
        setState(() => _selectedIds.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indents sent to CMS ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteDraft(String id) async {
    try {
      await ref.read(firebaseServiceProvider).deleteRequest(id);
      _selectedIds.remove(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebase = ref.watch(firebaseServiceProvider);

    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: Text('Active Indents',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24, color: MediColors.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MediColors.border, height: 1),
        ),
      ),
      body: StreamBuilder<List<MedRequest>>(
        stream: firebase.streamRequests(widget.facilityId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allRequests = snapshot.data ?? [];
          final drafts = allRequests.where((r) => r.status == RequestStatus.draft).toList();
          final pending = allRequests.where((r) => r.status == RequestStatus.pending).toList();
          final history = allRequests.where((r) =>
              r.status == RequestStatus.approved ||
              r.status == RequestStatus.fulfilled ||
              r.status == RequestStatus.rejected).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Draft Indents Card ──
                _buildSectionCard(
                  title: 'Draft Indents',
                  subtitle: '${drafts.length} indent(s) waiting for your review',
                  icon: Icons.edit_note_rounded,
                  iconColor: MediColors.warning,
                  child: drafts.isEmpty
                      ? _buildEmptyState('No draft indents', 'Create indents from the "Indents" tab to see them here.')
                      : Column(
                          children: [
                            // Select All
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: drafts.isNotEmpty && drafts.every((d) => _selectedIds.contains(d.id)),
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedIds.addAll(drafts.map((d) => d.id));
                                        } else {
                                          _selectedIds.removeAll(drafts.map((d) => d.id));
                                        }
                                      });
                                    },
                                    activeColor: MediColors.primary,
                                    side: const BorderSide(color: MediColors.borderLight),
                                  ),
                                  const Text('Select All', style: TextStyle(color: MediColors.textSecondary, fontSize: 13)),
                                ],
                              ),
                            ),
                            ...drafts.map((req) => _buildDraftTile(req)),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: MediColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: FilledButton.icon(
                                    onPressed: _isSubmitting ? null : () => _requestFromCMS(drafts),
                                    icon: _isSubmitting
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Icon(Icons.send_rounded),
                                    label: Text(
                                      _isSubmitting ? 'Sending...' : 'Request from CMS (${_selectedIds.length})',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),

                // ── Pending (Sent to CMS) ──
                _buildSectionCard(
                  title: 'Pending at CMS',
                  subtitle: '${pending.length} indent(s) awaiting CMS approval',
                  icon: Icons.hourglass_top_rounded,
                  iconColor: MediColors.info,
                  child: pending.isEmpty
                      ? _buildEmptyState('No pending indents', 'Indents you send to CMS will appear here.')
                      : Column(children: pending.map((req) => _buildStatusTile(req, MediColors.info, 'Pending')).toList()),
                ),
                const SizedBox(height: 24),

                // ── History ──
                _buildSectionCard(
                  title: 'History',
                  subtitle: '${history.length} resolved indent(s)',
                  icon: Icons.history_rounded,
                  iconColor: MediColors.textMuted,
                  child: history.isEmpty
                      ? _buildEmptyState('No history yet', 'Approved, fulfilled, or rejected indents will show here.')
                      : Column(children: history.map((req) {
                          Color color;
                          String label;
                          switch (req.status) {
                            case RequestStatus.approved:
                              color = MediColors.success; label = 'Approved'; break;
                            case RequestStatus.fulfilled:
                              color = MediColors.teal; label = 'Fulfilled'; break;
                            case RequestStatus.rejected:
                              color = MediColors.error; label = 'Rejected'; break;
                            default:
                              color = MediColors.textMuted; label = req.status.name;
                          }
                          return _buildStatusTile(req, color, label);
                        }).toList()),
                ),
                const SizedBox(height: 64),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Reusable Widgets ──

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MediColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: MediColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: MediColors.textSecondary, fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: MediColors.border, height: 1),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildDraftTile(MedRequest req) {
    final isSelected = _selectedIds.contains(req.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? MediColors.primary.withOpacity(0.08) : MediColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? MediColors.primary.withOpacity(0.4) : MediColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Checkbox(
          value: isSelected,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedIds.add(req.id);
              } else {
                _selectedIds.remove(req.id);
              }
            });
          },
          activeColor: MediColors.primary,
          side: const BorderSide(color: MediColors.borderLight),
        ),
        title: Text(req.medicineName, style: const TextStyle(fontWeight: FontWeight.bold, color: MediColors.textPrimary)),
        subtitle: Text(
          '${req.quantity} units  •  ${req.notes ?? ''}',
          style: const TextStyle(color: MediColors.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: MediColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Draft', style: TextStyle(color: MediColors.warning, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: MediColors.error, size: 20),
              tooltip: 'Delete draft',
              onPressed: () => _deleteDraft(req.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTile(MedRequest req, Color statusColor, String statusLabel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: MediColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MediColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(req.medicineName, style: const TextStyle(fontWeight: FontWeight.bold, color: MediColors.textPrimary)),
        subtitle: Text(
          '${req.quantity} units  •  ${req.notes ?? ''}',
          style: const TextStyle(color: MediColors.textSecondary, fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 40, color: MediColors.textMuted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: MediColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: MediColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
