import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/facility.dart';
import '../models/request.dart';
import '../models/inventory_item.dart';

final optimizationServiceProvider = Provider((ref) => OptimizationService());

class TransferRecommendation {
  final Facility donor;
  final Facility recipient;
  final String medicine;
  final int quantity;
  final double score;
  final String reasoning;

  TransferRecommendation({
    required this.donor,
    required this.recipient,
    required this.medicine,
    required this.quantity,
    required this.score,
    required this.reasoning,
  });
}

class MultiStopRoute {
  final List<TransferRecommendation> transfers;
  final List<Facility> stops;

  MultiStopRoute({
    required this.transfers,
    required this.stops,
  });
}

abstract class RoutingStrategy {
  List<Facility> buildRouteStops(
      Facility startNode, List<TransferRecommendation> transfers);
}

class NearestNeighborRoutingStrategy implements RoutingStrategy {
  const NearestNeighborRoutingStrategy();

  @override
  List<Facility> buildRouteStops(
      Facility startNode, List<TransferRecommendation> transfers) {
    final Distance distanceCalc = const Distance();

    final unvisited = <Facility>[];
    final seenRecipientIds = <String>{};
    for (final transfer in transfers) {
      if (seenRecipientIds.add(transfer.recipient.id)) {
        unvisited.add(transfer.recipient);
      }
    }

    List<Facility> orderedStops = [startNode];
    Facility current = startNode;

    while (unvisited.isNotEmpty) {
      Facility? nearest;
      double minDistance = double.infinity;

      for (var candidate in unvisited) {
        final dist = distanceCalc(
          LatLng(current.latitude, current.longitude),
          LatLng(candidate.latitude, candidate.longitude),
        );
        if (dist < minDistance) {
          minDistance = dist;
          nearest = candidate;
        }
      }

      if (nearest != null) {
        orderedStops.add(nearest);
        unvisited.remove(nearest);
        current = nearest;
      } else {
        break;
      }
    }

    return orderedStops;
  }
}

/// Redistribution matching and route-building for MediFlow's logistics
/// engine.
///
/// This service answers two questions:
///
/// 1. Which donor facility should fulfil which pending request, and how
///    much of a medicine should move ([calculateOptimalTransfers])?
/// 2. Given a set of transfers from the same donor, in what order should
///    that donor visit its recipients ([calculateMultiStopRoutes])?
///
/// ### Inputs
/// - `facilities`: every facility in the network, used for location, type
///   (`rural`/`urban`), and identity.
/// - `inventories`: current stock per facility, keyed by facility id.
/// - `requests`: pending/approved [MedRequest]s. Only `regularIndent` and
///   `shortage` requests represent deficits; `surplus` requests are explicit
///   donor offers, layered on top of implicit surplus derived from
///   inventory (see below).
///
/// ### Outputs
/// - [TransferRecommendation]: a single donor -> recipient -> medicine ->
///   quantity match, with a `score` and human-readable `reasoning`.
/// - [MultiStopRoute]: transfers grouped by donor, with `stops` ordered by
///   the configured [RoutingStrategy].
///
/// ### Algorithm assumptions
/// - **Implicit surplus:** any facility holding more than 30% of a
///   medicine's `initialQuantity` is treated as having that excess (above
///   the 30% floor) available to donate, even without an explicit surplus
///   request. Explicit surplus offers override this figure when larger.
/// - **Indent ordering:** deficits are processed rural-facilities-first,
///   then by descending quantity, so that larger and more vulnerable needs
///   are matched before smaller/urban ones exhaust the available surplus.
/// - **Scoring (Optimal Transfer Score):** for each candidate donor of a
///   given medicine, a score is computed from proximity (closer is worth
///   more, capped at 200km), a flat +150 bonus when the recipient is rural,
///   and a fulfillment bonus (+50 full, +25 partial). The highest-scoring
///   donor is chosen per iteration; this repeats until the deficit is met
///   or no donor has stock left, allowing a single indent to be split
///   across multiple donors.
/// - **Routing** ([NearestNeighborRoutingStrategy]): stops for a donor are
///   ordered with a simple greedy nearest-neighbor heuristic starting from
///   the donor's own location. This is not a shortest-path/TSP solver — it
///   is a fast approximation intended to produce a reasonable multi-stop
///   delivery order, not a mathematically optimal one.
class OptimizationService {
  final RoutingStrategy _strategy;

