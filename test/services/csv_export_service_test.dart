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

  group('CsvExportService.buildIndentRequestRows', () {
    test('builds indent request rows with admin-relevant fields (#85)', () {
      final requests = [
        MedRequest(
          id: 'req-1',
          facilityId: 'central_phc',
          medicineName: 'Paracetamol',
          type: RequestType.regularIndent,
          quantity: 75,
          requestDate: DateTime(2026, 7, 24),
          status: RequestStatus.pending,
          notes: 'Urgent restock',
        ),
        MedRequest(
          id: 'req-2',
          facilityId: 'rural_phc',
          medicineName: 'Amoxicillin',
          type: RequestType.surplus,
          quantity: 40,
          requestDate: DateTime(2026, 7, 20),
          status: RequestStatus.rejected,
          rejectionReason: 'Insufficient regional stock',
          resolvedAt: DateTime(2026, 7, 21, 9, 30),
        ),
        MedRequest(
          id: 'req-3',
          facilityId: 'rural_phc',
          medicineName: 'Insulin',
          type: RequestType.shortage,
          quantity: 10,
          requestDate: DateTime(2026, 7, 22),
          status: RequestStatus.needsManualReview,
        ),
      ];

      final rows = CsvExportService.buildIndentRequestRows(requests);

      expect(rows.first, [
        'Date',
        'Facility',
        'Medicine',
        'Request Type',
        'Quantity',
        'Status',
        'Facility Notes',
        'Rejection Reason',
        'Resolved At',
      ]);
      // Newest request first.
      expect(rows[1], [
        '2026-07-24',
        'CENTRAL PHC',
        'Paracetamol',
        'Restock',
        75,
        'PENDING',
        'Urgent restock',
        '',
        '',
      ]);
      expect(rows[2], [
        '2026-07-22',
        'RURAL PHC',
        'Insulin',
        'Shortage',
        10,
        'NEEDS REVIEW',
        '',
        '',
        '',
      ]);
      expect(rows[3], [
        '2026-07-20',
        'RURAL PHC',
        'Amoxicillin',
        'Redistribution',
        40,
        'REJECTED',
        '',
        'Insufficient regional stock',
        '2026-07-21 09:30',
      ]);
    });
  });
}
