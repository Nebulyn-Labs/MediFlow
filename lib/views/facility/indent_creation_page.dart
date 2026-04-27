import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../models/request.dart';
import '../../models/inventory_item.dart';
import '../../models/facility.dart';
import '../../main.dart'; // For MediColors

class IndentCreationPage extends ConsumerStatefulWidget {
  final String facilityId;
  const IndentCreationPage({super.key, required this.facilityId});

  @override
  ConsumerState<IndentCreationPage> createState() => _IndentCreationPageState();
}

class _IndentCreationPageState extends ConsumerState<IndentCreationPage> {
  List<InventoryItem> _inventory = [];
  Facility? _facility;
  bool _isLoading = true;
  bool _isForecasting = false;
  bool _isSubmitting = false;

  int _selectedPeriod = 30; // days
  Map<String, int> _aiSuggestions = {};
  Map<String, int> _quantities = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final firebase = ref.read(firebaseServiceProvider);
    try {
      final fac = await firebase.getFacility(widget.facilityId);
      final inv = await firebase.getInventoryOnce(widget.facilityId);
      if (mounted) {
        setState(() {
          _facility = fac;
          _inventory = inv;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  Future<void> _getAiForecast() async {
    setState(() => _isForecasting = true);
    try {
      final firebase = ref.read(firebaseServiceProvider);
      final ai = ref.read(aiServiceProvider);
      final logs = await firebase.getRecentLogs(widget.facilityId, days: 120);
      
      Map<String, int> suggestions = {};
      for (var item in _inventory) {
        final result = await ai.forecastDemand(item.medicineName, logs, _selectedPeriod);
        suggestions[item.medicineName] = result['prediction'] ?? 0;
      }
      
      if (mounted) {
        setState(() {
          _aiSuggestions = suggestions;
          _isForecasting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isForecasting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI Error: $e')));
      }
    }
  }

  Future<void> _submitIndent() async {
    final itemsToSubmit = _quantities.entries.where((e) => e.value > 0).toList();
    if (itemsToSubmit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter at least one quantity greater than 0.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final firebase = ref.read(firebaseServiceProvider);
      for (var entry in itemsToSubmit) {
        final req = MedRequest(
          id: '',
          facilityId: widget.facilityId,
          medicineName: entry.key,
          type: RequestType.regularIndent,
          quantity: entry.value,
          requestDate: DateTime.now(),
          status: RequestStatus.draft,
          notes: 'AI Guided Indent - $_selectedPeriod days',
        );
        await firebase.addRequest(req);
      }
      if (mounted) {
        setState(() {
          _quantities.clear();
          _aiSuggestions.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to Active Indents ✓')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error submitting: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
        title: Row(
          children: [
            Text('Create Indent', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 24, color: MediColors.textPrimary)),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: MediColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _facility?.name ?? 'Unknown Facility',
                style: const TextStyle(color: MediColors.primaryLight, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MediColors.border, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step 1
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: MediColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MediColors.border),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  Text('Step 1: Select Period', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: MediColors.textPrimary)),
                  const SizedBox(width: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: MediColors.surfaceLight,
                      border: Border.all(color: MediColors.borderLight),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedPeriod,
                        dropdownColor: MediColors.surfaceLight,
                        style: const TextStyle(color: MediColors.textPrimary),
                        iconEnabledColor: MediColors.textSecondary,
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30 days')),
                          DropdownMenuItem(value: 60, child: Text('60 days')),
                          DropdownMenuItem(value: 90, child: Text('90 days')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedPeriod = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Text('${_inventory.length} medicines in inventory', style: const TextStyle(color: MediColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Step 2
            Container(
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Step 2: Medicine Quantities', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: MediColors.textPrimary)),
                      Container(
                        decoration: BoxDecoration(
                          gradient: MediColors.cyanGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: FilledButton.icon(
                          onPressed: _isForecasting ? null : _getAiForecast,
                          icon: _isForecasting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Get AI Forecast', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Table
                  if (_inventory.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No medicines found in active inventory.', style: TextStyle(color: MediColors.textSecondary))),
                    )
                  else
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: MediColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(MediColors.surfaceLight),
                          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: MediColors.textSecondary),
                          dataRowMinHeight: 60,
                          dataRowMaxHeight: 60,
                          dividerThickness: 1,
                          columns: const [
                            DataColumn(label: Text('Medicine')),
                            DataColumn(label: Text('Batch')),
                            DataColumn(label: Text('Available')),
                            DataColumn(label: Text('AI Suggestion')),
                            DataColumn(label: Text('Your Quantity')),
                            DataColumn(label: Text('Unit')),
                          ],
                          rows: _inventory.map((item) {
                            final suggestion = _aiSuggestions[item.medicineName];
                            
                            // Determine unit type (tablets vs others)
                            String unit = 'units';
                            final nameLower = item.medicineName.toLowerCase();
                            if (nameLower.contains('tablet') || nameLower.contains('paracetamol') || nameLower.contains('acid') || nameLower.contains('metformin')) unit = 'tablets';
                            else if (nameLower.contains('capsule') || nameLower.contains('amoxicillin')) unit = 'capsules';
                            else if (nameLower.contains('sachet') || nameLower.contains('ors')) unit = 'sachets';
                            else if (nameLower.contains('syrup')) unit = 'bottles';

                            return DataRow(
                              cells: [
                                DataCell(Text(item.medicineName, style: const TextStyle(fontWeight: FontWeight.bold, color: MediColors.textPrimary))),
                                DataCell(Text(item.batchId, style: const TextStyle(color: MediColors.textSecondary))),
                                DataCell(Text(item.remainingQuantity.toString(), style: const TextStyle(color: MediColors.textPrimary))),
                                DataCell(
                                  Text(
                                    suggestion != null ? suggestion.toString() : '—',
                                    style: TextStyle(
                                      color: suggestion != null ? MediColors.success : MediColors.textMuted,
                                      fontWeight: suggestion != null ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: TextField(
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(color: MediColors.textPrimary),
                                      decoration: InputDecoration(
                                        hintText: '0',
                                        hintStyle: const TextStyle(color: MediColors.textMuted),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        filled: true,
                                        fillColor: MediColors.bg,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: MediColors.borderLight),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: MediColors.borderLight),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: MediColors.primary),
                                        ),
                                      ),
                                      onChanged: (val) {
                                        _quantities[item.medicineName] = int.tryParse(val) ?? 0;
                                      },
                                      controller: TextEditingController(
                                        text: _quantities[item.medicineName]?.toString() ?? '',
                                      )..selection = TextSelection.collapsed(offset: (_quantities[item.medicineName]?.toString() ?? '').length),
                                    ),
                                  ),
                                ),
                                DataCell(Text(unit, style: const TextStyle(color: MediColors.textSecondary))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // Submission Area
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: MediColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submitIndent,
                    icon: _isSubmitting 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                    label: Text(_isSubmitting ? 'Submitting...' : 'Submit Indent', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 64), // Scroll padding
          ],
        ),
      ),
    );
  }
}