  OptimizationService({
    RoutingStrategy strategy = const NearestNeighborRoutingStrategy(),
  }) : _strategy = strategy;

  List<TransferRecommendation> calculateOptimalTransfers({
    required List<Facility> facilities,
    required Map<String, List<InventoryItem>> inventories,
    required List<MedRequest> requests,
  }) {
    List<TransferRecommendation> recommendations = [];
    final Distance distanceCalc = const Distance();
    final facilityById = {
      for (final facility in facilities) facility.id: facility
    };

    // 1. Group needs (shortage or regular indent) by medicine
    final pendingIndents = <MedRequest>[];
    for (final request in requests) {
      if (!((request.status == RequestStatus.pending ||
              request.status == RequestStatus.approved) &&
          (request.type == RequestType.regularIndent ||
              request.type == RequestType.shortage))) {
        continue;
      }

      if (!facilityById.containsKey(request.facilityId)) {
        debugPrint(
          'OptimizationService: Skipping request ${request.id} because facility ${request.facilityId} is not in the active facility list.',
        );
        continue;
      }

      pendingIndents.add(request);
    }

    // 2. Group explicit surplus offers
    final surplusOffers = <MedRequest>[];
    for (final request in requests) {
      if (!((request.status == RequestStatus.pending ||
              request.status == RequestStatus.approved) &&
          request.type == RequestType.surplus)) {
        continue;
      }

      if (!facilityById.containsKey(request.facilityId)) {
        debugPrint(
          'OptimizationService: Skipping surplus request ${request.id} because facility ${request.facilityId} is not in the active facility list.',
        );
        continue;
      }

      surplusOffers.add(request);
    }

    // Track working surpluses to allow multi-fulfillment
    Map<String, Map<String, int>> workingSurpluses =
        {}; // {facilityId: {medicineName: surplusQty}}

    // Initialize with live inventory levels (anything above 30% is a potential surplus)
    for (var f in facilities) {
      workingSurpluses[f.id] = {};
      final inv = inventories[f.id] ?? [];
      for (var item in inv) {
        int surplus =
            item.remainingQuantity - (item.initialQuantity * 0.3).toInt();
        if (surplus > 0) {
          workingSurpluses[f.id]![item.medicineName] = surplus;
        }
      }
    }

    // Layer in explicit surplus offers (these take precedence or add to it)
    for (var offer in surplusOffers) {
      workingSurpluses[offer.facilityId] ??= {};
      final current =
          workingSurpluses[offer.facilityId]![offer.medicineName] ?? 0;
      // Use the max of live surplus or explicit offer
      if (offer.quantity > current) {
        workingSurpluses[offer.facilityId]![offer.medicineName] =
            offer.quantity;
      }
    }

    // 2. Process each indent (Deficit)
    // Sort indents: Rural first, then by quantity (larger first)
    final sortedIndents = List<MedRequest>.from(pendingIndents)
      ..sort((a, b) {
        final facA = facilityById[a.facilityId];
        final facB = facilityById[b.facilityId];

        if (facA == null && facB == null) {
          return b.quantity.compareTo(a.quantity);
        }
        if (facA == null) {
          return 1;
        }
        if (facB == null) {
          return -1;
        }

        if (facA.type == 'rural' && facB.type != 'rural') {
          return -1;
        }
        if (facB.type == 'rural' && facA.type != 'rural') {
          return 1;
        }
        return b.quantity.compareTo(a.quantity);
      });

    for (var indent in sortedIndents) {
      final recipientFac = facilityById[indent.facilityId];
      if (recipientFac == null) {
        debugPrint(
          'OptimizationService: Skipping request ${indent.id} because facility ${indent.facilityId} disappeared during optimization.',
        );
        continue;
      }

      final medicine = indent.medicineName;
      int remainingDeficit = indent.quantity;

      while (remainingDeficit > 0) {
        // Find best donor for THIS medicine
        Map<String, dynamic>? bestDonorMatch;
        double highestScore = -1;

        for (var donorFac in facilities) {
          if (donorFac.id == recipientFac.id) continue;

          final available = workingSurpluses[donorFac.id]?[medicine] ?? 0;
          if (available <= 0) continue;

          // Calculate Dynamic Score
          double score = 0;
          List<String> reasons = [];

          // A. Distance Score
          final distKm = distanceCalc(
                  LatLng(donorFac.latitude, donorFac.longitude),
                  LatLng(recipientFac.latitude, recipientFac.longitude)) /
              1000;
          double distScore = (200 - distKm).clamp(0, 200);
          score += distScore;
          reasons.add('Proximity (${distKm.toStringAsFixed(1)}km)');

          // B. Rural Priority
          if (recipientFac.type == 'rural') {
            score += 150;
            reasons.add('Rural Priority');
          }

          // C. Quantity Match (Bonus if donor can fulfill a lot)
          int qtyToTake =
              remainingDeficit < available ? remainingDeficit : available;
          if (qtyToTake == remainingDeficit) {
            score += 50;
            reasons.add('Full Fulfillment');
          } else {
            score += 25;
            reasons.add('Partial Fulfillment');
          }

          // D. Near-Expiry Priority (+100 when soonest valid batch expires ≤90 days)
          // Prefer donors whose surplus expires soonest so stock is redistributed
          // before wastage, matching the documented heuristic in the AI prompt.
          // Only non-expired batches are considered: a batch that already expired
          // gives a negative daysUntilExpiry which would satisfy <= 90 and
          // incorrectly rank expired stock above fresh stock.
          final donorBatches = inventories[donorFac.id] ?? [];
          final validMedicineBatches = donorBatches
              .where((item) =>
                  item.medicineName == medicine &&
                  item.expiryDate.isAfter(DateTime.now()))
              .toList();
          if (validMedicineBatches.isNotEmpty) {
            final soonestExpiry = validMedicineBatches
                .map((item) => item.expiryDate)
                .reduce((a, b) => a.isBefore(b) ? a : b);
            final daysUntilExpiry =
                soonestExpiry.difference(DateTime.now()).inDays;
            if (daysUntilExpiry >= 0 && daysUntilExpiry <= 90) {
              score += 100;
              reasons.add('Near Expiry (${daysUntilExpiry}d)');
            }
          }

          if (score > highestScore) {
            highestScore = score;
            bestDonorMatch = {
              'donor': donorFac,
              'qty': qtyToTake,
              'score': score,
              'reasoning': reasons.join(' + '),
            };
          }
        }

        if (bestDonorMatch != null) {
          final donorFac = bestDonorMatch['donor'] as Facility;
          final qtyTaken = bestDonorMatch['qty'] as int;

          recommendations.add(TransferRecommendation(
            donor: donorFac,
            recipient: recipientFac,
            medicine: medicine,
            quantity: qtyTaken,
            score: bestDonorMatch['score'],
            reasoning: bestDonorMatch['reasoning'],
          ));

          // Update state
          remainingDeficit -= qtyTaken;
          workingSurpluses[donorFac.id]![medicine] =
              (workingSurpluses[donorFac.id]![medicine] ?? 0) - qtyTaken;
        } else {
          // No donors left for this medicine
          break;
        }
      }
    }

    return recommendations;
  }

  List<MultiStopRoute> calculateMultiStopRoutes({
    required List<Facility> facilities,
    required Map<String, List<InventoryItem>> inventories,
    required List<MedRequest> requests,
    RoutingStrategy? routingStrategy,
  }) {
    final strategy = routingStrategy ?? _strategy;

    final recommendations = calculateOptimalTransfers(
      facilities: facilities,
      inventories: inventories,
      requests: requests,
    );

    final Map<String, List<TransferRecommendation>> groupedByDonor = {};
    for (var rec in recommendations) {
      groupedByDonor.putIfAbsent(rec.donor.id, () => []).add(rec);
    }

    final List<MultiStopRoute> multiStopRoutes = [];
    for (var entry in groupedByDonor.entries) {
      final transfers = entry.value;
      if (transfers.isEmpty) continue;

      final donor = transfers.first.donor;
      final stops = strategy.buildRouteStops(donor, transfers);

      multiStopRoutes.add(MultiStopRoute(
        transfers: transfers,
        stops: stops,
      ));
    }

    return multiStopRoutes;
  }
}
