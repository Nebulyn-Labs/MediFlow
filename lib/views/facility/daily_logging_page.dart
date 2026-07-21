import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/daily_usage_log.dart';
import '../../services/firebase_service.dart';
import '../../services/csv_export_service.dart';
import '../../services/ai_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class DailyLoggingPage extends ConsumerStatefulWidget {
  final String facilityId;
  const DailyLoggingPage({super.key, required this.facilityId});

  @override
  ConsumerState<DailyLoggingPage> createState() => _DailyLoggingPageState();
}

class _DailyLoggingPageState extends ConsumerState<DailyLoggingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  final _formKey = GlobalKey<FormState>();
  String? _medName;
  int _quantity = 0;
  int _patients = 0;
  bool _isSubmitting = false;
  List<String> _availableMedicines = [];
  bool _isLoadingInventory = true;
  List<Map<String, dynamic>> _csvItems = [];
  String? _csvStatus;
  bool _isSubmittingCsv = false;
  bool _isScanning = false;
  final List<Map<String, dynamic>> _scannedItems = [];
  bool _isSubmittingQr = false;
  bool _isExportingCsv = false;
  bool _isParsingImage = false;
  String? _imageParseResult;
  String? _imageParseError;

  // --- History tab state ---
  List<DailyUsageLog> _historyLogs = [];
  DocumentSnapshot? _lastHistoryDoc;
  bool _historyHasMore = true;
  bool _isLoadingHistory = true;
  bool _isLoadingMoreHistory = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchInventory();
    _fetchHistoryFirstPage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchInventory() async {
    try {
      final items = await ref
          .read(firebaseServiceProvider)
          .getInventoryOnce(widget.facilityId);
      if (mounted) {
        setState(() {
          _availableMedicines = items.map((i) => i.medicineName).toList();
          if (_availableMedicines.isNotEmpty) {
            _medName = _availableMedicines.first;
          }
          _isLoadingInventory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingInventory = false);
    }
  }

  // --- History fetching ---

  Future<void> _fetchHistoryFirstPage() async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });
    try {
      final result = await ref
          .read(firebaseServiceProvider)
          .getPaginatedLogs(widget.facilityId, pageSize: 15);
      if (mounted) {
        setState(() {
          _historyLogs = result.logs;
          _lastHistoryDoc = result.lastDocument;
          _historyHasMore = result.hasMore;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _historyError = e.toString();
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _fetchMoreHistory() async {
    if (!_historyHasMore || _isLoadingMoreHistory) return;
    setState(() => _isLoadingMoreHistory = true);
    try {
      final result = await ref.read(firebaseServiceProvider).getPaginatedLogs(
            widget.facilityId,
            pageSize: 15,
            startAfter: _lastHistoryDoc,
          );
      if (mounted) {
        setState(() {
          _historyLogs = [..._historyLogs, ...result.logs];
          _lastHistoryDoc = result.lastDocument ?? _lastHistoryDoc;
          _historyHasMore = result.hasMore;
          _isLoadingMoreHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMoreHistory = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load more: $e')));
      }
    }
  }

  Future<void> _submitLog() async {
    if (!_formKey.currentState!.validate() || _medName == null) return;
    _formKey.currentState!.save();
    setState(() => _isSubmitting = true);
    try {
      await ref.read(firebaseServiceProvider).logUsage(
          facilityId: widget.facilityId,
          date: _selectedDate,
          medicineName: _medName!,
          quantity: _quantity,
          patients: _patients);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Log saved ✓')));
        _formKey.currentState!.reset();
        // Keep the History tab fresh with the newly saved log.
        _fetchHistoryFirstPage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _exportUsageLogsCsv() async {
    setState(() => _isExportingCsv = true);
    try {
      final firebase = ref.read(firebaseServiceProvider);
      final logs = await firebase.getRecentLogs(widget.facilityId, days: 120);
      if (logs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No usage logs to export yet')));
        }
        return;
      }
      final fac = await firebase.getFacility(widget.facilityId);
      await CsvExportService.exportUsageLogs(logs, facilityName: fac?.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Usage logs CSV exported ✓')));
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

  Future<void> _pickCSV() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      final csvString = utf8.decode(bytes);
      final rows = const CsvDecoder().convert(csvString);
      if (rows.isEmpty) return;
      int startRow = 0;
      final firstCell = rows[0][0].toString().toLowerCase().trim();
      if (firstCell.contains('medicine') ||
          firstCell.contains('name') ||
          firstCell.contains('drug')) {
        startRow = 1;
      }
      final parsed = <Map<String, dynamic>>[];
      for (int i = startRow; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;
        final med = row[0].toString().trim();
        final qty =
            row.length > 1 ? int.tryParse(row[1].toString().trim()) ?? 0 : 0;
        final pat =
            row.length > 2 ? int.tryParse(row[2].toString().trim()) ?? 0 : 0;
        if (med.isNotEmpty && qty > 0) {
          parsed.add({'medicine': med, 'quantity': qty, 'patients': pat});
        }
      }
      setState(() {
        _csvItems = parsed;
        _csvStatus = 'Parsed ${parsed.length} entries from ${file.name}';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('CSV Error: $e')));
      }
    }
  }

  Future<void> _submitCSVLogs() async {
    if (_csvItems.isEmpty) return;
    setState(() => _isSubmittingCsv = true);
    try {
      for (var item in _csvItems) {
        await ref.read(firebaseServiceProvider).logUsage(
            facilityId: widget.facilityId,
            date: _selectedDate,
            medicineName: item['medicine'],
            quantity: item['quantity'],
            patients: item['patients']);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_csvItems.length} logs saved ✓')));
        setState(() {
          _csvItems.clear();
          _csvStatus = null;
        });
        _fetchHistoryFirstPage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingCsv = false);
    }
  }

  Future<void> _simulateQRScan() async {
    setState(() => _isScanning = true);
    await Future.delayed(const Duration(seconds: 2));
    if (_availableMedicines.isNotEmpty) {
      final med = _availableMedicines[
          DateTime.now().second % _availableMedicines.length];
      final qty = 10 + (DateTime.now().millisecond % 40);
      setState(() {
        _scannedItems.add(
            {'medicine': med, 'quantity': qty, 'patients': (qty / 3).round()});
        _isScanning = false;
      });
    } else {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _submitScannedLogs() async {
    if (_scannedItems.isEmpty) return;
    setState(() => _isSubmittingQr = true);
    try {
      for (var item in _scannedItems) {
        await ref.read(firebaseServiceProvider).logUsage(
            facilityId: widget.facilityId,
            date: _selectedDate,
            medicineName: item['medicine'],
            quantity: item['quantity'],
            patients: item['patients']);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_scannedItems.length} logs saved ✓')));
        setState(() => _scannedItems.clear());
        _fetchHistoryFirstPage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingQr = false);
    }
  }

  Future<void> _parseImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      setState(() {
        _isParsingImage = true;
        _imageParseResult = null;
        _imageParseError = null;
      });
      final parsed = await ref.read(aiServiceProvider).parseImageWithVision(
          bytes,
          'Extract all medicine names, quantities, and patient counts from this image. Output JSON: [{"medicine": "string", "quantity": int, "patients": int}]');
      if (mounted) {
        setState(() {
          _imageParseResult = parsed;
          _isParsingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _imageParseError = e.toString();
          _isParsingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image parsing failed: $e'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _parseImage,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: const Text('Daily Logging'),
        actions: [
          IconButton(
            tooltip: 'Export usage logs (CSV)',
            icon: _isExportingCsv
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
            onPressed: _isExportingCsv ? null : _exportUsageLogsCsv,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.edit_note_rounded), text: 'Manual'),
            Tab(icon: Icon(Icons.upload_file_rounded), text: 'CSV'),
            Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'Scan'),
            Tab(icon: Icon(Icons.image_rounded), text: 'Image'),
            Tab(icon: Icon(Icons.history_rounded), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManualTab(),
          _buildCsvTab(),
          _buildQrTab(),
          _buildImageTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildManualTab() {
    return Center(
      child: Container(
        width: 480,
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: MediColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: MediColors.border)),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Log Medicine Usage',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: MediColors.textPrimary)),
                const SizedBox(height: 6),
                const Text('Feeds into AI forecasting model',
                    style:
                        TextStyle(color: MediColors.textMuted, fontSize: 13)),
                const SizedBox(height: 28),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date',
                      style: TextStyle(
                          color: MediColors.textSecondary, fontSize: 13)),
                  subtitle: Text(
                      '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                      style: const TextStyle(
                          color: MediColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.calendar_today_rounded,
                      color: MediColors.textMuted),
                  onTap: () async {
                    final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now());
                    if (date != null) setState(() => _selectedDate = date);
                  },
                ),
                const SizedBox(height: 16),
                if (_isLoadingInventory)
                  const Center(child: CircularProgressIndicator())
                else if (_availableMedicines.isEmpty)
                  Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: MediColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('No active inventory found.',
                          style: TextStyle(
                              color: MediColors.warning, fontSize: 13)))
                else
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Medicine'),
                    dropdownColor: MediColors.surfaceLight,
                    initialValue: _medName,
                    style: const TextStyle(color: MediColors.textPrimary),
                    items: _availableMedicines
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _medName = v),
                    validator: (v) => v == null ? 'Select a medicine' : null,
                  ),
                const SizedBox(height: 16),
                TextFormField(
                    decoration:
                        const InputDecoration(labelText: 'Units Distributed'),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: MediColors.textPrimary),
                    validator: (v) => (int.tryParse(v ?? '') == null)
                        ? 'Enter valid number'
                        : null,
                    onSaved: (v) => _quantity = int.parse(v!)),
                const SizedBox(height: 16),
                TextFormField(
                    decoration:
                        const InputDecoration(labelText: 'Patients Served'),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: MediColors.textPrimary),
                    validator: (v) => (int.tryParse(v ?? '') == null)
                        ? 'Enter valid number'
                        : null,
                    onSaved: (v) => _patients = int.parse(v!)),
                const SizedBox(height: 28),
                SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                        onPressed:
                            (_isSubmitting || _availableMedicines.isEmpty)
                                ? null
                                : _submitLog,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Save Log'))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCsvTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: MediColors.teal.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: MediColors.teal.withValues(alpha: 0.2))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: MediColors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.upload_file_rounded,
                      color: MediColors.teal, size: 22)),
              const SizedBox(width: 12),
              const Text('Bulk CSV Import',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: MediColors.teal)),
            ]),
            const SizedBox(height: 12),
            const Text(
                'Columns: MedicineName, UnitsDistributed, PatientsServed',
                style: TextStyle(color: MediColors.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                icon: const Icon(Icons.file_open_rounded),
                label: const Text('Choose CSV'),
                onPressed: _pickCSV),
          ]),
        ),
        if (_csvStatus != null) ...[
          const SizedBox(height: 16),
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: MediColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: MediColors.success, size: 18),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_csvStatus!,
                        style: const TextStyle(
                            color: MediColors.success, fontSize: 13)))
              ])),
        ],
        if (_csvItems.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  color: MediColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MediColors.border)),
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Medicine')),
                        DataColumn(label: Text('Units')),
                        DataColumn(label: Text('Patients')),
                        DataColumn(label: Text(''))
                      ],
                      rows: _csvItems
                          .map((item) => DataRow(cells: [
                                DataCell(Text(item['medicine'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(item['quantity'].toString())),
                                DataCell(Text(item['patients'].toString())),
                                DataCell(IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        color: MediColors.error, size: 18),
                                    onPressed: () => setState(
                                        () => _csvItems.remove(item)))),
                              ]))
                          .toList()))),
          const SizedBox(height: 20),
          SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                  icon: const Icon(Icons.save_rounded),
                  label: _isSubmittingCsv
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Submit ${_csvItems.length} Logs'),
                  onPressed: _isSubmittingCsv ? null : _submitCSVLogs)),
        ],
      ]),
    );
  }

  Widget _buildQrTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          height: 260,
          decoration: BoxDecoration(
              color: MediColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: MediColors.border)),
          child: Center(
            child: _isScanning
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                            color: MediColors.success, strokeWidth: 3)),
                    const SizedBox(height: 16),
                    const Text('Scanning...',
                        style:
                            TextStyle(color: MediColors.success, fontSize: 15)),
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.qr_code_scanner_rounded,
                        size: 64, color: MediColors.textMuted),
                    const SizedBox(height: 16),
                    const Text('Point camera at batch QR',
                        style: TextStyle(color: MediColors.textMuted)),
                    const SizedBox(height: 20),
                    Container(
                        decoration: BoxDecoration(
                            gradient: MediColors.cyanGradient,
                            borderRadius: BorderRadius.circular(12)),
                        child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent),
                            icon: const Icon(Icons.camera_alt_rounded),
                            label: const Text('Simulate Scan'),
                            onPressed: _simulateQRScan)),
                  ]),
          ),
        ),
        if (_scannedItems.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Scanned Items',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: MediColors.textPrimary)),
          const SizedBox(height: 12),
          Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  color: MediColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MediColors.border)),
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Medicine')),
                        DataColumn(label: Text('Units')),
                        DataColumn(label: Text('Patients')),
                        DataColumn(label: Text(''))
                      ],
                      rows: _scannedItems
                          .map((item) => DataRow(cells: [
                                DataCell(Text(item['medicine'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(item['quantity'].toString())),
                                DataCell(Text(item['patients'].toString())),
                                DataCell(IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        color: MediColors.error, size: 18),
                                    onPressed: () => setState(
                                        () => _scannedItems.remove(item)))),
                              ]))
                          .toList()))),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan Another'),
                    onPressed: _isScanning ? null : _simulateQRScan)),
            const SizedBox(width: 16),
            Expanded(
                child: FilledButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: _isSubmittingQr
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text('Submit ${_scannedItems.length}'),
                    onPressed: _isSubmittingQr ? null : _submitScannedLogs)),
          ]),
        ],
      ]),
    );
  }

  Widget _buildImageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: MediColors.violet.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: MediColors.violet.withValues(alpha: 0.2))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: MediColors.violet.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.image_rounded,
                      color: MediColors.violet, size: 22)),
              const SizedBox(width: 12),
              const Text('AI Image Parsing',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: MediColors.violet)),
            ]),
            const SizedBox(height: 12),
            const Text(
                'Upload a photo of medicine records for AI-powered extraction',
                style: TextStyle(color: MediColors.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                icon: _isParsingImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: MediColors.violet))
                    : const Icon(Icons.photo_camera_rounded),
                label: Text(_isParsingImage ? 'Parsing...' : 'Choose Image'),
                onPressed: _isParsingImage ? null : _parseImage),
          ]),
        ),
        if (_imageParseError != null) ...[
          const SizedBox(height: 16),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: MediColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: MediColors.error.withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: MediColors.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Parsing Failed',
                          style: TextStyle(
                              color: MediColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(_imageParseError!,
                          style: const TextStyle(
                              color: MediColors.textMuted, fontSize: 12),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ])),
                const SizedBox(width: 12),
                TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    onPressed: _parseImage),
              ])),
        ],
        if (_imageParseResult != null) ...[
          const SizedBox(height: 16),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: MediColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: MediColors.success.withValues(alpha: 0.2))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.check_circle_rounded,
                          color: MediColors.success, size: 18),
                      SizedBox(width: 10),
                      Text('AI Extraction Result',
                          style: TextStyle(
                              color: MediColors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                    ]),
                    const SizedBox(height: 10),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: MediColors.surface,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(_imageParseResult!,
                            style: const TextStyle(
                                color: MediColors.textSecondary,
                                fontSize: 13,
                                fontFamily: 'monospace'))),
                  ])),
        ],
      ]),
    );
  }

  // --- History tab UI ---

  Widget _buildHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_historyError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: MediColors.error, size: 40),
            const SizedBox(height: 12),
            Text('Failed to load history: $_historyError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: MediColors.textMuted)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              onPressed: _fetchHistoryFirstPage,
            ),
          ],
        ),
      );
    }

    if (_historyLogs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchHistoryFirstPage,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Icon(Icons.history_rounded, size: 48, color: MediColors.textMuted),
            SizedBox(height: 12),
            Center(
              child: Text('No usage logs yet',
                  style: TextStyle(color: MediColors.textMuted)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchHistoryFirstPage,
      child: ListView.builder(
        padding: const EdgeInsets.all(28),
        itemCount: _historyLogs.length + 1,
        itemBuilder: (context, index) {
          if (index == _historyLogs.length) {
            if (!_historyHasMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No more logs',
                      style: TextStyle(color: MediColors.textMuted)),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: OutlinedButton(
                  onPressed: _isLoadingMoreHistory ? null : _fetchMoreHistory,
                  child: _isLoadingMoreHistory
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Load More'),
                ),
              ),
            );
          }

          final log = _historyLogs[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MediColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MediColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${log.date.day}/${log.date.month}/${log.date.year}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: MediColors.textPrimary),
                    ),
                    Text(
                      '${log.totalPatients} patients',
                      style: const TextStyle(
                          color: MediColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: log.medicines
                      .map((m) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: MediColors.teal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${m.medicineName} × ${m.unitsDistributed}',
                              style: const TextStyle(
                                  color: MediColors.teal, fontSize: 12),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
