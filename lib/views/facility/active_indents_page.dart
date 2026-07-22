import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../models/request.dart';
import '../../models/inventory_item.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class ActiveIndentsPage extends ConsumerStatefulWidget {
  final String facilityId;
  const ActiveIndentsPage({super.key, required this.facilityId});

  @override
  ConsumerState<ActiveIndentsPage> createState() => _ActiveIndentsPageState();
}

class _ActiveIndentsPageState extends ConsumerState<ActiveIndentsPage> {
  // ---------- Draft handling ----------
  final Map<String, TextEditingController> _draftControllers = {};
  bool _isDraftActionInProgress = false;

  // ---------- Empty state navigation ----------
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _analysisSectionKey = GlobalKey();

  // ---------- Inventory & AI analysis ----------
  List<InventoryItem> _inventory = [];
  final Map<String, int?> _forecasts = {};
  final Map<String, String?> _reasoning = {};
  final Map<String, bool> _forecastLoading = {};
  final Map<String, TextEditingController> _analysisControllers = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  int _selectedPeriod = 30;

  @override
  void initState() {
    super.initState();
    _fetchInventory();
  }

  @override
  void dispose() {
    for (var c in _draftControllers.values) {
      c.dispose();
    }
    for (var c in _analysisControllers.values) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- Inventory ----------
  Future<void> _fetchInventory() async {
    setState(() => _isLoading = true);
    try {
      final inv = await ref
          .read(firebaseServiceProvider)
          .getInventoryOnce(widget.facilityId);
      setState(() {
        _inventory = inv;
        for (var i in _inventory) {
          _analysisControllers[i.id] = TextEditingController(text: '0');
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching inventory: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- AI Forecast ----------
  Future<void> _getAIForecast() async {
    final aiService = ref.read(aiServiceProvider);
    final firebaseService = ref.read(firebaseServiceProvider);
    final logs =
        await firebaseService.getRecentLogs(widget.facilityId, days: 90);
    for (var item in _inventory) {
      setState(() => _forecastLoading[item.id] = true);
      try {
        final dynamic result = await aiService.forecastDemand(
            item.medicineName, logs, _selectedPeriod,
            facilityId: widget.facilityId);
        setState(() {
          dynamic predRaw;
          dynamic reasonRaw;
          if (result != null && result is Map) {
            predRaw = result['prediction'];
            reasonRaw = result['reasoning'];
          }
          int predicted = 0;
          if (predRaw is num) {
            predicted = predRaw.toInt();
          } else if (predRaw is String) {
            predicted = double.tryParse(predRaw)?.toInt() ?? 0;
          }
          _forecasts[item.id] = predicted;
          _reasoning[item.id] =
              reasonRaw?.toString() ?? "Calculated based on demand.";

          _analysisControllers[item.id]?.text =
              _suggestedQuantity(item, predicted).toString();
        });
      } catch (e) {
        debugPrint('Forecast error for ${item.medicineName}: $e');
      } finally {
        setState(() => _forecastLoading[item.id] = false);
      }
    }
  }

  int _suggestedQuantity(InventoryItem item, int? forecast) {
    if (forecast == null) return 0;
    if (forecast <= 0) return 0;

    final available = item.remainingQuantity;
    final isExpired = item.expiryDate.difference(DateTime.now()).inDays < 0;
    final expiringSoon =
        item.expiryDate.difference(DateTime.now()).inDays <= 30;

    if (isExpired) {
      return (forecast * 1.2).round();
    }
    if (forecast > available) {
      return ((forecast - available) * 1.2).round();
    }
    if ((available - forecast) > (forecast * 1.5) ||
        (available > forecast && expiringSoon)) {
      final surplusQty = available - (forecast * 1.2).round();
      return surplusQty < 0 ? 0 : surplusQty;
    }
    return 0;
  }

  RequestType _requestTypeFor(InventoryItem item, int? forecast) {
    if (forecast == null) return RequestType.regularIndent;
    if (forecast <= 0) return RequestType.regularIndent;

    final available = item.remainingQuantity;
    final isExpired = item.expiryDate.difference(DateTime.now()).inDays < 0;
    final expiringSoon =
        item.expiryDate.difference(DateTime.now()).inDays <= 30;
    final hasSurplus = !isExpired &&
        ((available - forecast) > (forecast * 1.5) ||
            (available > forecast && expiringSoon));

    if (hasSurplus) return RequestType.surplus;
    return RequestType.regularIndent;
  }

  Future<void> _saveAnalysisAsDrafts() async {
    final itemsToSubmit = _inventory.where((item) {
      final qty = int.tryParse(_analysisControllers[item.id]?.text ?? '0') ?? 0;
      return qty > 0;
    }).toList();

    if (itemsToSubmit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Enter a request quantity for at least one medicine.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      for (final item in itemsToSubmit) {
        final qty =
            int.tryParse(_analysisControllers[item.id]?.text ?? '0') ?? 0;
        final forecast = _forecasts[item.id];
        final type = _requestTypeFor(item, forecast);
        final action = type == RequestType.surplus
            ? 'Redistribution offer'
            : 'Restock request';

        final req = MedRequest(
          id: '',
          facilityId: widget.facilityId,
          medicineName: item.medicineName,
          type: type,
          quantity: qty,
          requestDate: DateTime.now(),
          status: RequestStatus.draft,
          notes:
              '$action. AI predicted usage: ${forecast ?? "N/A"} for $_selectedPeriod days.',
        );
        await ref.read(firebaseServiceProvider).addRequest(req);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Requests saved as drafts.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------- Draft actions ----------
  Future<void> _updateQuantity(String requestId, int quantity) async {
    setState(() => _isDraftActionInProgress = true);
    try {
      await ref
          .read(firebaseServiceProvider)
          .updateRequestQuantity(requestId, quantity);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDraftActionInProgress = false);
    }
  }

  Future<void> _deleteDraft(String requestId) async {
    setState(() => _isDraftActionInProgress = true);
    try {
      await ref.read(firebaseServiceProvider).deleteRequest(requestId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDraftActionInProgress = false);
    }
  }

  Future<void> _finalSubmit(String requestId) async {
    setState(() => _isDraftActionInProgress = true);
    try {
      await ref
          .read(firebaseServiceProvider)
          .updateRequestStatus(requestId, RequestStatus.pending);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request sent to CMS! âœ“')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Submission failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDraftActionInProgress = false);
    }
  }

  // ---------- Empty state navigation ----------
  void _goToCreateIndent() {
    final ctx = _analysisSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      // The analysis section may not be laid out yet (e.g. right after the
      // loading spinner disappears). Retry on the next frame instead of
      // silently doing nothing, so the CTA reliably works on first tap.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final retryCtx = _analysisSectionKey.currentContext;
        if (retryCtx != null && mounted) {
          Scrollable.ensureVisible(
            retryCtx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  // ---------- UI Helpers ----------
  Widget _sectionHeader(String title) => Text(title,
      style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: MediColors.textPrimary));

  // ----- AI Table -----
  Widget _analysisHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
          color: MediColors.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: const Row(
        children: [
          SizedBox(
              width: 40,
              child: Icon(Icons.check_box_outline_blank,
                  color: MediColors.textMuted, size: 20)),
          Expanded(
              flex: 3,
              child: Text('Medicine',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('Available',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('AI Predicted Usage',
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
              flex: 2,
              child: Text('Request Qty',
                  style: TextStyle(
                      color: MediColors.textSecondary,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _analysisRow(InventoryItem item) {
    final isLoading = _forecastLoading[item.id] ?? false;
    final forecast = _forecasts[item.id];
    final reasoning = _reasoning[item.id];
    int available = item.remainingQuantity;
    bool isExpired = item.expiryDate.difference(DateTime.now()).inDays < 0;
    bool expiringSoon = item.expiryDate.difference(DateTime.now()).inDays <= 30;

    String status = "â€”";
    Color statusColor = MediColors.textMuted;
    Color statusBg = Colors.transparent;
    IconData statusIcon = Icons.help_outline;

    if (forecast != null) {
      if (isExpired) {
        status = "EXPIRED";
        statusColor = MediColors.error;
        statusBg = MediColors.errorOverlay;
        statusIcon = Icons.warning_rounded;
      } else if (forecast > available) {
        status = "LOW STOCK";
        statusColor = MediColors.error;
        statusBg = MediColors.errorOverlay;
        statusIcon = Icons.trending_down_rounded;
      } else if (forecast > 0 &&
          ((available - forecast) > (forecast * 1.5) ||
              (available > forecast && expiringSoon))) {
        status = "SURPLUS";
        statusColor = MediColors.success;
        statusBg = MediColors.successOverlay;
        statusIcon = Icons.arrow_upward_rounded;
      } else {
        status = "OK";
        statusColor = MediColors.primary;
        statusBg = MediColors.primaryOverlay;
        statusIcon = Icons.check;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Checkbox(
                  value: true,
                  onChanged: (v) {},
                  activeColor: MediColors.surfaceLight,
                  checkColor: MediColors.textPrimary,
                  side: const BorderSide(color: MediColors.textMuted))),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.medicineName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: MediColors.textPrimary)),
                Text(item.batchId,
                    style: const TextStyle(
                        color: MediColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
              flex: 2,
              child: Text(available.toString(),
                  style: const TextStyle(
                      color: MediColors.textPrimary,
                      fontWeight: FontWeight.bold))),
          Expanded(
            flex: 2,
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Tooltip(
                    message: reasoning ?? "AI reasoning will appear here.",
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          forecast != null ? forecast.toString() : 'â€”',
                          style: TextStyle(
                              color: forecast != null
                                  ? MediColors.primaryLight
                                  : MediColors.textMuted,
                              fontWeight: forecast != null
                                  ? FontWeight.bold
                                  : FontWeight.normal),
                        ),
                        if (forecast != null) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.info_outline,
                              color: MediColors.primaryLight, size: 14)
                        ],
                      ],
                    ),
                  ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: statusBg, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 14),
                    const SizedBox(width: 6),
                    Text(status,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                  color: MediColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MediColors.border)),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _analysisControllers[item.id],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, color: MediColors.textPrimary),
                      decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero),
                    ),
                  ),
                  Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Text(item.unit,
                          style: const TextStyle(
                              color: MediColors.textMuted, fontSize: 11))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Drafts List -----
  Widget _draftsList() {
    return StreamBuilder<List<MedRequest>>(
      stream:
          ref.read(firebaseServiceProvider).streamRequests(widget.facilityId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Error: ${snapshot.error}',
                  style: const TextStyle(color: MediColors.error)));
        }
        final drafts = snapshot.data
                ?.where((r) => r.status == RequestStatus.draft)
                .toList() ??
            [];
        if (drafts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_outlined,
                      size: 72,
                      color: MediColors.textMuted.withValues(alpha: 0.5)),
                  const SizedBox(height: 20),
                  const Text('No Active Indents',
                      style: TextStyle(
                          color: MediColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'You have no active supply requests right now. '
                      'Use the AI analysis above to create a new indent.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: MediColors.textMuted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _goToCreateIndent,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Create New Indent'),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Pending Requests'),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: drafts.length,
              itemBuilder: (context, idx) {
                final draft = drafts[idx];
                if (!_draftControllers.containsKey(draft.id)) {
                  _draftControllers[draft.id] =
                      TextEditingController(text: draft.quantity.toString());
                }
                final medicineInfo = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(draft.medicineName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: MediColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(
                        'Created: ${draft.requestDate.day}/${draft.requestDate.month}/${draft.requestDate.year}',
                        style: const TextStyle(
                            fontSize: 12, color: MediColors.textMuted)),
                    if (draft.notes != null) ...[
                      const SizedBox(height: 8),
                      Text(draft.notes!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: MediColors.info,
                              fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: draft.type == RequestType.surplus
                            ? MediColors.successOverlay
                            : MediColors.errorOverlay,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            draft.type == RequestType.surplus
                                ? Icons.arrow_upward_rounded
                                : Icons.trending_down_rounded,
                            color: draft.type == RequestType.surplus
                                ? MediColors.success
                                : MediColors.error,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            draft.type == RequestType.surplus
                                ? 'Offering Redistribution'
                                : 'Requesting Restock',
                            style: TextStyle(
                                color: draft.type == RequestType.surplus
                                    ? MediColors.success
                                    : MediColors.error,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final quantityEditor = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text('Request Qty: ',
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: MediColors.textSecondary)),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      height: 40,
                      child: TextField(
                        controller: _draftControllers[draft.id],
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8))),
                        onSubmitted: (val) {
                          final qty = int.tryParse(val) ?? draft.quantity;
                          _updateQuantity(draft.id, qty);
                        },
                      ),
                    ),
                  ],
                );

                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: MediColors.error),
                        onPressed: _isDraftActionInProgress
                            ? null
                            : () => _deleteDraft(draft.id),
                        tooltip: 'Remove Draft'),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isDraftActionInProgress
                          ? null
                          : () => _finalSubmit(draft.id),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Submit to CMS'),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12)),
                    ),
                  ],
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 560;
                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              medicineInfo,
                              const SizedBox(height: 16),
                              quantityEditor,
                              const SizedBox(height: 16),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: actions),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(flex: 3, child: medicineInfo),
                            Expanded(flex: 2, child: quantityEditor),
                            actions,
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(title: const Text('Requests')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ----- AI Analysis -----
                  _sectionHeader('AI Stock Analysis & Requests'),
                  const SizedBox(height: 12),
                  // Period selector & button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionHeader('Select Period'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                            border: Border.all(color: MediColors.border),
                            borderRadius: BorderRadius.circular(12)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedPeriod,
                            dropdownColor: MediColors.surface,
                            items: [30, 60, 90]
                                .map((int v) => DropdownMenuItem<int>(
                                    value: v,
                                    child: Text('$v days',
                                        style: const TextStyle(
                                            color: MediColors.textPrimary))))
                                .toList(),
                            onChanged: (val) => setState(
                                () => _selectedPeriod = val ?? _selectedPeriod),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                          onPressed: _getAIForecast,
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Get AI Forecast')),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _isSubmitting ? null : _saveAnalysisAsDrafts,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_alt_rounded, size: 18),
                        label: const Text('Save Draft Requests'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    key: _analysisSectionKey,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const tableMinWidth = 700.0;
                        final tableContent = SizedBox(
                          width: constraints.maxWidth < tableMinWidth
                              ? tableMinWidth
                              : constraints.maxWidth,
                          child: Column(
                            children: [
                              _analysisHeader(),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _inventory.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, idx) =>
                                    _analysisRow(_inventory[idx]),
                              ),
                            ],
                          ),
                        );
                        if (constraints.maxWidth < tableMinWidth) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: tableContent,
                          );
                        }
                        return tableContent;
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                  // ----- Draft Requests -----
                  _draftsList(),
                ],
              ),
            ),
    );
  }
}
