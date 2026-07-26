# Optimization, Routing & Simulation Algorithms

This document is a developer-oriented overview of the three services that
implement MediFlow's redistribution logic and demo data generation:
`OptimizationService`, `RoutingService`, and `SimulationService`. Each
service also carries file-level dartdoc comments; this page ties them
together and gives a workflow-level view.

## OptimizationService (`lib/services/optimization_service.dart`)

Matches pending requests to donor facilities and orders multi-stop delivery
routes.

**Inputs:** the full list of `Facility` records, current inventory per
facility, and pending/approved `MedRequest`s.

**Outputs:** `TransferRecommendation`s (donor, recipient, medicine,
quantity, score, reasoning) and `MultiStopRoute`s (transfers grouped by
donor, with an ordered list of stops).

**Flow:**

1. Compute each facility's implicit surplus per medicine: stock above 30%
   of `initialQuantity`. Explicit surplus requests can raise this figure.
2. Sort pending deficits (regular indents and shortages) rural-first, then
   by descending quantity.
3. For each deficit, score every candidate donor using the Optimal
   Transfer Score: proximity (capped contribution at 200km), a flat +150
   bonus for rural recipients, and a fulfillment bonus (+50 full, +25
   partial). Pick the highest-scoring donor, repeat until the deficit is
   met or donors are exhausted, allowing a single indent to be split
   across multiple donors.
4. Group the resulting transfers by donor and hand each donor's transfer
   list to a `RoutingStrategy` (the nearest-neighbor greedy heuristic by
   default) to produce an ordered stop list.

**Key assumption:** the routing strategy is a fast approximation, not a
shortest-path/TSP solver — it optimizes for a reasonable delivery order,
not a mathematically optimal one. It is also pluggable: `OptimizationService`
takes a `RoutingStrategy` so alternative strategies can be substituted
without changing the matching logic above.

## RoutingService (`lib/services/routing_service.dart`)

Converts stop coordinates into road-accurate polylines for the map view.

**Inputs:** a start/end coordinate pair (`getRoute`), or an ordered list of
stops (`getMultiStopRoute`), typically the stops produced by
`OptimizationService`.

**Outputs:** a list of coordinates describing the road path, with
per-segment routes concatenated for multi-stop requests.

**Flow:** coordinates are validated first (rejecting placeholder or
out-of-range coordinates without an external call). ORS is tried first if
an API key is configured, then OSRM, then a straight-line fallback if both
fail or time out. Each segment is fetched independently with no caching or
retries.

**Key assumption:** a failed or skipped external call degrades to a
straight line rather than blocking the UI, so a rendered multi-stop route
may mix real road polylines with straight-line segments.

## SimulationService (`lib/services/simulation_service.dart`)

Generates demo facility profiles, inventory, and 31 days of usage history
so new facilities have realistic-looking data without manual seeding.

**Inputs:** an optional facility `type` for profile generation, or a
`facilityId` and `facilityType` for a full simulation run.

**Outputs:** `generateRealisticProfile` returns a facility field map;
`runFullSimulation` writes inventory and daily usage logs directly to
Firestore via batched writes (no return value).

**Flow:**

1. Seed inventory for a fixed medicine list if it doesn't already exist,
   with facility-specific expiry overrides for the demo facility
   `rampur_mediflow_com`.
2. Simulate the last 31 days of daily usage logs, with urban facilities
   averaging 150 patients/day and rural facilities 35/day (+/-20%
   variation), and seasonal multipliers for cough syrup/paracetamol
   (winter) and ORS (summer).
3. Reset final inventory levels to one of three random "personas"
   (critical, surplus, or normal) so demo dashboards show varied stock
   health across facilities, again with fixed overrides for
   `rampur_mediflow_com`.

**Key assumption:** writes are batched at 400 per commit to stay under
Firestore's 500-operation batch limit; simulated geography is clustered
around Delhi NCR purely for demo map visuals and is not meant to represent
real facility locations.

## Related documentation

- [AI Tool-Calling Architecture](ai-tool-calling.md) documents the AI
  request flow that consumes some of this same data (inventory, usage
  logs) for forecasting and chat.
- [BigQuery Integration](bigquery.md) documents how requests and inventory
  changes (including those produced by simulation) are mirrored for
  analytics.
  