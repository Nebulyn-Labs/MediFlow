import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/inventory_item.dart';
import 'package:med_supply_prototype/models/request.dart';
import 'package:med_supply_prototype/services/optimization_service.dart';

const _testDate = '2026-07-22T00:00:00.000Z';

Facility facility(
  String id, {
  String type = 'urban',
  double latitude = 0,
  double longitude = 0,
}) {
  return Facility(
    id: id,
    name: 'Facility $id',
    email: '$id@mediflow.test',
    type: type,
    region: 'Test Region',
    latitude: latitude,
    longitude: longitude,
    createdAt: DateTime.parse(_testDate),
  );
}

InventoryItem inventory(
  String facilityId,
  String medicine, {
  int initial = 100,
  int remaining = 100,
}) {
  final date = DateTime.parse(_testDate);
  return InventoryItem(
    id: '$facilityId-$medicine',
    medicineName: medicine,
    batchId: 'batch-1',
    arrivalDate: date,
    expiryDate: date.add(const Duration(days: 180)),
    initialQuantity: initial,
    remainingQuantity: remaining,
    unit: 'units',
    lastUpdated: date,
    facilityId: facilityId,
  );
}

MedRequest request(
  String id,
  String facilityId,
  String medicine,
  int quantity, {
  RequestType type = RequestType.shortage,
  RequestStatus status = RequestStatus.pending,
}) {
  return MedRequest(
    id: id,
    facilityId: facilityId,
    medicineName: medicine,
    type: type,
    quantity: quantity,
    requestDate: DateTime.parse(_testDate),
    status: status,
  );
}

int totalQuantity(List<TransferRecommendation> recommendations) {
  return recommendations.fold(0, (total, item) => total + item.quantity);
}

class RecordingRoutingStrategy implements RoutingStrategy {
  int callCount = 0;
  List<String> receivedRecipientIds = [];

  @override
  List<Facility> buildRouteStops(
    Facility startNode,
    List<TransferRecommendation> transfers,
  ) {
    callCount += 1;
    receivedRecipientIds = transfers.map((item) => item.recipient.id).toList();
    return [startNode, ...transfers.map((item) => item.recipient)];
  }
}

