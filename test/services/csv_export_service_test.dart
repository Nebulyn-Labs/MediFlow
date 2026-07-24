import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/request.dart';
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
}
