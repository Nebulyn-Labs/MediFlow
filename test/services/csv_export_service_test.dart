import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/daily_usage_log.dart';
import 'package:med_supply_prototype/services/csv_export_service.dart';

void main() {
  group('CsvExportService.buildTransferRequestHistoryRows', () {
    test('builds request history rows with UI-equivalent fields', () {
      final requests = [
        MedRequest(
          id: 'req-1',
          facilityId: 'fac-1',
          medicineName: 'Paracetamol',
          type: RequestType.surplus,
          quantity: 75,
          requestDate: DateTime(2026, 7, 24),
          status: RequestStatus.fulfilled,
          resolvedAt: DateTime(2026, 7, 25, 9, 30),
        ),
        MedRequest(
          id: 'req-2',
          facilityId: 'fac-1',
          medicineName: 'Amoxicillin',
          type: RequestType.regularIndent,
          quantity: 40,
          requestDate: DateTime(2026, 7, 20),
          status: RequestStatus.rejected,
          rejectionReason: 'Insufficient regional stock',
        ),
      ];

      final rows = CsvExportService.buildTransferRequestHistoryRows(requests);

      expect(rows.first, [
        'Submitted Date',
        'Medicine Name',
        'Request Type',
        'Quantity',
        'Status',
        'Resolved At',
        'Rejection Reason',
      ]);
      expect(rows[1], [
        '2026-07-24',
        'Paracetamol',
        'Offering Redistribution',
        75,
        'FULFILLED',
        '2026-07-25 09:30',
        '',
      ]);
      expect(rows[2], [
        '2026-07-20',
        'Amoxicillin',
        'Requesting Restock',
        40,
        'REJECTED',
        '',
        'Insufficient regional stock',
      ]);
    });
  });

  group('CsvExportService formatting', () {
    test('buildInventoryRows', () {
      final inventory = [
        InventoryItem(
          medicineName: 'Paracetamol',
          batchId: 'B1',
          remainingQuantity: 100,
          initialQuantity: 200,
          unit: 'tablets',
          arrivalDate: DateTime(2026, 7, 24),
          expiryDate: DateTime.now().add(const Duration(days: 30)),
          lastUpdated: DateTime(2026, 7, 25),
        ),
      ];
      final rows = CsvExportService.buildInventoryRows(inventory);
      expect(rows.length, 2);
      expect(rows.first, [
        'Medicine Name',
        'Batch ID',
        'Remaining Quantity',
        'Initial Quantity',
        'Unit',
        'Arrival Date',
        'Expiry Date',
        'Days To Expiry',
        'Last Updated',
      ]);
      expect(rows[1][0], 'Paracetamol');
      expect(rows[1][1], 'B1');
      expect(rows[1][2], 100);
    });

    test('buildUsageLogRows', () {
      final logs = [
        DailyUsageLog(
          id: 'log-1',
          date: DateTime(2026, 7, 24),
          totalPatients: 50,
          medicines: [
            MedicineUsage(medicineName: 'Paracetamol', unitsDistributed: 10)
          ],
        )
      ];
      final rows = CsvExportService.buildUsageLogRows(logs);
      expect(rows.length, 2);
      expect(rows.first, [
        'Date',
        'Medicine Name',
        'Units Distributed',
        'Total Patients (day)',
      ]);
      expect(rows[1], ['2026-07-24', 'Paracetamol', 10, 50]);
    });

    test('buildTransferRequestsRows', () {
      final requests = [
        MedRequest(
          id: 'req-1',
          facilityId: 'fac_1',
          medicineName: 'Paracetamol',
          type: RequestType.regularIndent,
          quantity: 10,
          requestDate: DateTime(2026, 7, 24),
          status: RequestStatus.approved,
        )
      ];
      final rows = CsvExportService.buildTransferRequestsRows(requests);
      expect(rows.length, 2);
      expect(rows.first, [
        'Date',
        'Facility',
        'Medicine',
        'Quantity',
        'Status',
        'Global Optimization',
      ]);
      expect(rows[1], ['2026-07-24', 'FAC 1', 'Paracetamol', 10, 'APPROVED', 'Optimize Routes']);
    });
  });
}
