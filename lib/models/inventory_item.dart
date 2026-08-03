import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/inventory_thresholds.dart';

/// Canonical stock-status categories for a single inventory item.
///
/// The order of values is intentional: higher enum index = higher severity,
/// which allows simple comparisons such as `status.index >= ItemStatus.expiringSoon.index`.
enum ItemStatus {
  /// Stock levels and expiry are both acceptable.
  healthy,

  /// Remaining stock has dropped to or below [kLowStockPercentage] of the
  /// initial quantity, **or** fewer than [kLowStockAbsolute] units remain.
  lowStock,

  /// More than 70 % of stock remains but expiry is within [kExpiringSoonDays].
  wastageRisk,

  /// Expiry is within [kExpiringSoonDays] days but the item is **not** yet
  /// expired (days-to-expiry in `[0, kExpiringSoonDays]`).
  expiringSoon,

  /// The expiry date has passed (days-to-expiry < 0).
  expired,
}

class InventoryItem {
  final String id;
  final String medicineName;
  final String batchId;
  final DateTime arrivalDate;
  final DateTime expiryDate;
  final int initialQuantity;
  final int remainingQuantity;
  final String unit;
  final DateTime lastUpdated;
  final String? facilityId; // Added for global sync

  InventoryItem({
    required this.id,
    required this.medicineName,
    required this.batchId,
    required this.arrivalDate,
    required this.expiryDate,
    required this.initialQuantity,
    required this.remainingQuantity,
    required this.unit,
    required this.lastUpdated,
    this.facilityId,
  });

  // ── Classification thresholds ────────────────────────────────────────────

  /// Items expiring within this many days are flagged as [ItemStatus.expiringSoon]
  /// (or [ItemStatus.wastageRisk] when stock is also high).
  static const int kExpiringSoonDays = 30;

  /// Items at or below this fraction of their initial quantity are flagged as
  /// [ItemStatus.lowStock].
  static const double kLowStockPercentage =
      InventoryThresholds.lowStockPercentage;

  /// Items at or below this absolute unit count are flagged as
  /// [ItemStatus.lowStock] regardless of percentage (safety floor for small
  /// initial batches where the percentage check alone is too loose).
  static const int kLowStockAbsolute = InventoryThresholds.lowStockAbsolute;

  /// Fraction of stock remaining (0.0–1.0). Safe against divide-by-zero.
  double get remainingPercentage =>
      initialQuantity > 0 ? remainingQuantity / initialQuantity : 0.0;

  /// Days remaining until the expiry date. Negative values indicate expired stock.
  int get daysToExpiry => expiryDate.difference(DateTime.now()).inDays;

  /// Single source of truth for expired stock detection.
  bool get isExpired => daysToExpiry < 0;

  /// Single source of truth for low-stock detection across the whole app.
  /// An item is low stock if either:
  ///  - it has dropped to [kLowStockPercentage] or less of its initial
  ///    quantity, or
  ///  - fewer than [kLowStockAbsolute] units remain.
  bool get isLowStock =>
      remainingPercentage <= kLowStockPercentage ||
      remainingQuantity <= kLowStockAbsolute;

  /// Single source of truth for wastage risk detection
  /// (high stock nearing expiry).
  bool get isWastageRisk =>
      !isExpired &&
      daysToExpiry <= kExpiringSoonDays &&
      remainingPercentage >= 0.70;

  /// Single source of truth for expiring-soon detection
  /// (nearing expiry, not expired/wastageRisk).
  bool get isExpiringSoon =>
      !isExpired && !isWastageRisk && daysToExpiry <= kExpiringSoonDays;

  /// Single source of truth for the canonical stock-status of this item.
  ///
  /// Priority (highest to lowest):
  /// 1. [ItemStatus.expired]      — expiry date has passed.
  /// 2. [ItemStatus.lowStock]     — quantity is critically low.
  /// 3. [ItemStatus.wastageRisk]  — high stock + close to expiry.
  /// 4. [ItemStatus.expiringSoon] — close to expiry but stock is not high.
  /// 5. [ItemStatus.healthy]      — everything is fine.
  ///
  /// Note: "expiring soon" explicitly excludes already-expired items so
  /// that expired items are never double-counted in both [ItemStatus.expired]
  /// and [ItemStatus.expiringSoon].
  ItemStatus get status {
    if (isExpired) return ItemStatus.expired;
    if (isLowStock) return ItemStatus.lowStock;
    if (isWastageRisk) return ItemStatus.wastageRisk;
    if (isExpiringSoon) return ItemStatus.expiringSoon;
    return ItemStatus.healthy;
  }

  /// Display string for the stock status.
  String get statusText {
    switch (status) {
      case ItemStatus.expired:
        return 'Expired';
      case ItemStatus.lowStock:
        return 'Low Stock';
      case ItemStatus.wastageRisk:
        return 'Wastage Risk';
      case ItemStatus.expiringSoon:
        return 'Expiring Soon';
      case ItemStatus.healthy:
        return 'Healthy';
    }
  }

  /// `true` when the item has any non-healthy status — convenient for
  /// sidebar badge / alert-bell calculations.
  bool get hasAlert => status != ItemStatus.healthy;

  factory InventoryItem.fromMap(
    Map<String, dynamic> map,
    String id, {
    String? facilityId,
  }) {
    return InventoryItem(
      id: id,
      medicineName: map['medicineName']?.toString() ?? '',
      batchId: map['batchId']?.toString() ?? '',
      arrivalDate: map['arrivalDate'] is Timestamp
          ? (map['arrivalDate'] as Timestamp).toDate()
          : DateTime.now(),
      expiryDate: map['expiryDate'] is Timestamp
          ? (map['expiryDate'] as Timestamp).toDate()
          : DateTime.now(),
      initialQuantity: (map['initialQuantity'] as num?)?.toInt() ?? 0,
      remainingQuantity: (map['remainingQuantity'] as num?)?.toInt() ?? 0,
      unit: map['unit']?.toString() ?? 'units',
      lastUpdated: map['lastUpdated'] is Timestamp
          ? (map['lastUpdated'] as Timestamp).toDate()
          : DateTime.now(),
      facilityId: facilityId ?? map['facilityId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'medicineName': medicineName,
      'batchId': batchId,
      'arrivalDate': Timestamp.fromDate(arrivalDate),
      'expiryDate': Timestamp.fromDate(expiryDate),
      'initialQuantity': initialQuantity,
      'remainingQuantity': remainingQuantity,
      'unit': unit,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      if (facilityId != null) 'facilityId': facilityId,
    };
  }
}
