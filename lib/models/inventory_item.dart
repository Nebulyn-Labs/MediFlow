import 'package:cloud_firestore/cloud_firestore.dart';

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
  final bool requiresColdChain;

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
    this.requiresColdChain = false,
  });

  /// Fraction of stock remaining (0.0–1.0). Safe against divide-by-zero.
  double get remainingPercentage =>
      initialQuantity > 0 ? remainingQuantity / initialQuantity : 0.0;

  /// Single source of truth for low-stock detection across the whole app.
  /// An item is low stock if either:
  ///  - it has dropped to 20% or less of its initial quantity, or
  ///  - fewer than 500 units remain in absolute terms (safety floor for
  ///    small initial batches where the percentage check alone is too loose).
  bool get isLowStock =>
      remainingPercentage <= 0.20 || remainingQuantity <= 500;

  factory InventoryItem.fromMap(Map<String, dynamic> map, String id,
      {String? facilityId}) {
    return InventoryItem(
      id: id,
      medicineName: map['medicineName'] ?? '',
      batchId: map['batchId'] ?? '',
      arrivalDate: map['arrivalDate'] != null
          ? (map['arrivalDate'] as Timestamp).toDate()
          : DateTime.now(),
      expiryDate: map['expiryDate'] != null
          ? (map['expiryDate'] as Timestamp).toDate()
          : DateTime.now(),
      initialQuantity: map['initialQuantity']?.toInt() ?? 0,
      remainingQuantity: map['remainingQuantity']?.toInt() ?? 0,
      unit: map['unit'] ?? 'units',
      lastUpdated: map['lastUpdated'] != null
          ? (map['lastUpdated'] as Timestamp).toDate()
          : DateTime.now(),
      facilityId: facilityId ?? map['facilityId'],
      requiresColdChain: map['requiresColdChain'] ?? false,
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
      'requiresColdChain': requiresColdChain,
    };
  }
}