void main() {
  group('OptimizationService regression coverage', () {
    late OptimizationService service;

    setUp(() {
      service = OptimizationService();
    });

    test('processes approved needs and ignores inactive request statuses', () {
      final donor = facility('donor');
      final approvedRecipient = facility('approved-recipient');
      final inactiveRecipient = facility('inactive-recipient');
      final requests = [
        request(
          'approved',
          approvedRecipient.id,
          'ORS',
          20,
          status: RequestStatus.approved,
        ),
        request(
          'draft',
          inactiveRecipient.id,
          'ORS',
          20,
          status: RequestStatus.draft,
        ),
        request(
          'fulfilled',
          inactiveRecipient.id,
          'ORS',
          20,
          status: RequestStatus.fulfilled,
        ),
        request(
          'rejected',
          inactiveRecipient.id,
          'ORS',
          20,
          status: RequestStatus.rejected,
        ),
      ];

      final result = service.calculateOptimalTransfers(
        facilities: [donor, approvedRecipient, inactiveRecipient],
        inventories: {
          donor.id: [inventory(donor.id, 'ORS')],
        },
        requests: requests,
      );

      expect(result, hasLength(1));
      expect(result.single.recipient.id, approvedRecipient.id);
      expect(result.single.quantity, 20);
    });

    test('prioritizes larger requests when facility priority is equal', () {
      final donor = facility('donor');
      final smallRecipient = facility('small', latitude: 0.1);
      final largeRecipient = facility('large', latitude: 0.2);

      final result = service.calculateOptimalTransfers(
        facilities: [donor, smallRecipient, largeRecipient],
        inventories: {
          donor.id: [inventory(donor.id, 'ORS')],
        },
        requests: [
          request('small-request', smallRecipient.id, 'ORS', 20),
          request('large-request', largeRecipient.id, 'ORS', 60),
        ],
      );

      expect(result, hasLength(2));
      expect(result.first.recipient.id, largeRecipient.id);
      expect(result.first.quantity, 60);
      expect(result.last.recipient.id, smallRecipient.id);
      expect(result.last.quantity, 10);
    });

    test('uses the larger of live surplus and an explicit surplus offer', () {
      final donor = facility('donor');
      final recipient = facility('recipient');

      final result = service.calculateOptimalTransfers(
        facilities: [donor, recipient],
        inventories: {
          donor.id: [inventory(donor.id, 'Paracetamol', remaining: 50)],
        },
        requests: [
          request(
            'surplus-offer',
            donor.id,
            'Paracetamol',
            50,
            type: RequestType.surplus,
          ),
          request('need', recipient.id, 'Paracetamol', 80),
        ],
      );

      // Live surplus is 20 and the explicit offer is 50. They must not be
      // double-counted as 70 units.
      expect(totalQuantity(result), 50);
    });

    test('does not leak consumed surplus between independent calculations', () {
      final donor = facility('donor');
      final recipient = facility('recipient');
      final inventories = {
        donor.id: [inventory(donor.id, 'ORS')],
      };
      final requests = [request('need', recipient.id, 'ORS', 40)];

      final first = service.calculateOptimalTransfers(
        facilities: [donor, recipient],
        inventories: inventories,
        requests: requests,
      );
      final second = service.calculateOptimalTransfers(
        facilities: [donor, recipient],
        inventories: inventories,
        requests: requests,
      );

      expect(totalQuantity(first), 40);
      expect(totalQuantity(second), 40);
      expect(inventories[donor.id]!.single.remainingQuantity, 100);
      expect(requests.single.quantity, 40);
    });

    test(
      'produces the documented score and reasoning for a rural recipient',
      () {
        final donor = facility('donor');
        final recipient = facility('recipient', type: 'rural');

        final result = service.calculateOptimalTransfers(
          facilities: [donor, recipient],
          inventories: {
            donor.id: [inventory(donor.id, 'ORS')],
          },
          requests: [request('need', recipient.id, 'ORS', 20)],
        );

        expect(result, hasLength(1));
        expect(result.single.score, 400);
        expect(
          result.single.reasoning,
          'Proximity (0.0km) + Rural Priority + Full Fulfillment',
        );
      },
    );

    test(
      'clamps distance contribution to zero for donors over 200 km away',
      () {
        final donor = facility('donor', latitude: 10, longitude: 10);
        final recipient = facility('recipient');

        final result = service.calculateOptimalTransfers(
          facilities: [donor, recipient],
          inventories: {
            donor.id: [inventory(donor.id, 'ORS')],
          },
          requests: [request('need', recipient.id, 'ORS', 20)],
        );

        expect(result.single.score, 50);
        expect(result.single.reasoning, endsWith('Full Fulfillment'));
      },
    );

    test('resolves equal donor scores deterministically by facility order', () {
      final firstDonor = facility('first-donor');
      final secondDonor = facility('second-donor');
      final recipient = facility('recipient');
      final inventories = {
        firstDonor.id: [inventory(firstDonor.id, 'ORS')],
        secondDonor.id: [inventory(secondDonor.id, 'ORS')],
      };

      final result = service.calculateOptimalTransfers(
        facilities: [firstDonor, secondDonor, recipient],
        inventories: inventories,
        requests: [request('need', recipient.id, 'ORS', 20)],
      );

      expect(result.single.donor.id, firstDonor.id);
    });
  });

  group('NearestNeighborRoutingStrategy regression coverage', () {
    const strategy = NearestNeighborRoutingStrategy();

    test('returns only the start node when there are no transfers', () {
      final donor = facility('donor');

      expect(strategy.buildRouteStops(donor, []), [donor]);
    });

    test('orders nearest recipients and removes duplicate recipient stops', () {
      final donor = facility('donor');
      final near = facility('near', latitude: 0.1);
      final far = facility('far', latitude: 1);
      final transfers = [
        TransferRecommendation(
          donor: donor,
          recipient: far,
          medicine: 'ORS',
          quantity: 10,
          score: 1,
          reasoning: 'test',
        ),
        TransferRecommendation(
          donor: donor,
          recipient: near,
          medicine: 'ORS',
          quantity: 10,
          score: 1,
          reasoning: 'test',
        ),
        TransferRecommendation(
          donor: donor,
          recipient: near,
          medicine: 'Paracetamol',
          quantity: 10,
          score: 1,
          reasoning: 'test',
        ),
      ];

      final stops = strategy.buildRouteStops(donor, transfers);

      expect(stops.map((item) => item.id), ['donor', 'near', 'far']);
    });
  });

  test('calculateMultiStopRoutes supports an injected routing strategy', () {
    final strategy = RecordingRoutingStrategy();
    final donor = facility('donor');
    final recipient = facility('recipient');
    final service = OptimizationService(strategy: strategy);

    final routes = service.calculateMultiStopRoutes(
      facilities: [donor, recipient],
      inventories: {
        donor.id: [inventory(donor.id, 'ORS')],
      },
      requests: [request('need', recipient.id, 'ORS', 20)],
    );

    expect(strategy.callCount, 1);
    expect(strategy.receivedRecipientIds, [recipient.id]);
    expect(routes.single.stops.map((item) => item.id), ['donor', 'recipient']);
  });
}
