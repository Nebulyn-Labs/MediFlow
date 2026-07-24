import 'package:flutter_test/flutter_test.dart';
import 'package:mediflow/models/facility.dart';
import 'package:mediflow/models/request.dart';
import 'package0mediflow/models/transfer_recommendation.dart'; // Adjust if model import uses request/indent
import 'package:mediflow/services/optimization_service.dart';

void main() {
  group('OptimizationService - Missing Facility Guard (#99)', () {
    test('calculateOptimalTransfers gracefully skips requests referencing non-existent facilityId', () {
      final activeFacility = Facility(
        id: 'fac-1',
        name: 'District Hospital',
        district: 'Central',
        latitude: 28.6139,
        longitude: 77.2090,
        inventory: {'Paracetamol': 500},
      );

      final validIndent = IndentRequest(
        id: 'req-valid',
        facilityId: 'fac-1',
        medicineName: 'Paracetamol',
        requestedQty: 50,
        createdAt: DateTime.now(),
      );

      final orphanIndent = IndentRequest(
        id: 'req-ghost',
        facilityId: 'deleted-facility-999',
        medicineName: 'Paracetamol',
        requestedQty: 100,
        createdAt: DateTime.now(),
      );

      final transfers = OptimizationService.calculateOptimalTransfers(
        facilities: [activeFacility],
        pendingIndents: [validIndent, orphanIndent],
      );

      expect(transfers, isA<List<dynamic>>());
      expect(transfers.any((t) => t.indentId == 'req-ghost'), isFalse);
    });
  });
}
