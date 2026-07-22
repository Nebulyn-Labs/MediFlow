import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/inventory_item.dart';
import '../models/daily_usage_log.dart';

/// Class representing a row-level failure in CSV import.
class CsvRowError {
  final int lineNumber;
  final String rawData;
  final String reason;

  CsvRowError({
    required this.lineNumber,
    required this.rawData,
    required this.reason,
  });
}

/// Class holding the summary of a bulk CSV upload operation.
class CsvUploadResult<T> {
  final int totalRows;
  final List<T> successfulRecords;
  final List<CsvRowError> failures;

  CsvUploadResult({
    required this.totalRows,
    required this.successfulRecords,
    required this.failures,
  });

  bool get isFullySuccessful => failures.isEmpty && totalRows > 0;
  bool get isPartialFailure => failures.isNotEmpty && successfulRecords.isNotEmpty;
  bool get isTotalFailure => successfulRecords.isEmpty && totalRows > 0;
}

/// Handles converting MediFlow domain models into CSV files and parsing CSVs
/// with robust error catching for bulk imports.
class CsvExportService {
  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _stampFmt = DateFormat('yyyyMMdd_HHmmss');

  /// Parses CSV raw content string into DailyUsageLog domain objects.
  /// Handles partial failures by isolating malformed rows and returning a summary.
  static CsvUploadResult<DailyUsageLog> parseUsageLogsCsv(
    String csvContent, {
    required String facilityId,
  }) {
    final fields = const CsvToListConverter(eol: '\n').convert(csvContent);
    if (fields.isEmpty) {
      return CsvUploadResult(
        totalRows: 0,
        successfulRecords: [],
        failures: [],
      );
    }

    // Skip header row if present
    int startIndex = 0;
    if (fields.first.isNotEmpty &&
        fields.first[0].toString().toLowerCase().contains('date')) {
      startIndex = 1;
    }

    final List<DailyUsageLog> successLogs = [];
    final List<CsvRowError> failures = [];
    final totalRows = fields.length - startIndex;

    for (int i = startIndex; i < fields.length; i++) {
      final lineNumber = i + 1;
      final row = fields[i];

      if (row.isEmpty || (row.length == 1 && row[0].toString().trim().isEmpty)) {
        continue; // Skip blank lines
      }

      try {
        if (row.length < 4) {
          throw 'Insufficient columns. Expected 4 columns (Date, Medicine Name, Units, Patients).';
        }

        final dateStr = row[0].toString().trim();
        final medicineName = row[1].toString().trim();
        final unitsStr = row[2].toString().trim();
        final patientsStr = row[3].toString().trim();

        if (dateStr.isEmpty) throw 'Date field is required.';
        if (medicineName.isEmpty) throw 'Medicine Name is required.';

        final parsedDate = _dateFmt.parseStrict(dateStr);
        final unitsDistributed = int.tryParse(unitsStr);
        final totalPatients = int.tryParse(patientsStr);

        if (unitsDistributed == null || unitsDistributed < 0) {
          throw 'Invalid Units Distributed value: "$unitsStr". Must be a non-negative integer.';
        }
        if (totalPatients == null || totalPatients < 0) {
          throw 'Invalid Total Patients value: "$patientsStr". Must be a non-negative integer.';
        }

        final log = DailyUsageLog(
          id: '${facilityId}_${_dateFmt.format(parsedDate)}',
          facilityId: facilityId,
          date: parsedDate,
          totalPatients: totalPatients,
          medicines: [
            MedicineUsage(
              medicineName: medicineName,
              unitsDistributed: unitsDistributed,
            ),
          ],
        );

        successLogs.add(log);
      } catch (e) {
        failures.add(
          CsvRowError(
            lineNumber: lineNumber,
            rawData: row.join(','),
            reason: e.toString().replaceAll('Exception: ', ''),
          ),
        );
      }
    }

    return CsvUploadResult<DailyUsageLog>(
      totalRows: totalRows,
      successfulRecords: successLogs,
      failures: failures,
    );
  }

  /// Exports the given inventory list as a CSV file.
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

  /// Exports the given daily usage logs as a CSV file.
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
