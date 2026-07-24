import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/inventory_item.dart';
import '../models/daily_usage_log.dart';
import '../models/request.dart';
import '../models/request.dart';

/// Handles converting MediFlow domain models into CSV files and letting the
/// user save/download them. Works across web, desktop and mobile since it
/// relies solely on [FilePicker.saveFile] with in-memory bytes rather than
/// `dart:io`.
class CsvExportService {
  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _stampFmt = DateFormat('yyyyMMdd_HHmmss');

  /// Exports the given inventory list as a CSV file and prompts the user to
  /// save/download it. Returns the saved path (or null if the user
  /// cancelled the save dialog).
  static Future<String?> exportInventory(
    List<InventoryItem> inventory, {
    String? facilityName,
  }) async {
    final rows = <List<dynamic>>[
      [
        'Medicine Name',
        'Batch ID',
        'Remaining Quantity',
        'Initial Quantity',
        'Unit',
        'Arrival Date',
        'Expiry Date',
        'Days To Expiry',
        'Last Updated',
      ],
    ];

    for (final item in inventory) {
      final daysToExpiry = item.expiryDate.difference(DateTime.now()).inDays;
      rows.add([
        item.medicineName,
        item.batchId,
        item.remainingQuantity,
        item.initialQuantity,
        item.unit,
        _dateFmt.format(item.arrivalDate),
        _dateFmt.format(item.expiryDate),
        daysToExpiry,
        _dateFmt.format(item.lastUpdated),
      ]);
    }

    final fileName =
        'inventory_${_slug(facilityName)}${_stampFmt.format(DateTime.now())}.csv';
    return _saveCsv(rows, fileName);
  }

  /// Exports the given daily usage logs as a CSV file (one row per
  /// medicine/day) and prompts the user to save/download it.
  static Future<String?> exportUsageLogs(
    List<DailyUsageLog> logs, {
    String? facilityName,
  }) async {
    final rows = <List<dynamic>>[
      [
        'Date',
        'Medicine Name',
        'Units Distributed',
        'Total Patients (day)',
      ],
    ];

    final sorted = [...logs]..sort((a, b) => a.date.compareTo(b.date));
    for (final log in sorted) {
      if (log.medicines.isEmpty) {
        rows.add([_dateFmt.format(log.date), '', 0, log.totalPatients]);
        continue;
      }
      for (final usage in log.medicines) {
        rows.add([
          _dateFmt.format(log.date),
          usage.medicineName,
          usage.unitsDistributed,
          log.totalPatients,
        ]);
      }
    }

    final fileName =
        'usage_logs_${_slug(facilityName)}${_stampFmt.format(DateTime.now())}.csv';
    return _saveCsv(rows, fileName);
  }

  /// Exports transfer request history as CSV and prompts the user to
  /// save/download it.
  static Future<String?> exportTransferRequests(
    List<MedRequest> requests, {
    String? facilityName,
  }) async {
    final rows = buildTransferRequestRows(requests);
    final fileName =
        'transfer_requests_${_slug(facilityName)}${_stampFmt.format(DateTime.now())}.csv';
    return _saveCsv(rows, fileName);
  }

  static List<List<dynamic>> buildTransferRequestRows(List<MedRequest> requests) {
    final rows = <List<dynamic>>[
      [
        'Submitted Date',
        'Medicine Name',
        'Request Type',
        'Quantity',
        'Status',
        'Resolved At',
        'Rejection Reason',
      ],
    ];

    for (final req in requests) {
      rows.add([
        _dateFmt.format(req.requestDate),
        req.medicineName,
        req.type == RequestType.surplus
            ? 'Offering Redistribution'
            : 'Requesting Restock',
        req.quantity,
        req.status.name.toUpperCase(),
        req.resolvedAt == null ? '' : _dateTimeFmt.format(req.resolvedAt!),
        req.rejectionReason ?? '',
      ]);
    }

    return rows;
  }

  /// Exports transfer request history as CSV with columns aligned to the
  /// admin transfer request status table.
  static Future<String?> exportTransferRequests(
    List<MedRequest> requests,
  ) async {
    final rows = <List<dynamic>>[
      [
        'Date',
        'Facility',
        'Medicine',
        'Quantity',
        'Status',
        'Global Optimization',
      ],
    ];

    final sorted = [...requests]
      ..sort((a, b) => b.requestDate.compareTo(a.requestDate));
    for (final request in sorted) {
      final facilityLabel =
          request.facilityId.replaceAll('_', ' ').toUpperCase();
      rows.add([
        _dateFmt.format(request.requestDate),
        facilityLabel,
        request.medicineName,
        request.quantity,
        request.status.name.toUpperCase(),
        request.status == RequestStatus.approved ? 'Optimize Routes' : '—',
      ]);
    }

    final fileName = 'transfer_requests_${_stampFmt.format(DateTime.now())}.csv';
    return _saveCsv(rows, fileName);
  }

  static String _slug(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final cleaned =
        name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return '${cleaned}_';
  }

  static Future<String?> _saveCsv(
      List<List<dynamic>> rows, String fileName) async {
    final csvString = const CsvEncoder().convert(rows);
    final bytes = Uint8List.fromList(utf8.encode(csvString));

    return FilePicker.saveFile(
      dialogTitle: 'Save CSV export',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
    );
  }
}
